; =============================================================================
; File     : src/kernels/riscv64/riscv64.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: RISC-V 64-bit kernels (reserved — needs utasm).
; =============================================================================

%ifndef VCS_KERNELS_RISCV64_ASM
%define VCS_KERNELS_RISCV64_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; riscv64_blake3 — Blake3 hash RISC-V (stub)
; -----------------------------------------------------------------------------
global riscv64_blake3
riscv64_blake3:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; riscv64_chunk — Content-defined chunking RISC-V (stub)
; -----------------------------------------------------------------------------
global riscv64_chunk
riscv64_chunk:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; riscv64_diff — Scalar diff RISC-V (stub)
; -----------------------------------------------------------------------------
global riscv64_diff
riscv64_diff:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_KERNELS_RISCV64_ASM