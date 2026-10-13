%ifndef KERNEL_ARCH_X86_64_MADT_ASM
%define KERNEL_ARCH_X86_64_MADT_ASM
; =============================================================================
; Validated ACPI MADT processor parser.
;
; This file is deliberately firmware- and allocator-independent so the exact
; parser used by the kernel can run in a native hostile-input unit harness.
; =============================================================================

[BITS 64]

SMP_MADT_SIGNATURE          equ 0x43495041 ; "APIC"
SMP_MADT_HEADER_BYTES       equ 44
SMP_MADT_MAX_BYTES          equ 1024 * 1024
SMP_MADT_MAX_OUTPUT_IDS     equ 4096
SMP_MADT_MAX_IOAPICS        equ 64
SMP_MADT_MAX_ISO_ROUTES     equ 16

; smp_madt_parse_irqs output records. The final IOAPIC dword is populated by
; the hardware probe with the exclusive GSI limit after the version register
; supplies the controller's redirection-entry count.
SMP_MADT_IOAPIC_ID_OFF      equ 0
SMP_MADT_IOAPIC_ADDR_OFF    equ 4
SMP_MADT_IOAPIC_GSI_OFF     equ 8
SMP_MADT_IOAPIC_LIMIT_OFF   equ 12
SMP_MADT_IOAPIC_BYTES       equ 16

SMP_MADT_ISO_SOURCE_OFF     equ 0
SMP_MADT_ISO_GSI_OFF        equ 4
SMP_MADT_ISO_FLAGS_OFF      equ 8
SMP_MADT_ISO_BYTES          equ 12

SMP_MADT_ERR_INPUT          equ 1
SMP_MADT_ERR_SPAN           equ 2
SMP_MADT_ERR_HEADER         equ 3
SMP_MADT_ERR_ENTRY          equ 4
SMP_MADT_ERR_DUPLICATE      equ 5
SMP_MADT_ERR_CAPACITY       equ 6
SMP_MADT_ERR_BSP            equ 7
SMP_MADT_ERR_LAPIC          equ 8
SMP_MADT_ERR_APIC_ID        equ 9

section .text

; -----------------------------------------------------------------------------
; smp_madt_parse
;   RDI = MADT identity address
;   RSI = exclusive end of the currently accessible physical mapping
;   EDX = executing BSP x2APIC/APIC ID
;   RCX = output array of u32 APIC IDs
;   R8D = output capacity
;   R9  = output qword for the LAPIC physical base
;
; CF=0: EAX=stored/enabled processor count, EDX=eligible count (identical;
;       exceeding capacity fails instead of silently truncating).  Slot zero
;       is always the executing BSP, regardless of firmware entry order.
; CF=1: EAX=0, EDX=rejection class.  All partial output must be discarded.
; -----------------------------------------------------------------------------
global smp_madt_parse
smp_madt_parse:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; table start
    mov r13, rsi                    ; accessible end, then table end
    mov ebp, edx                    ; BSP APIC ID
    mov r14, rcx                    ; output IDs
    mov r15, r9                     ; LAPIC-base output

    mov edx, SMP_MADT_ERR_INPUT
    test r12, r12
    jz .invalid
    test r14, r14
    jz .invalid
    test r15, r15
    jz .invalid
    cmp r12, r13
    jae .invalid
    cmp r8d, 1
    jb .invalid
    cmp r8d, SMP_MADT_MAX_OUTPUT_IDS
    ja .invalid
    mov esi, r8d                    ; bounded capacity

    mov edx, SMP_MADT_ERR_SPAN
    mov rax, r12
    add rax, SMP_MADT_HEADER_BYTES
    jc .invalid
    cmp rax, r13
    ja .invalid

    mov edx, SMP_MADT_ERR_HEADER
    cmp dword [r12], SMP_MADT_SIGNATURE
    jne .invalid
    mov ecx, [r12 + 4]
    cmp ecx, SMP_MADT_HEADER_BYTES
    jb .invalid
    cmp ecx, SMP_MADT_MAX_BYTES
    ja .invalid
    mov rax, r12
    add rax, rcx
    jc .span_invalid
    cmp rax, r13
    ja .span_invalid
    mov r13, rax                    ; exact table end

    ; Reject output/table aliasing before emitting even the BSP slot.
    mov eax, esi
    shl rax, 2
    mov rdx, r14
    add rdx, rax                    ; output end
    jc .span_invalid
    cmp r14, r13
    jae .ids_table_disjoint
    cmp r12, rdx
    jb .span_invalid
.ids_table_disjoint:
    mov rax, r15
    add rax, 8
    jc .span_invalid
    cmp r15, r13
    jae .lapic_table_disjoint
    cmp r12, rax
    jb .span_invalid
.lapic_table_disjoint:
    cmp r15, rdx
    jae .outputs_disjoint
    cmp r14, rax
    jb .span_invalid
.outputs_disjoint:

    ; ACPI SDT checksum: the complete declared table must sum to zero mod 256.
    xor eax, eax
    mov r11, r12
    mov ecx, [r12 + 4]
.checksum_loop:
    add al, [r11]
    inc r11
    dec ecx
    jnz .checksum_loop
    test al, al
    jnz .header_invalid

    mov r10d, [r12 + 36]            ; MADT header LAPIC address
    mov [r14], ebp                  ; BSP is always logical CPU zero
    mov ebx, 1                      ; stored count
    xor r9d, r9d                    ; eligible count
    xor edi, edi                    ; bit0=BSP seen, bit1=override seen
    lea r11, [r12 + SMP_MADT_HEADER_BYTES]

.entry_loop:
    cmp r11, r13
    je .entries_done
    ja .entry_invalid
    mov rax, r13
    sub rax, r11
    cmp rax, 2
    jb .entry_invalid

    movzx ecx, byte [r11 + 1]
    cmp ecx, 2
    jb .entry_invalid
    mov rax, r11
    add rax, rcx
    jc .entry_invalid
    cmp rax, r13
    ja .entry_invalid

    movzx eax, byte [r11]
    cmp eax, 0                      ; Processor Local APIC
    je .local_apic
    cmp eax, 4                      ; Local APIC NMI
    je .local_apic_nmi
    cmp eax, 5                      ; Local APIC Address Override
    je .lapic_override
    cmp eax, 9                      ; Processor Local x2APIC
    je .local_x2apic
    cmp eax, 10                     ; Local x2APIC NMI
    je .local_x2apic_nmi
    jmp .next_entry

.local_apic:
    cmp ecx, 8
    jb .entry_invalid
    mov eax, [r11 + 4]
    test eax, 0xFFFFFFFC            ; bits 0/1 are enabled/online-capable
    jnz .entry_invalid
    cmp eax, 3                      ; online-capable is reserved if enabled
    je .entry_invalid
    test eax, 1                     ; only currently enabled processors
    jz .next_entry
    movzx eax, byte [r11 + 3]
    jmp .processor

.local_x2apic:
    cmp ecx, 16
    jb .entry_invalid
    cmp word [r11 + 2], 0           ; architecturally reserved
    jne .entry_invalid
    mov eax, [r11 + 8]
    test eax, 0xFFFFFFFC
    jnz .entry_invalid
    cmp eax, 3
    je .entry_invalid
    test eax, 1
    jz .next_entry
    mov eax, [r11 + 4]
    jmp .processor

.local_apic_nmi:
    cmp ecx, 6
    jne .entry_invalid
    cmp byte [r11 + 5], 1           ; only LINT0/LINT1 exist
    ja .entry_invalid
    movzx eax, word [r11 + 3]
    jmp .validate_nmi_flags

.local_x2apic_nmi:
    cmp ecx, 12
    jne .entry_invalid
    cmp dword [r11 + 8], 1          ; LINT plus three reserved zero bytes
    ja .entry_invalid
    movzx eax, word [r11 + 2]

.validate_nmi_flags:
    test eax, 0xFFF0                ; only polarity/trigger fields are defined
    jnz .entry_invalid
    mov edx, eax
    and edx, 3
    cmp edx, 2                      ; 2 is reserved for both fields
    je .entry_invalid
    shr eax, 2
    and eax, 3
    cmp eax, 2
    je .entry_invalid
    jmp .next_entry

.lapic_override:
    cmp ecx, 12
    jb .entry_invalid
    cmp word [r11 + 2], 0
    jne .entry_invalid
    test edi, 2
    jnz .duplicate_invalid
    mov r10, [r11 + 4]
    or edi, 2
    jmp .next_entry

.processor:
    cmp eax, 0xFFFFFFFF             ; x2APIC physical broadcast destination
    je .apic_id_invalid
    inc r9d
    cmp eax, ebp
    jne .non_bsp
    test edi, 1
    jnz .duplicate_invalid
    or edi, 1
    jmp .next_entry

.non_bsp:
    mov edx, 1
.duplicate_scan:
    cmp edx, ebx
    jae .unique_processor
    cmp eax, [r14 + rdx * 4]
    je .duplicate_invalid
    inc edx
    jmp .duplicate_scan

.unique_processor:
    cmp ebx, esi
    jae .capacity_invalid
    mov [r14 + rbx * 4], eax
    inc ebx

.next_entry:
    add r11, rcx
    jmp .entry_loop

.entries_done:
    test edi, 1
    jz .bsp_invalid
    cmp ebx, r9d
    jne .capacity_invalid
    test r10, r10
    jz .lapic_invalid
    test r10, 0xFFF
    jnz .lapic_invalid
    mov rax, 0x100000000
    cmp r10, rax
    jae .lapic_invalid

    mov [r15], r10
    mov eax, ebx
    mov edx, r9d
    clc
    jmp .done

.span_invalid:
    mov edx, SMP_MADT_ERR_SPAN
    jmp .invalid
.header_invalid:
    mov edx, SMP_MADT_ERR_HEADER
    jmp .invalid
.entry_invalid:
    mov edx, SMP_MADT_ERR_ENTRY
    jmp .invalid
.duplicate_invalid:
    mov edx, SMP_MADT_ERR_DUPLICATE
    jmp .invalid
.capacity_invalid:
    mov edx, SMP_MADT_ERR_CAPACITY
    jmp .invalid
.bsp_invalid:
    mov edx, SMP_MADT_ERR_BSP
    jmp .invalid
.lapic_invalid:
    mov edx, SMP_MADT_ERR_LAPIC
    jmp .invalid
.apic_id_invalid:
    mov edx, SMP_MADT_ERR_APIC_ID
.invalid:
    xor eax, eax
    stc

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; smp_madt_find_nmi
;   RDI = MADT identity address
;   RSI = exclusive end of the currently accessible physical mapping
;   EDX = current x2APIC/APIC ID
;
; CF=0: EAX=LINT0 and ECX=LINT1 LAPIC LVT NMI configurations; zero means
;       no route applies to that pin. Wildcard and exact-UID records compose
;       across pins, while identical duplicates are harmless. EDX=0.
; CF=1: EAX=0, EDX=SMP_MADT_ERR_ENTRY for malformed input or conflicting
;       configurations for the same pin.
; -----------------------------------------------------------------------------
global smp_madt_find_nmi
smp_madt_find_nmi:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; table start
    mov r13, rsi                    ; accessible end
    mov ebp, edx                    ; current APIC ID

    test r12, r12
    jz .nmi_invalid
    cmp r12, r13
    jae .nmi_invalid
    mov rax, r12
    add rax, SMP_MADT_HEADER_BYTES
    jc .nmi_invalid
    cmp rax, r13
    ja .nmi_invalid
    cmp dword [r12], SMP_MADT_SIGNATURE
    jne .nmi_invalid
    mov ecx, [r12 + 4]
    cmp ecx, SMP_MADT_HEADER_BYTES
    jb .nmi_invalid
    cmp ecx, SMP_MADT_MAX_BYTES
    ja .nmi_invalid
    mov r14, r12
    add r14, rcx                    ; exact table end
    jc .nmi_invalid
    cmp r14, r13
    ja .nmi_invalid

    xor ebx, ebx                    ; matching enabled CPU record seen
    xor r15d, r15d                  ; resolved ACPI processor UID
    lea r11, [r12 + SMP_MADT_HEADER_BYTES]

.nmi_uid_loop:
    cmp r11, r14
    je .nmi_routes
    ja .nmi_invalid
    mov rax, r14
    sub rax, r11
    cmp rax, 2
    jb .nmi_invalid
    movzx ecx, byte [r11 + 1]
    cmp ecx, 2
    jb .nmi_invalid
    mov rax, r11
    add rax, rcx
    jc .nmi_invalid
    cmp rax, r14
    ja .nmi_invalid

    movzx eax, byte [r11]
    test eax, eax
    jz .nmi_uid_lapic
    cmp eax, 9
    je .nmi_uid_x2apic
    jmp .nmi_uid_next

.nmi_uid_lapic:
    cmp ecx, 8
    jb .nmi_invalid
    mov eax, [r11 + 4]
    test eax, 0xFFFFFFFC
    jnz .nmi_invalid
    cmp eax, 3
    je .nmi_invalid
    test eax, 1
    jz .nmi_uid_next
    movzx eax, byte [r11 + 3]
    cmp eax, ebp
    jne .nmi_uid_next
    movzx r15d, byte [r11 + 2]
    jmp .nmi_uid_found

.nmi_uid_x2apic:
    cmp ecx, 16
    jb .nmi_invalid
    cmp word [r11 + 2], 0
    jne .nmi_invalid
    mov eax, [r11 + 8]
    test eax, 0xFFFFFFFC
    jnz .nmi_invalid
    cmp eax, 3
    je .nmi_invalid
    test eax, 1
    jz .nmi_uid_next
    cmp dword [r11 + 4], ebp
    jne .nmi_uid_next
    mov r15d, [r11 + 12]

.nmi_uid_found:
    inc ebx
    cmp ebx, 1
    ja .nmi_invalid

.nmi_uid_next:
    add r11, rcx
    jmp .nmi_uid_loop

.nmi_routes:
    xor r8d, r8d                    ; LINT0 LVT configuration
    xor r9d, r9d                    ; LINT1 LVT configuration
    lea r11, [r12 + SMP_MADT_HEADER_BYTES]

.nmi_route_loop:
    cmp r11, r14
    je .nmi_route_done
    ja .nmi_invalid
    mov rax, r14
    sub rax, r11
    cmp rax, 2
    jb .nmi_invalid
    movzx ecx, byte [r11 + 1]
    cmp ecx, 2
    jb .nmi_invalid
    mov rax, r11
    add rax, rcx
    jc .nmi_invalid
    cmp rax, r14
    ja .nmi_invalid

    movzx eax, byte [r11]
    cmp eax, 4
    je .nmi_route_lapic
    cmp eax, 10
    je .nmi_route_x2apic
    jmp .nmi_route_next

.nmi_route_lapic:
    cmp ecx, 6
    jne .nmi_invalid
    movzx edx, word [r11 + 3]
    movzx r10d, byte [r11 + 5]
    cmp r10d, 1
    ja .nmi_invalid
    shl r10d, 16                    ; pack LINT above the LVT bits
    movzx eax, byte [r11 + 2]
    xor edi, edi                    ; wildcard specificity
    cmp eax, 0xFF
    je .nmi_route_flags
    mov edi, 1                     ; exact specificity
    cmp eax, r15d
    jne .nmi_route_skip
    jmp .nmi_route_flags

.nmi_route_x2apic:
    cmp ecx, 12
    jne .nmi_invalid
    mov eax, [r11 + 8]
    cmp eax, 1                     ; LINT plus reserved bytes
    ja .nmi_invalid
    mov r10d, eax
    shl r10d, 16
    movzx edx, word [r11 + 2]
    mov eax, [r11 + 4]
    xor edi, edi
    cmp eax, 0xFFFFFFFF
    je .nmi_route_flags
    mov edi, 1
    cmp eax, r15d
    jne .nmi_route_skip

.nmi_route_flags:
    test edx, 0xFFF0
    jnz .nmi_invalid
    mov eax, edx
    and eax, 3
    cmp eax, 2
    je .nmi_invalid
    or r10d, 0x400                  ; LAPIC NMI delivery mode
    cmp eax, 3
    jne .nmi_trigger
    or r10d, 0x2000                 ; active low
.nmi_trigger:
    shr edx, 2
    and edx, 3
    cmp edx, 2
    je .nmi_invalid
    cmp edx, 3
    jne .nmi_route_applicability
    or r10d, 0x8000                 ; level triggered

.nmi_route_applicability:
    test ebx, ebx                   ; APIC ID absent from enabled topology
    jz .nmi_route_next
    cmp edi, 2                      ; valid route for a different UID
    je .nmi_route_next
    test r10d, 1 << 16
    jnz .nmi_store_lint1
    and r10d, 0xFFFF
    test r8d, r8d
    jz .nmi_set_lint0
    cmp r8d, r10d
    jne .nmi_invalid
    jmp .nmi_route_next
.nmi_set_lint0:
    mov r8d, r10d
    jmp .nmi_route_next
.nmi_store_lint1:
    and r10d, 0xFFFF
    test r9d, r9d
    jz .nmi_set_lint1
    cmp r9d, r10d
    jne .nmi_invalid
    jmp .nmi_route_next
.nmi_set_lint1:
    mov r9d, r10d
    jmp .nmi_route_next

.nmi_route_skip:
    ; The primary parser already validated flags; retain independent safety
    ; here by validating even routes for other processor UIDs.
    mov edi, 2
    jmp .nmi_route_flags

.nmi_route_next:
    add r11, rcx
    jmp .nmi_route_loop

.nmi_route_done:
    mov eax, r8d
    mov ecx, r9d
    xor edx, edx
    clc
    jmp .nmi_done

.nmi_invalid:
    xor eax, eax
    xor ecx, ecx
    mov edx, SMP_MADT_ERR_ENTRY
    stc

.nmi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; smp_madt_parse_irqs
;   RDI = MADT identity address
;   RSI = exclusive end of the currently accessible physical mapping
;   RDX = output array of SMP_MADT_IOAPIC_BYTES records
;   ECX = IOAPIC output capacity
;   R8  = output array of SMP_MADT_ISO_BYTES records
;   R9D = interrupt-source-override output capacity
;
; CF=0: EAX=IOAPIC count, ECX=unique ISA override count, EDX=0.
; CF=1: EAX=ECX=0, EDX=rejection class. Partial output must be discarded.
;
; The processor parser has already validated the other MADT record families.
; This independent pass repeats the hostile table-envelope/checksum checks and
; owns the two record types required for external interrupt routing.
; -----------------------------------------------------------------------------
global smp_madt_parse_irqs
smp_madt_parse_irqs:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24

    mov r12, rdi                    ; table start
    mov r13, rsi                    ; accessible end, then exact table end
    mov r14, rdx                    ; IOAPIC output
    mov r15, r8                     ; ISO output
    mov [rsp], ecx                  ; IOAPIC capacity
    mov [rsp + 4], r9d              ; ISO capacity

    mov edx, SMP_MADT_ERR_INPUT
    test r12, r12
    jz .irq_invalid
    test r14, r14
    jz .irq_invalid
    test r15, r15
    jz .irq_invalid
    cmp r12, r13
    jae .irq_invalid
    cmp ecx, 1
    jb .irq_invalid
    cmp ecx, SMP_MADT_MAX_IOAPICS
    ja .irq_invalid
    cmp r9d, 1
    jb .irq_invalid
    cmp r9d, SMP_MADT_MAX_ISO_ROUTES
    ja .irq_invalid

    mov edx, SMP_MADT_ERR_SPAN
    mov rax, r12
    add rax, SMP_MADT_HEADER_BYTES
    jc .irq_invalid
    cmp rax, r13
    ja .irq_invalid

    mov edx, SMP_MADT_ERR_HEADER
    cmp dword [r12], SMP_MADT_SIGNATURE
    jne .irq_invalid
    mov ecx, [r12 + 4]
    cmp ecx, SMP_MADT_HEADER_BYTES
    jb .irq_invalid
    cmp ecx, SMP_MADT_MAX_BYTES
    ja .irq_invalid
    mov rax, r12
    add rax, rcx
    jc .irq_span_invalid
    cmp rax, r13
    ja .irq_span_invalid
    mov r13, rax

    ; Reject table/output and output/output aliasing before writing records.
    mov eax, [rsp]
    shl rax, 4
    add rax, r14
    jc .irq_span_invalid
    mov [rsp + 8], rax              ; IOAPIC output end
    mov eax, [rsp + 4]
    imul rax, SMP_MADT_ISO_BYTES
    add rax, r15
    jc .irq_span_invalid
    mov [rsp + 16], rax             ; ISO output end

    cmp r14, r13
    jae .irq_io_table_disjoint
    cmp r12, [rsp + 8]
    jb .irq_span_invalid
.irq_io_table_disjoint:
    cmp r15, r13
    jae .irq_iso_table_disjoint
    cmp r12, [rsp + 16]
    jb .irq_span_invalid
.irq_iso_table_disjoint:
    cmp r14, [rsp + 16]
    jae .irq_outputs_disjoint
    mov rax, [rsp + 8]
    cmp r15, rax
    jb .irq_span_invalid
.irq_outputs_disjoint:

    xor eax, eax
    mov r11, r12
    mov ecx, [r12 + 4]
.irq_checksum_loop:
    add al, [r11]
    inc r11
    dec ecx
    jnz .irq_checksum_loop
    test al, al
    jnz .irq_header_invalid

    xor ebx, ebx                    ; IOAPIC count
    xor ebp, ebp                    ; unique ISO count
    lea r11, [r12 + SMP_MADT_HEADER_BYTES]
.irq_entry_loop:
    cmp r11, r13
    je .irq_entries_done
    ja .irq_entry_invalid
    mov rax, r13
    sub rax, r11
    cmp rax, 2
    jb .irq_entry_invalid
    movzx ecx, byte [r11 + 1]
    cmp ecx, 2
    jb .irq_entry_invalid
    mov rax, r11
    add rax, rcx
    jc .irq_entry_invalid
    cmp rax, r13
    ja .irq_entry_invalid

    movzx eax, byte [r11]
    cmp eax, 1                      ; I/O APIC
    je .irq_type_ioapic
    cmp eax, 2                      ; Interrupt Source Override
    je .irq_type_iso
    jmp .irq_next_entry

.irq_type_ioapic:
    cmp ecx, 12
    jne .irq_entry_invalid
    cmp byte [r11 + 3], 0           ; architecturally reserved
    jne .irq_entry_invalid
    mov esi, [r11 + 4]
    test esi, esi
    jz .irq_entry_invalid
    test esi, 0xFFF
    jnz .irq_entry_invalid
    movzx r9d, byte [r11 + 2]
    mov edi, [r11 + 8]

    xor edx, edx
.irq_io_duplicate_loop:
    cmp edx, ebx
    jae .irq_io_unique
    mov eax, edx
    shl rax, 4
    lea r10, [r14 + rax]
    cmp r9d, [r10 + SMP_MADT_IOAPIC_ID_OFF]
    je .irq_duplicate_invalid
    cmp esi, [r10 + SMP_MADT_IOAPIC_ADDR_OFF]
    je .irq_duplicate_invalid
    cmp edi, [r10 + SMP_MADT_IOAPIC_GSI_OFF]
    je .irq_duplicate_invalid
    inc edx
    jmp .irq_io_duplicate_loop

.irq_io_unique:
    cmp ebx, [rsp]
    jae .irq_capacity_invalid
    mov eax, ebx
    shl rax, 4
    lea r10, [r14 + rax]
    mov [r10 + SMP_MADT_IOAPIC_ID_OFF], r9d
    mov [r10 + SMP_MADT_IOAPIC_ADDR_OFF], esi
    mov [r10 + SMP_MADT_IOAPIC_GSI_OFF], edi
    mov dword [r10 + SMP_MADT_IOAPIC_LIMIT_OFF], 0
    inc ebx
    jmp .irq_next_entry

.irq_type_iso:
    cmp ecx, 10
    jne .irq_entry_invalid
    cmp byte [r11 + 2], 0           ; ISA is the only defined source bus
    jne .irq_entry_invalid
    movzx r9d, byte [r11 + 3]
    cmp r9d, 15
    ja .irq_entry_invalid
    mov esi, [r11 + 4]
    movzx edi, word [r11 + 8]
    test edi, 0xFFF0
    jnz .irq_entry_invalid
    mov eax, edi
    and eax, 3
    cmp eax, 2                      ; polarity value 2 is reserved
    je .irq_entry_invalid
    mov eax, edi
    shr eax, 2
    and eax, 3
    cmp eax, 2                      ; trigger value 2 is reserved
    je .irq_entry_invalid

    xor edx, edx
.irq_iso_duplicate_loop:
    cmp edx, ebp
    jae .irq_iso_unique
    mov eax, edx
    imul rax, SMP_MADT_ISO_BYTES
    lea r10, [r15 + rax]
    cmp r9d, [r10 + SMP_MADT_ISO_SOURCE_OFF]
    jne .irq_iso_duplicate_next
    cmp esi, [r10 + SMP_MADT_ISO_GSI_OFF]
    jne .irq_duplicate_invalid
    cmp edi, [r10 + SMP_MADT_ISO_FLAGS_OFF]
    jne .irq_duplicate_invalid
    jmp .irq_next_entry             ; identical duplicate is harmless
.irq_iso_duplicate_next:
    inc edx
    jmp .irq_iso_duplicate_loop

.irq_iso_unique:
    cmp ebp, [rsp + 4]
    jae .irq_capacity_invalid
    mov eax, ebp
    imul rax, SMP_MADT_ISO_BYTES
    lea r10, [r15 + rax]
    mov [r10 + SMP_MADT_ISO_SOURCE_OFF], r9d
    mov [r10 + SMP_MADT_ISO_GSI_OFF], esi
    mov [r10 + SMP_MADT_ISO_FLAGS_OFF], edi
    inc ebp

.irq_next_entry:
    add r11, rcx
    jmp .irq_entry_loop

.irq_entries_done:
    mov eax, ebx
    mov ecx, ebp
    xor edx, edx
    clc
    jmp .irq_done

.irq_span_invalid:
    mov edx, SMP_MADT_ERR_SPAN
    jmp .irq_invalid
.irq_header_invalid:
    mov edx, SMP_MADT_ERR_HEADER
    jmp .irq_invalid
.irq_entry_invalid:
    mov edx, SMP_MADT_ERR_ENTRY
    jmp .irq_invalid
.irq_duplicate_invalid:
    mov edx, SMP_MADT_ERR_DUPLICATE
    jmp .irq_invalid
.irq_capacity_invalid:
    mov edx, SMP_MADT_ERR_CAPACITY
.irq_invalid:
    xor eax, eax
    xor ecx, ecx
    stc

.irq_done:
    lea rsp, [rsp + 24]             ; preserve the CF success/error contract
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; KERNEL_ARCH_X86_64_MADT_ASM
