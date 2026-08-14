; =============================================================================
; lib/io/intr/spurious.asm
; Spurious interrupt handler for Local APIC (vector 0xFF).
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_SPURIOUS_ASM
%define IO_INTR_SPURIOUS_ASM

section .text

; =============================================================================
; io_spurious_handler — Spurious interrupt vector 0xFF handler.
; According to the Intel SDM, spurious interrupts on vector 0xFF do NOT set the
; In-Service Register (ISR) bit, hence they must return immediately WITHOUT EOI.
; =============================================================================
global io_spurious_handler

io_spurious_handler:
    ; 1. Preserve caller-saved registers (interrupt context safety)
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11

    ; 2. Call telemetry tick handler
    call    spurious_telemetry_tick

    ; 3. Restore registers and return from interrupt
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    iretq

%endif ; IO_INTR_SPURIOUS_ASM
