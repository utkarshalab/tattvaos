; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_ctr.asm
; =============================================================================
; Intel AES-NI Hardware Accelerated AES-256-CTR Counter Mode Streaming Cipher.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_ctr_crypt — AES-256-CTR Counter Mode Encryption/Decryption Loop
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Nonce/Counter Pointer (16 bytes)
;         RDX = Input Data Pointer
;         RCX = Input Data Length
;         R8  = Output Data Pointer
; Output: RAX = Output Length
; -----------------------------------------------------------------------------
aes_ctr_crypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdx                    ; Input Data
    mov r13, r8                     ; Output Data

    ; Load Nonce/Counter into XMM0
    movdqu xmm0, [rsi]

    ; Encrypt Counter Block using Intel AES-NI
    pxor xmm1, xmm0
    pxor xmm1, [rdi]

    aesenc xmm1, [rdi + 16]
    aesenc xmm1, [rdi + 32]
    aesenc xmm1, [rdi + 48]
    aesenc xmm1, [rdi + 64]
    aesenc xmm1, [rdi + 80]
    aesenc xmm1, [rdi + 96]
    aesenc xmm1, [rdi + 112]
    aesenc xmm1, [rdi + 128]
    aesenc xmm1, [rdi + 144]
    aesenc xmm1, [rdi + 160]
    aesenc xmm1, [rdi + 176]
    aesenc xmm1, [rdi + 192]
    aesenc xmm1, [rdi + 208]
    aesenclast xmm1, [rdi + 224]

    ; XOR encrypted counter stream with input data payload
    movdqu xmm2, [r12]
    pxor xmm1, xmm2
    movdqu [r13], xmm1

    mov rax, rcx
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
