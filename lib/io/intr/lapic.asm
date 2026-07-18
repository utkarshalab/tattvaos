; =============================================================================
; lib/io/intr/lapic.asm
; Local APIC (LAPIC) and LAPIC Timer initialization/management.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_LAPIC_ASM
%define IO_INTR_LAPIC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .text

extern io_lapic_base

; =============================================================================
; lapic_init — Initialize the Local APIC for the current core
; In : None
; Out: None
; =============================================================================
IO_FUNC lapic_init
    push    rax
    push    rcx

    mov     rcx, [rel io_lapic_base]
    test    rcx, rcx
    jz      .done

    ; 1. Enable LAPIC & Set Spurious Vector to 0xFF
    ; SVR register (offset 0xF0) = spurious vector (0xFF) | APIC Software Enable (bit 8 = 0x100)
    mov     dword [rcx + LAPIC_SVR], 0x1FF

    ; 2. Set Task Priority Register TPR (offset 0x80) to 0 to accept all interrupts
    mov     dword [rcx + LAPIC_TPR], 0

.done:
    pop     rcx
    pop     rax
    ret
IO_ENDFUNC lapic_init

; =============================================================================
; lapic_send_eoi — Send End Of Interrupt signal to LAPIC
; In : None
; Out: None
; =============================================================================
IO_FUNC lapic_send_eoi
    push    rcx

    mov     rcx, [rel io_lapic_base]
    test    rcx, rcx
    jz      .done

    ; Write 0 to EOI register (offset 0xB0)
    mov     dword [rcx + LAPIC_EOI], 0

.done:
    pop     rcx
    ret
IO_ENDFUNC lapic_send_eoi

; =============================================================================
; lapic_timer_start — Start the LAPIC timer in periodic mode
; In : RDI = Initial count ticks (32-bit)
;      RSI = Vector number (8-bit)
; Out: None
; RSO: RDI, RSI owned-in
; =============================================================================
IO_FUNC lapic_timer_start
    push    rax
    push    rcx
    push    rdx

    mov     rcx, [rel io_lapic_base]
    test    rcx, rcx
    jz      .done

    ; 1. Set Divider Config register (offset 0x3E0) to Divide by 16 (value 0x03)
    mov     dword [rcx + LAPIC_TIMER_DIV], 0x03

    ; 2. Program LVT Timer register (offset 0x320)
    ; Mode: Periodic (bit 17 = 1, value 0x20000)
    ; Vector: mask with 0xFF from RSI
    mov     rax, rsi
    and     rax, 0xFF
    or      rax, 0x20000            ; Periodic mode bit
    mov     [rcx + LAPIC_LVT_TIMER], eax

    ; 3. Write initial count to count register (offset 0x380)
    mov     [rcx + LAPIC_TIMER_INIT], edi

.done:
    pop     rdx
    pop     rcx
    pop     rax
    ret
IO_ENDFUNC lapic_timer_start

%endif ; IO_INTR_LAPIC_ASM
