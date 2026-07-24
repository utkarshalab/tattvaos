; =============================================================================
; Tattva OS — lib/ucmp/arch/common/macros.inc
; =============================================================================
; Common NASM Assembly Macros for Compression Algorithms.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UCMP_MACROS_INC
%define UCMP_MACROS_INC

; -----------------------------------------------------------------------------
; Function Entry & Exit PUSH/POP Macros
; -----------------------------------------------------------------------------
%macro UCMP_SAVE_REGS 0
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro UCMP_RESTORE_REGS 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
%endmacro

; -----------------------------------------------------------------------------
; Alignment & Vector Register Zeroing Macros
; -----------------------------------------------------------------------------
%macro UCMP_ALIGN_16 0
    align 16
%endmacro

%macro UCMP_ALIGN_32 0
    align 32
%endmacro

%macro UCMP_VZEROALL 0
    vzeroall
%endmacro

%endif ; UCMP_MACROS_INC
