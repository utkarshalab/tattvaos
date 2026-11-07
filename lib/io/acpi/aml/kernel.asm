; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/kernel.asm
; =============================================================================
; The AML interpreter inside the kernel: find the DSDT and SSDTs, give the
; interpreter memory and hooks, load the tables, and run start-up (_REG,
; _STA, _INI). Included by kernel/entry.asm after aml.asm.
;
; acpi_kernel_init runs once on the BSP from kernel_main, after interrupts
; are set up. Nothing in it stops the boot: a machine whose tables fail to
; load boots without ACPI devices and says why on the console.
;
; The sandbox (lib/io/acpi/ROADMAP.md, decision 3) is the region handler:
;   SystemMemory  only below the identity-mapped limit, never in usable RAM
;                 from the firmware memory map, never in the kernel image
;   SystemIO      ports 0-0xFFFF, except PCI configuration (0xCF8-0xCFF),
;                 which belongs to the PCI driver
;   anything else not yet: PCI configuration, the embedded controller and
;   the rest arrive with their drivers
; Refusals are counted, and the first one is printed.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_KERNEL_ASM
%define LIB_IO_ACPI_AML_KERNEL_ASM

%define ACPI_HEAP_PAGES     512         ; 2 MB for the interpreter
%define ACPI_MAX_SSDTS      32
%define ACPI_MAX_TABLE      0x1000000   ; 16 MB: larger is not a real table
%define ACPI_MAX_ROOT       1024        ; root table entries looked at

%define ACPI_SIG_RSDP       0x2052545020445352  ; "RSD PTR "
%define ACPI_SIG_XSDT       0x54445358  ; "XSDT"
%define ACPI_SIG_RSDT       0x54445352  ; "RSDT"
%define ACPI_SIG_FACP       0x50434146  ; "FACP"
%define ACPI_SIG_DSDT       0x54445344  ; "DSDT"
%define ACPI_SIG_SSDT       0x54445353  ; "SSDT"

%define ACPI_FADT_DSDT      40          ; 32-bit DSDT address
%define ACPI_FADT_X_DSDT    140         ; 64-bit DSDT address (FADT 2.0+)

section .bss
alignb 8
acpi_heap:          resq 1
acpi_limit:         resq 1              ; exclusive end of reachable memory
acpi_dsdt:          resq 1
acpi_ssdts:         resq ACPI_MAX_SSDTS
acpi_ssdt_count:    resd 1
global acpi_bad_checksums
acpi_bad_checksums: resd 1              ; tables used despite a bad checksum
global acpi_denied
acpi_denied:        resd 1              ; accesses the sandbox refused
global acpi_ready
acpi_ready:         resd 1              ; 1 once the namespace is loaded

section .data
align 8
; EDI = port, ESI = width in bits (8, 16, 32) → EAX
global acpi_port_in_fn
acpi_port_in_fn:    dq acpi_native_in
; EDI = port, ESI = width in bits, EDX = value
global acpi_port_out_fn
acpi_port_out_fn:   dq acpi_native_out
msg_acpi_no_rsdp:   db "ACPI: no valid RSDP; no ACPI devices", 0x0D, 0x0A, 0
msg_acpi_no_root:   db "ACPI: no valid XSDT or RSDT; no ACPI devices", 0x0D, 0x0A, 0
msg_acpi_no_dsdt:   db "ACPI: no valid DSDT; no ACPI devices", 0x0D, 0x0A, 0
msg_acpi_no_heap:   db "ACPI: no memory for the interpreter", 0x0D, 0x0A, 0
msg_acpi_checksum:  db "ACPI: table with a bad checksum used anyway: ", 0
msg_acpi_dsdt:      db "ACPI: DSDT ", 0
msg_acpi_ssdt:      db "ACPI: SSDT ", 0
msg_acpi_bytes:     db " bytes", 0
msg_acpi_loaded:    db " loaded", 0x0D, 0x0A, 0
msg_acpi_failed:    db " stopped with error -", 0
msg_acpi_at:        db " at offset ", 0
msg_acpi_devices:   db "ACPI: devices ", 0
msg_acpi_inis:      db ", _INI run ", 0
msg_acpi_errors:    db ", failures ", 0
msg_acpi_heap:      db ", interpreter memory ", 0
msg_acpi_crlf:      db 0x0D, 0x0A, 0
msg_acpi_denied:    db "ACPI: sandbox refused space ", 0
msg_acpi_address:   db " address ", 0
msg_acpi_sci_failed: db "ACPI: the SCI could not be routed; no ACPI events", 0x0D, 0x0A, 0
msg_acpi_found:     db "ACPI: present: ", 0
acpi_id_touchpad:   db "PNP0C50", 0
acpi_id_lid:        db "PNP0C0D", 0
acpi_id_power:      db "PNP0C0C", 0
acpi_id_ec:         db "PNP0C09", 0
acpi_id_battery:    db "PNP0C0A", 0
acpi_found_names:
    dq acpi_id_touchpad, acpi_id_lid, acpi_id_power, acpi_id_ec, acpi_id_battery, 0
msg_acpi_name_sep:  db " ", 0
acpi_name_buf:      db 0, 0, 0, 0, 0

section .text

; -----------------------------------------------------------------------------
; acpi_checksum — whether a table's bytes sum to zero
; Input:  RDI = table, ECX = length
; Output: ZF = 1 when they do
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
acpi_checksum:
    xor eax, eax
    xor edx, edx
.byte:
    test ecx, ecx
    jz .done
    add al, [rdi + rdx]
    inc edx
    dec ecx
    jmp .byte
.done:
    test al, al
    ret

; -----------------------------------------------------------------------------
; acpi_table_ok — a table header that lies inside reachable memory
; Input:  RDI = table, ESI = signature wanted (0 for any)
; Output: CF = 0 when usable; a bad checksum is counted and printed, and
;         the table is still used (firmware with a wrong checksum is common
;         and its tables otherwise work)
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
acpi_table_ok:
    test rdi, rdi
    jz .bad
    mov rax, rdi
    add rax, 36
    jc .bad
    cmp rax, [rel acpi_limit]
    ja .bad
    test esi, esi
    jz .any
    cmp [rdi], esi
    jne .bad
.any:
    mov ecx, [rdi + 4]
    cmp ecx, 36
    jb .bad
    cmp ecx, ACPI_MAX_TABLE
    ja .bad
    lea rax, [rdi + rcx]
    cmp rax, [rel acpi_limit]
    ja .bad
    call acpi_checksum
    jz .good
    inc dword [rel acpi_bad_checksums]
    push rsi
    lea rsi, [rel msg_acpi_checksum]
    call uart_print_str
    mov eax, [rdi]
    mov [rel acpi_name_buf], eax
    lea rsi, [rel acpi_name_buf]
    call uart_print_str
    lea rsi, [rel msg_acpi_crlf]
    call uart_print_str
    pop rsi
.good:
    clc
    ret
.bad:
    stc
    ret

; -----------------------------------------------------------------------------
; acpi_find_tables — the DSDT and the SSDTs, through RSDP, XSDT (or RSDT)
;                    and FADT
; Output: CF = 0 with acpi_dsdt set; CF = 1 with a message printed
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
acpi_find_tables:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [rel acpi_dsdt], 0
    mov dword [rel acpi_ssdt_count], 0
    xor r15d, r15d                      ; FADT
    ; RSDP from the boot loader
    mov rbx, [rel boot_info_ptr]
    test rbx, rbx
    jz .no_rsdp
    mov r12, [rbx + BOOT_INFO_ACPI_RSDP_OFF]
    test r12, r12
    jz .no_rsdp
    lea rax, [r12 + 36]
    cmp rax, [rel acpi_limit]
    ja .no_rsdp
    mov rax, ACPI_SIG_RSDP
    cmp [r12], rax
    jne .no_rsdp
    mov rdi, r12
    mov ecx, 20
    call acpi_checksum
    jnz .no_rsdp
    ; ACPI 2.0+: the XSDT with 8-byte entries; else the RSDT with 4
    cmp byte [r12 + 15], 2
    jb .rsdt
    mov rdi, [r12 + 24]
    mov esi, ACPI_SIG_XSDT
    call acpi_table_ok
    jc .rsdt
    mov r13, rdi
    mov r14d, 8
    jmp .root
.rsdt:
    mov edi, [r12 + 16]
    mov esi, ACPI_SIG_RSDT
    call acpi_table_ok
    jc .no_root
    mov r13, rdi
    mov r14d, 4
.root:
    mov eax, [r13 + 4]
    sub eax, 36
    xor edx, edx
    div r14d
    cmp eax, ACPI_MAX_ROOT
    jbe .count
    mov eax, ACPI_MAX_ROOT
.count:
    mov ebx, eax                        ; entries
    lea r12, [r13 + 36]
.entry:
    test ebx, ebx
    jz .entries_done
    dec ebx
    cmp r14d, 8
    jne .entry32
    mov rdi, [r12]
    jmp .have
.entry32:
    mov edi, [r12]
.have:
    add r12, r14
    xor esi, esi
    call acpi_table_ok
    jc .entry
    mov eax, [rdi]
    cmp eax, ACPI_SIG_FACP
    jne .ssdt
    test r15, r15
    jnz .entry                          ; the first FADT counts
    mov r15, rdi
    jmp .entry
.ssdt:
    cmp eax, ACPI_SIG_SSDT
    jne .entry
    mov eax, [rel acpi_ssdt_count]
    cmp eax, ACPI_MAX_SSDTS
    jae .entry
    lea rcx, [rel acpi_ssdts]
    mov [rcx + rax * 8], rdi
    inc dword [rel acpi_ssdt_count]
    jmp .entry
.entries_done:
    ; the DSDT: X_DSDT when the FADT is long enough and sets it
    mov [rel acpi_fadt], r15            ; events.asm reads its event blocks
    test r15, r15
    jz .no_dsdt
    xor edi, edi
    cmp dword [r15 + 4], ACPI_FADT_X_DSDT + 8
    jb .dsdt32
    mov rdi, [r15 + ACPI_FADT_X_DSDT]
.dsdt32:
    test rdi, rdi
    jnz .dsdt
    mov edi, [r15 + ACPI_FADT_DSDT]
.dsdt:
    mov esi, ACPI_SIG_DSDT
    call acpi_table_ok
    jc .no_dsdt
    mov [rel acpi_dsdt], rdi
    clc
    jmp .out
.no_rsdp:
    lea rsi, [rel msg_acpi_no_rsdp]
    jmp .fail
.no_root:
    lea rsi, [rel msg_acpi_no_root]
    jmp .fail
.no_dsdt:
    lea rsi, [rel msg_acpi_no_dsdt]
.fail:
    call uart_print_str
    stc
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_load_one — load one table and say how it went
; Input:  RDI = table, RSI = its label ("ACPI: DSDT ")
; -----------------------------------------------------------------------------
acpi_load_one:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call uart_print_str
    mov eax, [rbx + 4]
    call uart_print_dec
    lea rsi, [rel msg_acpi_bytes]
    call uart_print_str
    mov rdi, rbx
    call aml_load
    test eax, eax
    jnz .failed
    lea rsi, [rel msg_acpi_loaded]
    call uart_print_str
    jmp .out
.failed:
    mov r12d, eax
    lea rsi, [rel msg_acpi_failed]
    call uart_print_str
    mov eax, r12d
    neg eax
    call uart_print_dec
    lea rsi, [rel msg_acpi_at]
    call uart_print_str
    mov rax, [rel aml_fail_offset]
    call uart_print_hex64
    lea rsi, [rel msg_acpi_crlf]
    call uart_print_str
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_kernel_init — load the namespace and run start-up
; -----------------------------------------------------------------------------
global acpi_kernel_init
acpi_kernel_init:
    push rbx
    push r12
    sub rsp, 8
    mov dword [rel acpi_ready], 0
    mov rax, [rel phys_state + phys_state_t.direct_map_limit]
    mov [rel acpi_limit], rax
    call acpi_find_tables
    jc .out

    mov rdi, ACPI_HEAP_PAGES
    call phys_alloc_pages
    test rax, rax
    jz .no_heap
    mov [rel acpi_heap], rax
    mov rdi, rax
    mov rsi, ACPI_HEAP_PAGES * 4096
    call aml_init
    test eax, eax
    jnz .no_heap
    ; a new namespace: nothing queued for the old one survives
    mov dword [rel acpi_notify_head], 0
    mov dword [rel acpi_notify_tail], 0
    mov dword [rel acpi_events_ready], 0

    lea rax, [rel acpi_kernel_region]
    mov [rel aml_region_fn], rax
    lea rax, [rel acpi_events_notify]   ; queued; handled after the method
    mov [rel aml_notify_fn], rax
    lea rax, [rel acpi_kernel_sleep]
    mov [rel aml_sleep_fn], rax
    lea rax, [rel mono_get_nanos]
    mov [rel aml_clock_fn], rax

    mov rdi, [rel acpi_dsdt]
    lea rsi, [rel msg_acpi_dsdt]
    call acpi_load_one
    xor ebx, ebx
.ssdt:
    cmp ebx, [rel acpi_ssdt_count]
    jae .loaded
    lea rax, [rel acpi_ssdts]
    mov rdi, [rax + rbx * 8]
    lea rsi, [rel msg_acpi_ssdt]
    call acpi_load_one
    inc ebx
    jmp .ssdt
.loaded:
    ; memory and I/O have their handler now, and the embedded controller
    ; once found; the rest come with their drivers
    call acpi_ec_init
    xor edi, edi
    call aml_run_reg
    mov edi, 1
    call aml_run_reg
    cmp dword [rel acpi_ec_ready], 0
    je .initialize
    mov edi, 3
    call aml_run_reg
.initialize:
    call aml_initialize
    mov dword [rel acpi_ready], 1

    lea rsi, [rel msg_acpi_devices]
    call uart_print_str
    mov eax, [rel aml_init_devices]
    call uart_print_dec
    lea rsi, [rel msg_acpi_inis]
    call uart_print_str
    mov eax, [rel aml_init_inis]
    call uart_print_dec
    lea rsi, [rel msg_acpi_errors]
    call uart_print_str
    mov eax, [rel aml_init_errors]
    call uart_print_dec
    lea rsi, [rel msg_acpi_heap]
    call uart_print_str
    call aml_heap_used
    call uart_print_dec
    lea rsi, [rel msg_acpi_bytes]
    call uart_print_str
    lea rsi, [rel msg_acpi_crlf]
    call uart_print_str

    ; which of the devices the next drivers need are present
    lea rsi, [rel msg_acpi_found]
    call uart_print_str
    lea r12, [rel acpi_found_names]
.find:
    mov rdi, [r12]
    test rdi, rdi
    jz .found_done
    xor esi, esi
    call aml_find_device
    test rax, rax
    jz .next_id
    mov rsi, [r12]
    call uart_print_str
    lea rsi, [rel msg_acpi_name_sep]
    call uart_print_str
.next_id:
    add r12, 8
    jmp .find
.found_done:
    lea rsi, [rel msg_acpi_crlf]
    call uart_print_str
    ; batteries, the adapter, thermal zones: read once (Notify refreshes)
    call acpi_power_init
    ; events: GPEs and buttons, then the SCI
    call acpi_events_init
    test eax, eax
    jnz .out
    call acpi_events_start
    jmp .out
.no_heap:
    lea rsi, [rel msg_acpi_no_heap]
    call uart_print_str
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ram_overlap — whether [RSI, RDX) touches usable RAM or the kernel
; Output: CF = 1 when it does
; Clobbers: RAX, RCX, R9, R10, R11
; -----------------------------------------------------------------------------
acpi_ram_overlap:
    ; the kernel image, whatever the map says
    lea rax, [rel kernel_bss_end]
    cmp rsi, rax
    jae .map
    lea rax, [rel kernel_text_start]
    cmp rdx, rax
    ja .yes
.map:
    mov r9, [rel boot_info_ptr]
    test r9, r9
    jz .no
    mov ecx, [r9 + BOOT_INFO_E820_COUNT_OFF]
    cmp ecx, PHYS_E820_MAX_ENTRIES
    jbe .count
    mov ecx, PHYS_E820_MAX_ENTRIES
.count:
    mov r9, [r9 + BOOT_INFO_E820_PTR_OFF]
    test r9, r9
    jz .no
.entry:
    test ecx, ecx
    jz .no
    dec ecx
    cmp dword [r9 + e820_entry.type], 1
    jne .next
    mov r10, [r9 + e820_entry.base]
    mov r11, [r9 + e820_entry.length]
    add r11, r10                        ; entry end
    cmp rsi, r11
    jae .next
    cmp rdx, r10
    ja .yes
.next:
    add r9, e820_entry_size
    jmp .entry
.no:
    clc
    ret
.yes:
    stc
    ret

; -----------------------------------------------------------------------------
; acpi_kernel_region — aml_region_fn: one access unit, inside the sandbox
; Input:  RDI = space, RSI = address, EDX = width in bits, ECX = 1 write,
;         R8 = u64*
; Output: EAX = 0, -AML_EDENIED or -AML_EUNSUPPORTED
; -----------------------------------------------------------------------------
acpi_kernel_region:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi                        ; space
    mov r12, rsi                        ; address
    mov r13d, edx                       ; bits
    mov r14d, ecx                       ; write
    mov r15, r8
    cmp ebx, 0
    je .memory
    cmp ebx, 1
    je .io
    cmp ebx, 3
    jne .other_space
    mov edi, ebx
    mov rsi, r12
    mov edx, r13d
    mov ecx, r14d
    mov r8, r15
    call acpi_ec_region
    jmp .out
.other_space:
    mov eax, -AML_EUNSUPPORTED
    jmp .out

.memory:
    mov edx, r13d
    shr edx, 3
    mov rsi, r12
    lea rdx, [r12 + rdx]                ; end
    cmp rdx, rsi
    jb .denied                          ; wrapped
    cmp rdx, [rel acpi_limit]
    ja .denied
    call acpi_ram_overlap
    jc .denied
    test r14d, r14d
    jnz .mem_write
    cmp r13d, 8
    je .mr8
    cmp r13d, 16
    je .mr16
    cmp r13d, 32
    je .mr32
    mov rax, [r12]
    jmp .mr
.mr8:
    movzx eax, byte [r12]
    jmp .mr
.mr16:
    movzx eax, word [r12]
    jmp .mr
.mr32:
    mov eax, [r12]
.mr:
    mov [r15], rax
    jmp .ok
.mem_write:
    mov rax, [r15]
    cmp r13d, 8
    je .mw8
    cmp r13d, 16
    je .mw16
    cmp r13d, 32
    je .mw32
    mov [r12], rax
    jmp .ok
.mw8:
    mov [r12], al
    jmp .ok
.mw16:
    mov [r12], ax
    jmp .ok
.mw32:
    mov [r12], eax
    jmp .ok

.io:
    cmp r13d, 64
    je .unsupported                     ; no 64-bit port access
    mov eax, r13d
    shr eax, 3
    lea rcx, [r12 + rax - 1]            ; last port
    cmp rcx, 0xFFFF
    ja .denied
    cmp rcx, 0xCF8                      ; PCI configuration ports
    jb .io_ok
    cmp r12, 0xCFF
    jbe .denied
.io_ok:
    mov edi, r12d
    mov esi, r13d
    test r14d, r14d
    jnz .io_write
    call acpi_in
    mov [r15], rax
    jmp .ok
.io_write:
    mov edx, [r15]
    call acpi_out
    jmp .ok

.denied:
    inc dword [rel acpi_denied]
    cmp dword [rel acpi_denied], 1
    jne .denied_quiet
    lea rsi, [rel msg_acpi_denied]
    call uart_print_str
    mov eax, ebx
    call uart_print_dec
    lea rsi, [rel msg_acpi_address]
    call uart_print_str
    mov rax, r12
    call uart_print_hex64
    lea rsi, [rel msg_acpi_crlf]
    call uart_print_str
.denied_quiet:
    mov eax, -AML_EDENIED
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
    jmp .out
.ok:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_native_in, acpi_native_out — the real port instructions (8, 16, 32)
; -----------------------------------------------------------------------------
acpi_native_in:
    mov edx, edi
    xor eax, eax
    cmp esi, 8
    je .b
    cmp esi, 16
    je .w
    in eax, dx
    ret
.b:
    in al, dx
    ret
.w:
    in ax, dx
    ret

acpi_native_out:
    mov eax, edx
    mov edx, edi
    cmp esi, 8
    je .b
    cmp esi, 16
    je .w
    out dx, eax
    ret
.b:
    out dx, al
    ret
.w:
    out dx, ax
    ret

; -----------------------------------------------------------------------------
; acpi_events_start — route the SCI to its handler (after acpi_events_init)
; The SCI is level-triggered and active low unless the MADT overrides it;
; ioapic_route_sci applies that rule.
; -----------------------------------------------------------------------------
acpi_events_start:
    push rbx
    call vector_alloc
    cmp eax, IOAPIC_VECTOR_FIRST
    jb .fail
    cmp eax, IOAPIC_VECTOR_LAST
    ja .fail
    mov ebx, eax
    mov edi, eax
    lea rsi, [rel acpi_ev_sci_isr]
    xor edx, edx
    call register_idt_handler
    mov edi, [rel acpi_sci_int]
    mov esi, ebx
    mov edx, [rel smp_bsp_apic_id]
    xor ecx, ecx
    call ioapic_route_sci
    jnc .out
.fail:
    lea rsi, [rel msg_acpi_sci_failed]
    call uart_print_str
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ev_sci_isr — the SCI: mask and mark what fired; the fiber does the rest
; -----------------------------------------------------------------------------
acpi_ev_sci_isr:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    cld
    call acpi_ev_sci_irq
    call smp_lapic_eoi
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    iretq

; -----------------------------------------------------------------------------
; acpi_kernel_sleep — aml_sleep_fn: wait RDI nanoseconds (Sleep, Stall)
; Start-up runs on the BSP alone, so a spin wait is acceptable here.
; -----------------------------------------------------------------------------
acpi_kernel_sleep:
    sub rsp, 8
    mov rax, rdi
    xor edx, edx
    mov ecx, 1000
    div rcx                             ; microseconds
    lea rdi, [rax + 1]
    call udelay
    add rsp, 8
    ret

%include "lib/io/acpi/aml/events.asm"
%include "lib/io/acpi/aml/ec.asm"
%include "lib/io/acpi/aml/power.asm"

%endif ; LIB_IO_ACPI_AML_KERNEL_ASM
