; =============================================================================
; lib/io/macro/func.asm
; Prologue and epilogue macros for Tattva OS I/O Subsystem routines.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_MACRO_FUNC_ASM
%define IO_MACRO_FUNC_ASM

; -----------------------------------------------------------------------------
; IO_FUNC name
; Standard function prologue conforming to System V AMD64 ABI.
; Sets up stack frame, saving the caller's frame pointer (RBP).
; -----------------------------------------------------------------------------
%macro IO_FUNC 1
global %1
%1:
    push    rbp
    mov     rbp, rsp
%endmacro

; -----------------------------------------------------------------------------
; IO_ENDFUNC name
; Standard function epilogue. Restores frame pointer and returns.
; -----------------------------------------------------------------------------
%macro IO_ENDFUNC 1
    pop     rbp
    ret
%endmacro

%endif ; IO_MACRO_FUNC_ASM
