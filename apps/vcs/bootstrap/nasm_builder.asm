; =============================================================================
; File     : bootstrap/nasm_builder.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Stage 0 NASM builder — assembles all VCS source with NASM.
; =============================================================================

%ifndef VCS_BOOTSTRAP_NASM_ASM
%define VCS_BOOTSTRAP_NASM_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; bootstrap_build — Build all VCS objects with NASM
; Input:  rdi = source root, rsi = output directory
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global bootstrap_build
bootstrap_build:
    PROLOGUE_SAVE rbx
    ; TODO: iterate source files, invoke NASM on each
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; bootstrap_link — Link all objects into final VCS binary
; Input:  rdi = object directory, rsi = output binary
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global bootstrap_link
bootstrap_link:
    PROLOGUE_SAVE rbx
    ; TODO: invoke ld on all .o files
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_BOOTSTRAP_NASM_ASM