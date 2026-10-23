; =============================================================================
; Utkarsha OS — boot/stage2/cpu/longmode.asm
; =============================================================================
; Verify long mode is supported and enter it.
; Must be called after GDT and paging are set up.
;
; Long mode entry sequence (STRICT ORDER — do not reorder):
;   1. Set PAE bit in CR4         (bit 5)
;   2. Load PML4 address into CR3
;   3. Set LME bit in EFER MSR   (MSR 0xC0000080, bit 8)
;   4. Enable paging + protected mode in CR0 simultaneously
;   5. Far jump to 64-bit code segment
;   6. Reload segment registers in 64-bit code
;   7. Enable SSE/AVX
;
; Any other order = triple fault with no error message.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit) → long mode (64-bit)
; =============================================================================

%ifndef LONGMODE_ASM
%define LONGMODE_ASM

; MSR addresses
MSR_EFER        equ 0xC0000080      ; Extended Feature Enable Register
EFER_LME        equ (1 << 8)        ; Long Mode Enable bit
EFER_LMA        equ (1 << 10)       ; Long Mode Active bit (read-only)
EFER_NXE        equ (1 << 11)       ; No-Execute Enable bit

; CR0 bits
CR0_PE          equ (1 << 0)        ; Protected mode Enable
CR0_MP          equ (1 << 1)        ; Monitor coProcessor
CR0_EM          equ (1 << 2)        ; EMulation (clear for SSE)
CR0_TS          equ (1 << 3)        ; Task Switched (clear for SIMD)
CR0_NE          equ (1 << 5)        ; Native x87 exception reporting
CR0_WP          equ (1 << 16)       ; supervisor write-protect enforcement
CR0_PG          equ (1 << 31)       ; Paging enable

; CR4 bits
CR4_PAE         equ (1 << 5)        ; Physical Address Extension
CR4_OSFXSR      equ (1 << 9)        ; OS support for FXSAVE/FXRSTOR
CR4_OSXMMEXCPT  equ (1 << 10)       ; OS support for SIMD exceptions
CR4_OSXSAVE     equ (1 << 18)       ; OS support for XSAVE (for AVX)

; =============================================================================
; longmode_check — verify CPU supports long mode
; Input:  [FEATURES_DEST] filled by cpu_detect
; Output: CF=0 supported, CF=1 not supported
; =============================================================================
longmode_check:
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_LM
    jz .not_supported
    clc
    ret
.not_supported:
    stc
    ret

[BITS 32]
; =============================================================================
; longmode_enter — switch from protected mode to long mode
; Input:  GDT loaded, paging set up, PML4 at PAGING_PML4
; Output: never returns in protected mode
;         execution continues in 64-bit code after far jump
; =============================================================================
longmode_enter:
    cli

    ; Mask the legacy NMI source across the interval where the 32-bit IDT gate
    ; format no longer matches the active mode. Restore the exact CMOS index
    ; byte only after a valid 64-bit IDT has passed its round-trip test.
    in al, 0x70
    mov [longmode_cmos_index], al
    or al, 0x80
    out 0x70, al

    ; The entry contract is protected mode with paging still disabled.
    mov eax, cr0
    test eax, CR0_PE
    jz longmode_fail_pm32
    test eax, CR0_PG
    jnz longmode_fail_pm32

    ; -------------------------------------------------------------------------
    ; STEP 1: Enable PAE in CR4
    ; PAE must be set before loading CR3 or enabling LME
    ; -------------------------------------------------------------------------
    mov eax, cr4
    or eax, CR4_PAE                 ; set PAE bit
    or eax, CR4_OSFXSR              ; enable FXSAVE/FXRSTOR (for SSE)
    or eax, CR4_OSXMMEXCPT          ; enable SIMD exception handling
    mov cr4, eax

    ; -------------------------------------------------------------------------
    ; STEP 2: Load PML4 physical address into CR3
    ; CR3 = physical address of PML4 page table
    ; Bits 11:0 of CR3 are control flags (cache disable, etc.)
    ; We use 0 for flags (enable caching, write-back)
    ; -------------------------------------------------------------------------
    mov eax, PAGING_PML4            ; PML4 physical address
    mov cr3, eax


    ; -------------------------------------------------------------------------
    ; STEP 3: Enable LME in EFER MSR
    ; Read EFER, set LME bit, write back
    ; Also enable NXE if CPU supports NX
    ; -------------------------------------------------------------------------
    mov ecx, MSR_EFER
    rdmsr                           ; EDX:EAX = EFER
    or eax, EFER_LME                ; set Long Mode Enable
    and eax, ~EFER_NXE              ; policy below decides whether NXE is legal

    ; enable NX if supported
    mov ebx, [FEATURES_DEST]
    test ebx, CPU_FEAT_NX
    jz .no_nx_enable
    or eax, EFER_NXE                ; set No-Execute Enable
.no_nx_enable:
    wrmsr                           ; write back EFER

    ; Read back the MSR before making the irreversible CR0.PG transition.
    rdmsr
    test eax, EFER_LME
    jz longmode_fail_pm32
    test ebx, CPU_FEAT_NX
    jz .verify_nxe_clear
    test eax, EFER_NXE
    jz longmode_fail_pm32
    jmp .efer_verified
.verify_nxe_clear:
    test eax, EFER_NXE
    jnz longmode_fail_pm32
.efer_verified:


    ; -------------------------------------------------------------------------
    ; STEP 4: Enable paging and protected mode simultaneously in CR0
    ; CRITICAL: must set PG and PE in the same write
    ; Both bits set in one mov cr0 instruction
    ; -------------------------------------------------------------------------
    mov eax, cr0
    or eax, (CR0_PE | CR0_PG | CR0_WP | CR0_NE | CR0_MP)
    and eax, ~(CR0_EM | CR0_TS)
    mov cr0, eax


    ; -------------------------------------------------------------------------
    ; STEP 5: Far jump to 64-bit code segment
    ; This flushes the instruction pipeline and activates long mode.
    ; SEL_CODE64 = 0x08 (64-bit code descriptor in GDT)
    ; longmode_64 = entry point in 64-bit code
    ; -------------------------------------------------------------------------
    jmp SEL_CODE64:longmode_64

longmode_fail_pm32:
    mov esi, msg_longmode_verify_fail_pm
    call uart_print_pm
.halt:
    cli
    hlt
    jmp .halt

msg_longmode_verify_fail_pm:
    db "Long-mode transition verify: FAIL (pre-transition)", 0x0D, 0x0A, 0

; =============================================================================
; longmode_64 — we are now in 64-bit long mode
; All code below is [BITS 64]
; =============================================================================
[BITS 64]
longmode_64:
    mov rsp, STACK_LONG             ; known mapped stack before the first call

    ; Install a valid 16-byte-gate IDT before doing any work that could fault.
    ; The protected-mode IDT retained across the jump is not valid in IA-32e.
    call idt64_init

    ; -------------------------------------------------------------------------
    ; STEP 6: Reload all data segment registers
    ; After far jump: CS is loaded with 64-bit descriptor
    ; DS/ES/FS/GS/SS still have protected mode values
    ; Must reload with 64-bit data selector
    ; Forgetting ANY segment = subtle corruption bugs
    ; -------------------------------------------------------------------------
    mov ax, SEL_DATA64              ; 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    call idt64_selftest
    jc .transition_failed
    mov al, [rel longmode_cmos_index]
    out 0x70, al                    ; restore prior NMI mask + CMOS index
    lea rsi, [rel msg_idt64_ok]
    call uart_print_64

    call longmode_verify_state
    jc .transition_failed
    lea rsi, [rel msg_longmode_verify_ok]
    call uart_print_64

    ; Physical KASLR remains disabled until relocation covers the complete
    ; validated ULF v2 file+BSS footprint and warm recovery can reproduce the
    ; same mapping.  The legacy PT0 path covers only 1 MiB and used metadata
    ; from the reread header before the final whole-image checksum.
    mov dword [BOOT_INFO_ADDR + 20], 0

    ; -------------------------------------------------------------------------
    ; STEP 8: Print confirmation via UART
    ; (UART still works in long mode, same port I/O)
    ; -------------------------------------------------------------------------
    mov rsi, msg_longmode_ok
    call uart_print_64              ; note: uart_print needs 64-bit version

    ; Run 64-bit survive unit test
    call test_survive
    jc .survive_test_failed

    ; -------------------------------------------------------------------------
    ; STEP 9: Load and jump to kernel
    ; Copy kernel from real-mode temp buffer (0x20000) to randomized physical address
    ; -------------------------------------------------------------------------
    mov rsi, msg_kernel_load
    call uart_print_64

    ; -------------------------------------------------------------------------
    ; KASLR relocation, skipped when no randomized address was chosen.
    ;
    ; BOOT_INFO_KASLR_PHYS is a dword and the qword immediately after it holds
    ; the ACPI RSDP pointer, so this has to be a 32-bit load. Reading eight
    ; bytes pulled the RSDP's low half into the high half of the address and
    ; turned a field nothing had set into a plausible-looking nonzero
    ; destination — which then got used both as a memcpy target and as the
    ; physical base for virtual 1MB-2MB.
    ;
    ; Nothing sets the field yet, so the branch below is the live path:
    ; kernel_stream_load already placed the image at KERNEL_LOAD while still in
    ; real mode, and there is nothing left to copy or remap.
    ; -------------------------------------------------------------------------
    xor edi, edi
    mov edi, [BOOT_INFO_ADDR + 20]  ; 32-bit load, zero-extended into RDI
    test rdi, rdi
    jz .kernel_in_place

    push rdi
    call kernel_load                ; relocate KERNEL_LOAD → phys_dest
    pop rbx                         ; RBX = phys_dest

    ; Repoint virtual 1MB-2MB at the new physical home. Only the first
    ; megabyte: PT0 is the sole 4KB-granular table, and everything above 2MB
    ; is covered by the identity huge pages, so a randomized base would have to
    ; stay 2MB-aligned for the rest of the image to follow.
    push r8
    push r9
    push r10
    mov rdi, PAGING_PT0 + 256 * 8   ; pointer to entry 256 of PT0
    mov rcx, 256                    ; 256 entries (1MB)
    mov r8d, KERNEL_LOAD            ; current virtual page
    mov r9d, [KERNEL_LOAD + ULF_EXEC_SIZE_OFF]
    add r9d, KERNEL_LOAD            ; executable-prefix exclusive end
    xor r10d, r10d
    test dword [FEATURES_DEST], CPU_FEAT_NX
    jz .kaslr_nx_ready
    mov r10d, PTE_NX_BIT
.kaslr_nx_ready:

.update_kaslr_page_table:
    mov rax, rbx
    or rax, 0x03                    ; present + read/write
    mov [rdi], rax
    mov [rdi + 4], r10d             ; data tail is NX when supported
    cmp r8d, r9d
    jae .kaslr_page_done
    and dword [rdi], ~0x02          ; relocated executable prefix is RX
    mov dword [rdi + 4], 0          ; declared executable prefix
.kaslr_page_done:
    
    add rbx, 0x1000                 ; next physical page (4KB)
    add r8d, 0x1000                 ; next virtual page
    add rdi, 8                      ; next page table entry
    dec rcx
    jnz .update_kaslr_page_table

    pop r10
    pop r9
    pop r8

    ; Flush TLB by reloading CR3
    mov rax, cr3
    mov cr3, rax

.kernel_in_place:

    ; The legacy BIOS filesystem reader stages a fixed 64 KiB initrd below
    ; 1 MiB.  Its permanent destination begins immediately after the largest
    ; ULF v2 kernel footprint accepted by this loader, so it cannot overlap BSS.
    xor rax, rax
    mov al, [rel initrd_loaded]
    test al, al
    jz .skip_initrd_copy

    mov rsi, 0x40000                ; source: 0x40000 (loaded in real mode segment 0x4000)
    mov rdi, INITRD_LOAD
    xor rcx, rcx
    mov ecx, [rel initrd_size]
    add rcx, 7
    shr rcx, 3                      ; quadword count
    cld
    rep movsq

    ; Populate BootInfo fields
    mov rdi, BOOT_INFO_ADDR
    mov qword [rdi + 56], INITRD_LOAD ; BOOT_INFO_INITRD_ADDR
    xor rax, rax
    mov eax, [rel initrd_size]
    mov [rdi + 64], rax             ; BOOT_INFO_INITRD_SIZE
    jmp .initrd_done

.skip_initrd_copy:
    mov rdi, BOOT_INFO_ADDR
    mov qword [rdi + 56], 0
    mov qword [rdi + 64], 0

.initrd_done:

    ; 1. Verify ULF magic number at KERNEL_LOAD (0x100000)
    mov eax, [KERNEL_LOAD + ULF_MAGIC_OFF]
    cmp eax, ULF_MAGIC              ; check if it matches "ULF\0"
    jne .ulf_bad_magic

    ; 2. Verify exact on-disk size constraints.
    mov ecx, [KERNEL_LOAD + ULF_IMAGE_SIZE_OFF]
    test ecx, 7                     ; must be 8-byte aligned
    jnz .ulf_bad_size
    cmp ecx, ULF_HEADER_SIZE
    jb .ulf_bad_size
    cmp ecx, ULF_MAX_IMAGE_BYTES
    ja .ulf_bad_size

    ; 3. Verify Checksum
    mov rsi, KERNEL_LOAD
    mov ebx, ecx
    shr ebx, 3                      ; rbx = number of 8-byte quadwords
    jz .checksum_done
    
    xor rax, rax                    ; rax = calculated sum
    xor rdx, rdx                    ; rdx = current offset

.checksum_loop:
    cmp rdx, ULF_CHECKSUM_OFF       ; checksum field is counted as zero
    je .skip_field
    add rax, [rsi + rdx]
.skip_field:
    add rdx, 8
    dec rbx
    jnz .checksum_loop

.checksum_done:
    mov r8, [KERNEL_LOAD + ULF_CHECKSUM_OFF]
    cmp rax, r8
    jne .ulf_bad_checksum

    ; 4. Validate the executable extent, version, and control-flow target at
    ; the final trust boundary, after the complete image passed its checksum.
    cmp dword [KERNEL_LOAD + ULF_VERSION_OFF], ULF_VERSION
    jne .ulf_bad_header
    mov edx, [KERNEL_LOAD + ULF_EXEC_SIZE_OFF]
    cmp edx, ULF_HEADER_SIZE
    jb .ulf_bad_header
    test edx, ULF_EXEC_ALIGN - 1
    jnz .ulf_bad_header
    cmp edx, ecx
    ja .ulf_bad_header
    cmp edx, ULF_MAX_EXEC_BYTES
    ja .ulf_bad_header
    mov rax, [KERNEL_LOAD + ULF_ENTRY_OFF]
    cmp rax, KERNEL_LOAD + ULF_HEADER_SIZE
    jb .ulf_bad_entry
    add rdx, KERNEL_LOAD
    cmp rax, rdx
    jae .ulf_bad_entry

    ; ULF v2 makes the complete initialized-data+BSS footprint explicit.
    ; Bound it before using it, then zero everything not present in the file,
    ; including allocation-page padding.  The initial BIOS path otherwise
    ; inherits whatever happened to be in those physical pages.
    cmp dword [KERNEL_LOAD + ULF_MEMORY_SIZE_OFF + 4], 0
    jne .ulf_bad_header
    mov edx, [KERNEL_LOAD + ULF_MEMORY_SIZE_OFF]
    cmp edx, ecx
    jb .ulf_bad_header
    test edx, 7
    jnz .ulf_bad_header
    cmp edx, ULF_MAX_MEMORY_BYTES
    ja .ulf_bad_header

    mov r9d, edx
    add r9, 4095
    jc .ulf_bad_header
    and r9, -4096                  ; page-rounded footprint length
    add r9, KERNEL_LOAD
    jc .ulf_bad_header
    mov edi, KERNEL_LOAD
    add rdi, rcx                   ; first byte absent from the file
    cmp rdi, r9
    ja .ulf_bad_header
    mov rcx, r9
    sub rcx, rdi
    xor eax, eax
    cld
    rep stosb

    ; 5. Print success and dynamic jump
    mov rsi, msg_kernel_ok
    call uart_print_64

    ; Perform Measured Boot TPM measurements
    call tpm_measure_all

    ; Save the pristine state snapshot and register the panic vector
    call survive_snapshot_save
    call survive_vector_install

    ; 4. Retrieve dynamic entry point from header (offset 8)
    mov rax, [KERNEL_LOAD + ULF_ENTRY_OFF]

    mov rdi, BOOT_INFO_ADDR         ; Pass BootInfo pointer in RDI (System V ABI)
    jmp rax                         ; jump dynamically!

.ulf_bad_magic:
    mov rsi, msg_ulf_err_magic
    call uart_print_64
    jmp .halt

.ulf_bad_size:
    mov rsi, msg_ulf_err_size
    call uart_print_64
    jmp .halt

.ulf_bad_checksum:
    mov rsi, msg_ulf_err_checksum
    call uart_print_64
    jmp .halt

.ulf_bad_entry:
    mov rsi, msg_ulf_err_entry
    call uart_print_64
    jmp .halt

.ulf_bad_header:
    mov rsi, msg_ulf_err_header
    call uart_print_64
    jmp .halt

.transition_failed:
    lea rsi, [rel msg_longmode_verify_fail]
    call uart_print_64
    jmp .halt

.survive_test_failed:
    lea rsi, [rel msg_survive_test_halt]
    call uart_print_64
    jmp .halt

.halt:
    cli
    hlt
    jmp .halt

    ; never reaches here
    cli
    hlt

; =============================================================================
; longmode_verify_state — prove the architectural transition state before the
; loader performs any optional relocation or transfers control to the kernel.
; Output: CF=0 valid, CF=1 invalid. Preserves all GPRs.
; =============================================================================
longmode_verify_state:
    push rax
    push rbx
    push rcx
    push rdx

    mov ax, cs
    cmp ax, SEL_CODE64
    jne .failed
    mov ax, ds
    cmp ax, SEL_DATA64
    jne .failed
    mov ax, es
    cmp ax, SEL_DATA64
    jne .failed
    mov ax, ss
    cmp ax, SEL_DATA64
    jne .failed

    mov rax, cr0
    mov ebx, eax
    and ebx, CR0_PE | CR0_PG | CR0_WP | CR0_NE | CR0_MP
    cmp ebx, CR0_PE | CR0_PG | CR0_WP | CR0_NE | CR0_MP
    jne .failed
    test eax, CR0_EM | CR0_TS
    jnz .failed

    mov rax, cr4
    mov ebx, eax
    and ebx, CR4_PAE | CR4_OSFXSR | CR4_OSXMMEXCPT
    cmp ebx, CR4_PAE | CR4_OSFXSR | CR4_OSXMMEXCPT
    jne .failed

    mov rbx, cr3
    and rbx, -4096
    cmp rbx, PAGING_PML4
    jne .failed

    mov ecx, MSR_EFER
    rdmsr
    mov ebx, eax
    and ebx, EFER_LME | EFER_LMA
    cmp ebx, EFER_LME | EFER_LMA
    jne .failed

    test dword [FEATURES_DEST], CPU_FEAT_NX
    jz .expect_nxe_clear
    test eax, EFER_NXE
    jz .failed
    jmp .check_avx
.expect_nxe_clear:
    test eax, EFER_NXE
    jnz .failed

.check_avx:
    test dword [FEATURES_DEST], CPU_FEAT_AVX
    jz .check_interrupts
    mov rax, cr4
    test rax, CR4_OSXSAVE
    jz .failed
    xor ecx, ecx
    xgetbv
    and eax, 0x07
    cmp eax, 0x07
    jne .failed

.check_interrupts:
    pushfq
    pop rax
    test rax, (1 << 9)              ; IF must stay clear until kernel IDT setup
    jnz .failed

    pop rdx
    pop rcx
    pop rbx
    pop rax
    clc
    ret

.failed:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    stc
    ret


; =============================================================================
; Data (in 64-bit section)
; =============================================================================
msg_idt64_ok:       db "IDT64 verify: OK", 0x0D, 0x0A, 0
msg_longmode_verify_ok:
    db "Long-mode transition verify: OK", 0x0D, 0x0A, 0
msg_longmode_verify_fail:
    db "Long-mode transition verify: FAIL", 0x0D, 0x0A, 0
msg_survive_test_halt:
    db "HALT: survive snapshot self-test failed", 0x0D, 0x0A, 0
longmode_cmos_index: db 0
msg_longmode_ok:    db "Long mode OK", 0x0D, 0x0A, 0
msg_kernel_load:    db "Kernel... ", 0
msg_crlf:           db 0x0D, 0x0A, 0
msg_kernel_ok:      db "OK", 0x0D, 0x0A, 0
msg_ulf_err_magic:  db "FAIL (Bad Magic)", 0x0D, 0x0A, 0
msg_ulf_err_size:   db "FAIL (Bad Size)", 0x0D, 0x0A, 0
msg_ulf_err_checksum:db "FAIL (Bad Checksum)", 0x0D, 0x0A, 0
msg_ulf_err_entry:   db "FAIL (Invalid Entry Point)", 0x0D, 0x0A, 0
msg_ulf_err_header:  db "FAIL (Unsupported ULF Header)", 0x0D, 0x0A, 0

; Switch back to 16-bit for rest of stage2
[BITS 16]

%endif ; LONGMODE_ASM
