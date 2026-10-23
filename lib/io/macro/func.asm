; =============================================================================
; lib/io/macro/func.asm
; Prologue and epilogue macros for Utkarsha OS I/O Subsystem routines.
;
; Part of Utkarsha Labs / Utkarsha OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_MACRO_FUNC_ASM
%define IO_MACRO_FUNC_ASM

; -----------------------------------------------------------------------------
; IO_FUNC name
; Declares and labels a global routine. Frameless: nothing is pushed, so a
; body may return early with a plain `ret` as long as its own pushes are
; balanced. (A frame push here would be skipped by every such early return.)
; -----------------------------------------------------------------------------
%macro IO_FUNC 1
global %1
%1:
%endmacro

; -----------------------------------------------------------------------------
; IO_ENDFUNC name
; Return for bodies that fall through to the end.
; -----------------------------------------------------------------------------
%macro IO_ENDFUNC 1
    ret
%endmacro

%endif ; IO_MACRO_FUNC_ASM
