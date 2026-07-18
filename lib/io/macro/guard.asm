; =============================================================================
; lib/io/macro/guard.asm
; Boundary checks and validation macros for lib/io routines.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_MACRO_GUARD_ASM
%define IO_MACRO_GUARD_ASM

%include "lib/io/error/codes.asm"

; -----------------------------------------------------------------------------
; guard_null reg
; Asserts that the specified register is non-null. If null, returns
; IO_ERR_NULL (-1) immediately, cleaning up the stack frame.
; WARNING: This macro assumes ONLY RBP has been pushed to the stack (e.g. from
; the IO_FUNC prologue). It MUST appear BEFORE any other callee-saved pushes 
; in the function body; otherwise, the ret path will cause stack corruption.
; -----------------------------------------------------------------------------
%macro guard_null 1
    test    %1, %1
    jnz     %%ok
    mov     rax, IO_ERR_NULL
    pop     rbp
    ret
%%ok:
%endmacro

; -----------------------------------------------------------------------------
; guard_bar reg, min, max
; Asserts that the value in the specified register is within range [min, max].
; If outside bounds, returns IO_ERR_BADARG (-2) immediately.
; WARNING: This macro assumes ONLY RBP has been pushed to the stack (e.g. from
; the IO_FUNC prologue). It MUST appear BEFORE any other callee-saved pushes 
; in the function body; otherwise, the ret path will cause stack corruption.
; -----------------------------------------------------------------------------
%macro guard_bar 3
    cmp     %1, %2
    jl      %%fail
    cmp     %1, %3
    jg      %%fail
    jmp     %%ok
%%fail:
    mov     rax, IO_ERR_BADARG
    pop     rbp
    ret
%%ok:
%endmacro

; -----------------------------------------------------------------------------
; IS_ERR reg
; Sets flags to check if a return value/pointer is in the top-page error band.
; i.e. value >= -4095 (unsigned comparison).
; -----------------------------------------------------------------------------
%macro IS_ERR 1
    cmp     %1, -4095
%endmacro

%endif ; IO_MACRO_GUARD_ASM
