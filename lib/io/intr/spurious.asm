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
    iretq                           ; Simply return from interrupt

%endif ; IO_INTR_SPURIOUS_ASM
