; =============================================================================
; lib/io/intr/isr.asm
; Common Interrupt Service Routine (ISR) save/restore macros.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_ISR_ASM
%define IO_INTR_ISR_ASM

; -----------------------------------------------------------------------------
; save_gp_regs
; Pushes RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11 onto stack.
; Fits the reverse layout of GP registers in interrupt_frame_t.
; -----------------------------------------------------------------------------
%macro save_gp_regs 0
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
%endmacro

; -----------------------------------------------------------------------------
; restore_gp_regs
; Pops R11, R10, R9, R8, RDI, RSI, RDX, RCX, RAX in order from the stack.
; -----------------------------------------------------------------------------
%macro restore_gp_regs 0
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
%endmacro

; -----------------------------------------------------------------------------
; ISR_ENTRY
; Prepares the CPU stack frame for a device interrupt (which does not push an
; error code automatically) by pushing a dummy error code and saving registers.
; -----------------------------------------------------------------------------
%macro ISR_ENTRY 0
    push    qword 0                 ; Dummy error code to align interrupt_frame_t
    save_gp_regs
%endmacro

; -----------------------------------------------------------------------------
; ISR_EXIT
; Restores all registers saved in ISR_ENTRY and returns using iretq.
; -----------------------------------------------------------------------------
%macro ISR_EXIT 0
    restore_gp_regs
    add     rsp, 8                  ; Pop dummy error code
    iretq
%endmacro

%endif ; IO_INTR_ISR_ASM
