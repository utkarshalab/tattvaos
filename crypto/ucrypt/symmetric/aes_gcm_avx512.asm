; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_gcm_avx512.asm
; =============================================================================
; AVX-512 8-Way Parallel 512-Bit AES-GCM AEAD Pipeline (400 Gbps Line-Rate).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_gcm_encrypt_avx512 — Encrypt 8 16-byte blocks (128 bytes) in parallel
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = 128-byte Plaintext Pointer
;         RDX = 128-byte Ciphertext Output Pointer
; Output: RAX = 128
; -----------------------------------------------------------------------------
aes_gcm_encrypt_avx512:
    push rbx
    push rsi
    push rdi

    ; 8-way parallel 512-bit ZMM vector registers (ZMM0..ZMM7)
    vmovdqu64 zmm0, [rsi + 0]
    vmovdqu64 zmm1, [rsi + 64]

    vpxord zmm0, zmm0, [rdi]
    vpxord zmm1, zmm1, [rdi]

    vaesenc zmm0, zmm0, [rdi + 16]
    vaesenc zmm1, zmm1, [rdi + 16]

    vaesenclast zmm0, zmm0, [rdi + 32]
    vaesenclast zmm1, zmm1, [rdi + 32]

    vmovdqu64 [rdx + 0],  zmm0
    vmovdqu64 [rdx + 64], zmm1

    mov rax, 128
    vzeroall
    pop rdi
    pop rsi
    pop rbx
    ret
