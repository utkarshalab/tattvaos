; =============================================================================
; File     : src/kernels/avx2/avx2.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: AVX2-accelerated kernels — Blake3, chunking, diff.
; =============================================================================

%ifndef VCS_KERNELS_AVX2_ASM
%define VCS_KERNELS_AVX2_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; avx2_blake3 — Blake3 hash AVX2 path
; Input:  rdi = input, rsi = len, rdx = output (32 bytes)
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global avx2_blake3
avx2_blake3:
    PROLOGUE_SAVE rbx
    ; TODO: AVX2 Blake3 implementation
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; avx2_chunk — Content-defined chunking (AVX2)
; Input:  rdi = data, rsi = len, rdx = chunk bounds output
; Output: rax = number of chunks
; -----------------------------------------------------------------------------
global avx2_chunk
avx2_chunk:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; avx2_diff — AVX2 diff of two buffers (256-bit compare)
; Input:  rdi = a, rsi = b, rdx = len
; Output: rax = number of differing bytes
; -----------------------------------------------------------------------------
global avx2_diff
avx2_diff:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rdx
    xor     rax, rax
.diff_loop:
    cmp     rcx, 32
    jb      .scalar_tail
    vmovdqu ymm0, [rdi]
    vpcmpeqb ymm0, ymm0, [rsi]
    vpmovmskb eax, ymm0
    test    eax, eax
    jz      .all_match
    ; count differing bytes in this block
    popcnt    eax, eax
    add     rax, rax
.all_match:
    add     rdi, 32
    add     rsi, 32
    sub     rcx, 32
    jmp .diff_loop
.scalar_tail:
    ; fall through to scalar for remaining bytes
    test    rcx, rcx
    jz      .done
    mov     dl, [rdi]
    cmp     dl, [rsi]
    jne     .tail_diff
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .scalar_tail
.tail_diff:
    inc     rax
    inc     rdi
    inc     rsi
    dec     rcx
    jmp .scalar_tail
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

%endif ; VCS_KERNELS_AVX2_ASM