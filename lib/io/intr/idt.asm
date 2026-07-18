; =============================================================================
; lib/io/intr/idt.asm
; IDT handler registration wrapper.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_IDT_ASM
%define IO_INTR_IDT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

section .text

; Declared in kernel/arch/x86_64/interrupts.asm
extern register_idt_handler

; =============================================================================
; idt_register_handler — Register an interrupt handler in the system IDT
; In : RDI = Vector index (0-255)
;      RSI = Handler address (64-bit function pointer)
;      RDX = IST index (0-7)
; Out: None
; RSO: RDI, RSI, RDX owned-in
; =============================================================================
IO_FUNC idt_register_handler
    guard_null rsi
    ; Forward the call directly to kernel's IDT registrar
    call    register_idt_handler
    ret
IO_ENDFUNC idt_register_handler

%endif ; IO_INTR_IDT_ASM
