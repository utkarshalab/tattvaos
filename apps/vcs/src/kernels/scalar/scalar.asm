; =============================================================================
; File     : src/kernels/scalar/scalar.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Scalar reference kernels — Blake3, chunking, diff.
; =============================================================================

%ifndef VCS_KERNELS_SCALAR_ASM
%define VCS_KERNELS_SCALAR_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; scalar_blake3 — Blake3 hash scalar reference
; Input:  rdi = input, rsi = len, rdx = output (32 bytes)
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global scalar_blake3
scalar_blake3:
    PROLOGUE_SAVE rbx
    ; TODO: scalar Blake3 implementation
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; scalar_chunk — Content-defined chunking (scalar)
; Input:  rdi = data, rsi = len, rdx = chunk bounds output
; Output: rax = number of chunks
; -----------------------------------------------------------------------------
global scalar_chunk
scalar_chunk:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; scalar_diff — Scalar diff of two buffers
; Input:  rdi = a, rsi = b, rdx = len
; Output: rax = number of differing bytes
; -----------------------------------------------------------------------------
global scalar_diff
scalar_diff:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rdx
    xor     rax, rax
.diff_loop:
    test    rcx, rcx
    jz      .done
    mov     dl, [rdi]
    cmp     dl, [rsi]
    jne     .found_diff
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .diff_loop
.found_diff:
    inc     rax
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .diff_loop
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

%endif ; VCS_KERNELS_SCALAR_ASM