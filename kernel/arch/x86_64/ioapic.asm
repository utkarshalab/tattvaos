%ifndef KERNEL_ARCH_X86_64_IOAPIC_ASM
%define KERNEL_ARCH_X86_64_IOAPIC_ASM
; =============================================================================
; Validated I/O APIC ownership and legacy GSI routing.
;
; Firmware routes are masked before any one is reprogrammed. MADT discovery is
; bounded by the existing direct-map contract, supports multiple controllers,
; and resolves ISA interrupt-source overrides before selecting a redirection
; entry. MSI/MSI-X never passes through this layer.
; =============================================================================

[BITS 64]

IOAPIC_REGSEL              equ 0x00
IOAPIC_IOWIN               equ 0x10
IOAPIC_REG_ID              equ 0x00
IOAPIC_REG_VERSION         equ 0x01
IOAPIC_REDIR_BASE          equ 0x10
IOAPIC_MAX_REDIR_INDEX     equ 119
IOAPIC_REDIR_POLARITY_LOW  equ 1 << 13
IOAPIC_REDIR_TRIGGER_LEVEL equ 1 << 15
IOAPIC_REDIR_MASKED        equ 1 << 16

IOAPIC_VECTOR_FIRST        equ 0x40
IOAPIC_VECTOR_LAST         equ 0xEF
IOAPIC_PIT_DIVISOR         equ 11932       ; approximately 10 ms at 1.193182 MHz
IOAPIC_PIT_WAIT_MS         equ 100

section .text

; Read/write one indirect register. The selector/window pair is shared state,
; so one lock covers every controller and local interrupts are held off while
; it is owned. Both helpers preserve the caller's complete RFLAGS value.
ioapic_read_reg:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    pushfq
    pop r13
    cli
.lock_try:
    mov eax, 1
    xchg eax, [rel ioapic_mmio_lock]
    test eax, eax
    jz .locked
.lock_wait:
    pause
    cmp dword [rel ioapic_mmio_lock], 0
    jne .lock_wait
    jmp .lock_try
.locked:
    mov [rbx + IOAPIC_REGSEL], r12d
    mov eax, [rbx + IOAPIC_IOWIN]
    mov r8d, eax
    mov dword [rel ioapic_mmio_lock], 0
    push r13
    popfq
    mov eax, r8d
    pop r13
    pop r12
    pop rbx
    ret

ioapic_write_reg:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    mov r14d, edx
    pushfq
    pop r13
    cli
.lock_try:
    mov eax, 1
    xchg eax, [rel ioapic_mmio_lock]
    test eax, eax
    jz .locked
.lock_wait:
    pause
    cmp dword [rel ioapic_mmio_lock], 0
    jne .lock_wait
    jmp .lock_try
.locked:
    mov [rbx + IOAPIC_REGSEL], r12d
    mov [rbx + IOAPIC_IOWIN], r14d
    mov dword [rel ioapic_mmio_lock], 0
    push r13
    popfq
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Locate the controller owning EDI=GSI.
; CF=0: RAX=MMIO base, EDX=redirection pin. CF=1: no owner.
ioapic_find_gsi:
    xor ecx, ecx
.loop:
    cmp ecx, [rel ioapic_count]
    jae .missing
    mov eax, ecx
    shl rax, 4
    lea r8, [rel ioapic_descriptors]
    add r8, rax
    cmp edi, [r8 + SMP_MADT_IOAPIC_GSI_OFF]
    jb .next
    cmp edi, [r8 + SMP_MADT_IOAPIC_LIMIT_OFF]
    jae .next
    mov edx, edi
    sub edx, [r8 + SMP_MADT_IOAPIC_GSI_OFF]
    mov eax, [r8 + SMP_MADT_IOAPIC_ADDR_OFF]
    clc
    ret
.next:
    inc ecx
    jmp .loop
.missing:
    xor eax, eax
    xor edx, edx
    stc
    ret

; Resolve EDI=legacy ISA IRQ through MADT overrides.
; CF=0: EAX=GSI, EDX=IOAPIC polarity/trigger bits.
ioapic_resolve_legacy_irq:
    cmp edi, 15
    ja .invalid
    mov eax, edi                    ; conforming ISA route: high/edge
    xor edx, edx
    xor ecx, ecx
.loop:
    cmp ecx, [rel ioapic_iso_count]
    jae .done
    mov r8d, ecx
    imul r8, SMP_MADT_ISO_BYTES
    lea r9, [rel ioapic_iso_routes]
    add r9, r8
    cmp edi, [r9 + SMP_MADT_ISO_SOURCE_OFF]
    je .found
    inc ecx
    jmp .loop
.found:
    mov eax, [r9 + SMP_MADT_ISO_GSI_OFF]
    mov r8d, [r9 + SMP_MADT_ISO_FLAGS_OFF]
    mov r9d, r8d
    and r9d, 3
    cmp r9d, 3
    jne .trigger
    or edx, IOAPIC_REDIR_POLARITY_LOW
.trigger:
    shr r8d, 2
    and r8d, 3
    cmp r8d, 3
    jne .done
    or edx, IOAPIC_REDIR_TRIGGER_LEVEL
.done:
    clc
    ret
.invalid:
    xor eax, eax
    xor edx, edx
    stc
    ret

; Program one legacy route. Every update first masks the existing entry, then
; writes destination and low configuration while the entry remains masked.
; EDI=IRQ, ESI=vector, EDX=destination APIC ID, ECX=nonzero to leave masked.
global ioapic_route_legacy_irq
ioapic_route_legacy_irq:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    cmp byte [rel ioapic_ready], 1
    jne .invalid
    cmp esi, IOAPIC_VECTOR_FIRST
    jb .invalid
    cmp esi, IOAPIC_VECTOR_LAST
    ja .invalid
    cmp edx, 255
    ja .invalid
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    call ioapic_resolve_legacy_irq
    jc .invalid
    mov ebx, edx                    ; polarity/trigger configuration
    mov edi, eax
    call ioapic_find_gsi
    jc .invalid
    mov r12, rax                    ; controller MMIO base
    mov ebp, edx                    ; redirection pin
    shl ebp, 1
    add ebp, IOAPIC_REDIR_BASE

    mov rdi, r12
    mov esi, ebp
    call ioapic_read_reg
    or eax, IOAPIC_REDIR_MASKED
    mov rdi, r12
    mov esi, ebp
    mov edx, eax
    call ioapic_write_reg

    mov rdi, r12
    lea esi, [rbp + 1]
    mov edx, r14d
    shl edx, 24
    call ioapic_write_reg

    mov eax, r13d
    or eax, ebx
    test r15d, r15d
    jz .write_low
    or eax, IOAPIC_REDIR_MASKED
.write_low:
    mov rdi, r12
    mov esi, ebp
    mov edx, eax
    call ioapic_write_reg
    clc
    jmp .done
.invalid:
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; EDI=legacy ISA IRQ. Preserve the route but force its mask bit high.
global ioapic_mask_legacy_irq
ioapic_mask_legacy_irq:
    push rbp
    push r12
    cmp byte [rel ioapic_ready], 1
    jne .invalid
    call ioapic_resolve_legacy_irq
    jc .invalid
    mov edi, eax
    call ioapic_find_gsi
    jc .invalid
    mov r12, rax
    mov ebp, edx
    shl ebp, 1
    add ebp, IOAPIC_REDIR_BASE
    mov rdi, r12
    mov esi, ebp
    call ioapic_read_reg
    or eax, IOAPIC_REDIR_MASKED
    mov rdi, r12
    mov esi, ebp
    mov edx, eax
    call ioapic_write_reg
    clc
    jmp .done
.invalid:
    stc
.done:
    pop r12
    pop rbp
    ret

; Parse all routing records, validate each MMIO aperture/version/GSI window,
; detect overlaps, then mask every redirection entry before publishing ready.
global ioapic_init
ioapic_init:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov byte [rel ioapic_ready], 0
    mov dword [rel ioapic_count], 0
    mov dword [rel ioapic_iso_count], 0
    mov dword [rel ioapic_input_count], 0
    mov rdi, [rel smp_madt_ptr]
    test rdi, rdi
    jz .unavailable
    mov rsi, [rel phys_state + phys_state_t.direct_map_limit]
    lea rdx, [rel ioapic_descriptors]
    mov ecx, SMP_MADT_MAX_IOAPICS
    lea r8, [rel ioapic_iso_routes]
    mov r9d, SMP_MADT_MAX_ISO_ROUTES
    call smp_madt_parse_irqs
    jc .invalid
    mov [rel ioapic_count], eax
    mov [rel ioapic_iso_count], ecx
    test eax, eax
    jz .unavailable

    xor r12d, r12d
.controller_loop:
    cmp r12d, [rel ioapic_count]
    jae .controllers_masked
    mov eax, r12d
    shl rax, 4
    lea r13, [rel ioapic_descriptors]
    add r13, rax
    mov ebx, [r13 + SMP_MADT_IOAPIC_ADDR_OFF]
    test ebx, 0xFFF
    jnz .invalid
    mov eax, ebx
    add rax, 0x1000
    jc .invalid
    cmp rax, [rel phys_state + phys_state_t.direct_map_limit]
    ja .invalid

    mov edi, ebx
    mov esi, IOAPIC_REG_VERSION
    call ioapic_read_reg
    cmp eax, 0xFFFFFFFF
    je .invalid
    mov edx, eax
    and edx, 0xFF
    cmp edx, 0x10
    jb .invalid
    cmp edx, 0xFF
    je .invalid
    shr eax, 16
    and eax, 0xFF
    cmp eax, IOAPIC_MAX_REDIR_INDEX
    ja .invalid
    inc eax
    mov r14d, eax                   ; pin count
    mov edx, [r13 + SMP_MADT_IOAPIC_GSI_OFF]
    add edx, r14d                   ; exclusive GSI limit
    jc .invalid
    mov [r13 + SMP_MADT_IOAPIC_LIMIT_OFF], edx

    xor ebp, ebp
.overlap_loop:
    cmp ebp, r12d
    jae .mask_controller
    mov eax, ebp
    shl rax, 4
    lea r15, [rel ioapic_descriptors]
    add r15, rax
    mov eax, [r13 + SMP_MADT_IOAPIC_GSI_OFF]
    cmp eax, [r15 + SMP_MADT_IOAPIC_LIMIT_OFF]
    jae .overlap_next
    mov eax, [r15 + SMP_MADT_IOAPIC_GSI_OFF]
    cmp eax, [r13 + SMP_MADT_IOAPIC_LIMIT_OFF]
    jb .invalid
.overlap_next:
    inc ebp
    jmp .overlap_loop

.mask_controller:
    xor r15d, r15d
.mask_loop:
    cmp r15d, r14d
    jae .controller_done
    mov ebp, r15d
    shl ebp, 1
    add ebp, IOAPIC_REDIR_BASE
    mov edi, ebx
    mov esi, ebp
    call ioapic_read_reg
    or eax, IOAPIC_REDIR_MASKED
    mov edi, ebx
    mov esi, ebp
    mov edx, eax
    call ioapic_write_reg
    inc r15d
    jmp .mask_loop
.controller_done:
    add [rel ioapic_input_count], r14d
    inc r12d
    jmp .controller_loop

.controllers_masked:
    ; ponytail: x2APIC destinations above 255 require interrupt remapping;
    ; retain a safe masked-only state until that layer is owned.
    cmp dword [rel smp_bsp_apic_id], 255
    ja .remap_deferred
    mov byte [rel ioapic_ready], 1
    lea rsi, [rel msg_ioapic_masked]
    call uart_print_str
    mov eax, [rel ioapic_input_count]
    call uart_print_dec
    lea rsi, [rel msg_ioapic_across]
    call uart_print_str
    mov eax, [rel ioapic_count]
    call uart_print_dec
    lea rsi, [rel msg_ioapic_controllers]
    call uart_print_str
    clc
    jmp .done

.unavailable:
    lea rsi, [rel msg_ioapic_unavailable]
    call uart_print_str
    clc
    jmp .done
.remap_deferred:
    lea rsi, [rel msg_ioapic_remap_deferred]
    call uart_print_str
    clc
    jmp .done
.invalid:
    lea rsi, [rel msg_ioapic_invalid]
    call uart_print_str
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Prove an actual external interrupt end to end: allocate an owned vector,
; route PIT IRQ0 through its MADT-resolved GSI to the BSP, observe one edge,
; and mask/release the route again.
global ioapic_pit_selftest
ioapic_pit_selftest:
    push rbx
    push r12
    push r13
    cmp byte [rel ioapic_ready], 1
    jne .skip
    call vector_alloc
    cmp eax, IOAPIC_VECTOR_FIRST
    jb .early_fail
    cmp eax, IOAPIC_VECTOR_LAST
    ja .early_fail
    mov r13d, eax
    mov edi, eax
    lea rsi, [rel ioapic_pit_isr]
    xor edx, edx
    call register_idt_handler
    mov dword [rel ioapic_pit_ticks], 0
    pushfq
    pop r12
    cli

    mov edi, 0                     ; PIT IRQ0
    mov esi, r13d
    mov edx, [rel smp_bsp_apic_id]
    mov ecx, 1                     ; configure while masked
    call ioapic_route_legacy_irq
    jc .failed_cleanup

    mov dx, 0x43
    mov al, 0x30                   ; channel 0, lo/hi, one-shot mode 0
    out dx, al
    mov dx, 0x40
    mov ax, IOAPIC_PIT_DIVISOR
    out dx, al
    mov al, ah
    out dx, al

    mov edi, 0
    mov esi, r13d
    mov edx, [rel smp_bsp_apic_id]
    xor ecx, ecx                   ; publish the fully programmed route
    call ioapic_route_legacy_irq
    jc .failed_cleanup
    sti
    mov ebx, IOAPIC_PIT_WAIT_MS
.wait:
    cmp dword [rel ioapic_pit_ticks], 0
    jne .passed_cleanup
    mov edi, 1000
    call udelay
    dec ebx
    jnz .wait
    xor ebx, ebx
    jmp .cleanup
.passed_cleanup:
    mov ebx, 1
.cleanup:
    cli
    mov edi, 0
    call ioapic_mask_legacy_irq
    push r12
    popfq
    mov edi, r13d
    call vector_free
    test ebx, ebx
    jz .failed
    lea rsi, [rel msg_ioapic_pit_pass]
    call uart_print_str
    clc
    jmp .done
.failed_cleanup:
    xor ebx, ebx
    jmp .cleanup
.early_fail:
    lea rsi, [rel msg_ioapic_pit_fail]
    call uart_print_str
    stc
    jmp .done
.failed:
    lea rsi, [rel msg_ioapic_pit_fail]
    call uart_print_str
    stc
    jmp .done
.skip:
    lea rsi, [rel msg_ioapic_pit_skip]
    call uart_print_str
    clc
.done:
    pop r13
    pop r12
    pop rbx
    ret

ioapic_pit_isr:
    push rax
    push rcx
    push rdx
    lock inc dword [rel ioapic_pit_ticks]
    call smp_lapic_eoi
    pop rdx
    pop rcx
    pop rax
    iretq

section .data
msg_ioapic_masked:         db "IOAPIC: masked ", 0
msg_ioapic_across:         db " inputs across ", 0
msg_ioapic_controllers:    db " controllers", 0x0D, 0x0A, 0
msg_ioapic_unavailable:    db "IOAPIC: unavailable; external interrupts remain disabled", 0x0D, 0x0A, 0
msg_ioapic_remap_deferred: db "IOAPIC: BSP destination requires interrupt remapping; routes remain masked", 0x0D, 0x0A, 0
msg_ioapic_invalid:        db "IOAPIC: topology or hardware validation FAILED", 0x0D, 0x0A, 0
msg_ioapic_pit_pass:       db "IOAPIC: PIT IRQ0 delivery PASS", 0x0D, 0x0A, 0
msg_ioapic_pit_fail:       db "IOAPIC: PIT IRQ0 delivery FAILED", 0x0D, 0x0A, 0
msg_ioapic_pit_skip:       db "IOAPIC: PIT IRQ0 delivery SKIP (routing unavailable)", 0x0D, 0x0A, 0

section .bss
alignb 64
ioapic_descriptors: resb SMP_MADT_MAX_IOAPICS * SMP_MADT_IOAPIC_BYTES
alignb 16
ioapic_iso_routes:  resb SMP_MADT_MAX_ISO_ROUTES * SMP_MADT_ISO_BYTES
alignb 8
ioapic_mmio_lock:   resd 1
ioapic_count:       resd 1
ioapic_iso_count:   resd 1
ioapic_input_count: resd 1
ioapic_pit_ticks:   resd 1
ioapic_ready:       resb 1

%endif ; KERNEL_ARCH_X86_64_IOAPIC_ASM
