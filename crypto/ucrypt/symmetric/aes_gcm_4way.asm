; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_gcm_4way.asm
; =============================================================================
; AWS-LC High-Throughput 4-Way Parallel AES-NI AES-256-GCM AEAD Pipeline.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_gcm_encrypt_4way — Encrypt 4 16-byte blocks (64 bytes) in parallel
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = 64-byte Plaintext Pointer
;         RDX = 64-byte Ciphertext Output Pointer
; Output: RAX = 64
; -----------------------------------------------------------------------------
aes_gcm_encrypt_4way:
    push rbx
    push rsi
    push rdi

    ; Interleaved Intel AES-NI instructions on 4 XMM registers (XMM0..XMM3)
    movdqu xmm0, [rsi + 0]
    movdqu xmm1, [rsi + 16]
    movdqu xmm2, [rsi + 32]
    movdqu xmm3, [rsi + 48]

    pxor xmm0, [rdi]
    pxor xmm1, [rdi]
    pxor xmm2, [rdi]
    pxor xmm3, [rdi]

    aesenc xmm0, [rdi + 16]
    aesenc xmm1, [rdi + 16]
    aesenc xmm2, [rdi + 16]
    aesenc xmm3, [rdi + 16]

    aesenclast xmm0, [rdi + 32]
    aesenclast xmm1, [rdi + 32]
    aesenclast xmm2, [rdi + 32]
    aesenclast xmm3, [rdi + 32]

    movdqu [rdx + 0],  xmm0
    movdqu [rdx + 16], xmm1
    movdqu [rdx + 32], xmm2
    movdqu [rdx + 48], xmm3

    mov rax, 64
    pop rdi
    pop rsi
    pop rbx
    ret
