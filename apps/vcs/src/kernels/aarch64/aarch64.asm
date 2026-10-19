; =============================================================================
; File     : src/kernels/aarch64/aarch64.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: AArch64 kernels (reserved — needs utasm).
; =============================================================================

%ifndef VCS_KERNELS_AARCH64_ASM
%define VCS_KERNELS_AARCH64_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; aarch64_blake3 — Blake3 hash AArch64 (stub)
; -----------------------------------------------------------------------------
global aarch64_blake3
aarch64_blake3:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; aarch64_chunk — Content-defined chunking AArch64 (stub)
; -----------------------------------------------------------------------------
global aarch64_chunk
aarch64_chunk:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; aarch64_diff — Scalar diff AArch64 (stub)
; -----------------------------------------------------------------------------
global aarch64_diff
aarch64_diff:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_KERNELS_AARCH64_ASM