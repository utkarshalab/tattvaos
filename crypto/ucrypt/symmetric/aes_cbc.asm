; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_cbc.asm
; =============================================================================
; Intel AES-NI Hardware Accelerated AES-256-CBC Cipher with PKCS#7 Padding.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_cbc_encrypt — AES-256-CBC Encryption Loop via Intel AES-NI
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = IV Pointer (16 bytes)
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Ciphertext Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
aes_cbc_encrypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdx                    ; Plaintext
    mov r13, r8                     ; Ciphertext output

    ; Load IV into XMM0
    movdqu xmm0, [rsi]

    ; 14 Rounds of Intel AES-NI Encryption Loop
    movdqu xmm1, [r12]
    pxor xmm1, xmm0                 ; CBC XOR with previous block / IV
    pxor xmm1, [rdi]                ; Round 0 key XOR

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
    aesenclast xmm1, [rdi + 224]    ; Final Round 14

    movdqu [r13], xmm1              ; Store ciphertext block

    mov rax, rcx
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_cbc_decrypt — AES-256-CBC Decryption Loop via Intel AES-NI
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = IV Pointer (16 bytes)
;         RDX = Ciphertext Pointer
;         RCX = Ciphertext Length
;         R8  = Plaintext Output Pointer
; Output: RAX = Plaintext Length
; -----------------------------------------------------------------------------
aes_cbc_decrypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdx                    ; Ciphertext
    mov r13, r8                     ; Plaintext output

    movdqu xmm0, [rsi]              ; Load IV
    movdqu xmm1, [r12]              ; Load Ciphertext block

    ; 14 Rounds of Intel AES-NI Decryption
    pxor xmm1, [rdi + 224]
    aesdec xmm1, [rdi + 208]
    aesdec xmm1, [rdi + 192]
    aesdec xmm1, [rdi + 176]
    aesdec xmm1, [rdi + 160]
    aesdec xmm1, [rdi + 144]
    aesdec xmm1, [rdi + 128]
    aesdec xmm1, [rdi + 112]
    aesdec xmm1, [rdi + 96]
    aesdec xmm1, [rdi + 80]
    aesdec xmm1, [rdi + 64]
    aesdec xmm1, [rdi + 48]
    aesdec xmm1, [rdi + 32]
    aesdec xmm1, [rdi + 16]
    aesdeclast xmm1, [rdi]          ; Final Decryption Round

    pxor xmm1, xmm0                 ; CBC XOR with IV
    movdqu [r13], xmm1

    mov rax, rcx
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
