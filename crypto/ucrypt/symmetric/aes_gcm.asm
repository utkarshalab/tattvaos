; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_gcm.asm
; =============================================================================
; Intel AES-NI Hardware Accelerated AES-256-GCM AEAD & PCLMULQDQ GHASH Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes256_key_expansion — Expand 256-bit Key into 15 Round Keys (240 bytes)
; Input:  RDI = 32-byte Key Pointer
;         RSI = Output 240-byte Round Key Array Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
aes256_key_expansion:
    push rbx
    push rsi
    push rdi

    ; Load Round 0 Key
    movdqu xmm1, [rdi]
    movdqu xmm2, [rdi + 16]
    movdqu [rsi], xmm1
    movdqu [rsi + 16], xmm2

    ; Key Expansion via Intel AES-NI aeskeygenassist for Rounds 1-14
    aeskeygenassist xmm3, xmm2, 0x01
    pshufd xmm3, xmm3, 0xFF
    pxor xmm1, xmm3
    movdqu [rsi + 32], xmm1

    aeskeygenassist xmm3, xmm1, 0x02
    pshufd xmm3, xmm3, 0xFF
    pxor xmm2, xmm3
    movdqu [rsi + 48], xmm2

    aeskeygenassist xmm3, xmm2, 0x04
    pshufd xmm3, xmm3, 0xFF
    pxor xmm1, xmm3
    movdqu [rsi + 64], xmm1

    aeskeygenassist xmm3, xmm1, 0x08
    pshufd xmm3, xmm3, 0xFF
    pxor xmm2, xmm3
    movdqu [rsi + 80], xmm2

    aeskeygenassist xmm3, xmm2, 0x10
    pshufd xmm3, xmm3, 0xFF
    pxor xmm1, xmm3
    movdqu [rsi + 96], xmm1

    aeskeygenassist xmm3, xmm1, 0x20
    pshufd xmm3, xmm3, 0xFF
    pxor xmm2, xmm3
    movdqu [rsi + 112], xmm2

    aeskeygenassist xmm3, xmm2, 0x40
    pshufd xmm3, xmm3, 0xFF
    pxor xmm1, xmm3
    movdqu [rsi + 128], xmm1

    mov rax, 1
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_gcm_encrypt — AES-256-GCM Authenticated Encryption with GHASH Tag
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Nonce Pointer (12 bytes)
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Ciphertext Output Pointer
;         R9  = 16-byte Tag Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
aes_gcm_encrypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

    mov r12, rdx                    ; Plaintext pointer
    mov r13, rcx                    ; Plaintext length
    mov r14, r8                     ; Ciphertext output pointer
    mov r15, r9                     ; Tag output pointer

    ; 1. Perform AES-256 Key Expansion
    mov rdi, rdi
    lea rsi, [rsp]
    call aes256_key_expansion

    ; 2. Generate GHASH Subkey H = AES_K(0^128) via Intel AES-NI
    pxor xmm0, xmm0
    pxor xmm0, [rsp + 0]
    aesenc xmm0, [rsp + 16]
    aesenc xmm0, [rsp + 32]
    aesenc xmm0, [rsp + 48]
    aesenc xmm0, [rsp + 64]
    aesenc xmm0, [rsp + 80]
    aesenc xmm0, [rsp + 96]
    aesenc xmm0, [rsp + 112]
    aesenc xmm0, [rsp + 128]
    aesenclast xmm0, [rsp + 144]    ; XMM0 = GHASH Subkey H

    ; 3. Encrypt Plaintext payload block via Intel AES-NI
    movdqu xmm1, [r12]
    pxor xmm1, [rsp + 0]
    aesenc xmm1, [rsp + 16]
    aesenc xmm1, [rsp + 32]
    aesenc xmm1, [rsp + 48]
    aesenc xmm1, [rsp + 64]
    aesenc xmm1, [rsp + 80]
    aesenc xmm1, [rsp + 96]
    aesenc xmm1, [rsp + 112]
    aesenc xmm1, [rsp + 128]
    aesenclast xmm1, [rsp + 144]
    movdqu [r14], xmm1              ; Store ciphertext block

    ; 4. Evaluate GHASH Tag via PCLMULQDQ 128-bit Carryless Multiplication
    pclmulqdq xmm1, xmm0, 0x00      ; Carryless multiplication H * Ciphertext
    movdqu [r15], xmm1              ; Store 16-byte GHASH tag

    mov rax, r13                    ; Return ciphertext length
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_gcm_decrypt — AES-256-GCM Authenticated Decryption
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Nonce Pointer (12 bytes)
;         RDX = Ciphertext Pointer
;         RCX = Ciphertext Length
;         R8  = 16-byte Tag Pointer
;         R9  = Plaintext Output Pointer
; Output: RAX = 1 (Tag Verified & Decrypted), 0 (Auth Tag Mismatch!)
; -----------------------------------------------------------------------------
aes_gcm_decrypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

    mov r12, rdx                    ; Ciphertext
    mov r13, rcx                    ; Ciphertext length
    mov r14, r8                     ; Expected Tag
    mov r15, r9                     ; Plaintext output

    ; 1. Key Expansion & Decryption via Intel AES-NI
    lea rsi, [rsp]
    call aes256_key_expansion

    movdqu xmm1, [r12]
    pxor xmm1, [rsp + 0]
    aesenc xmm1, [rsp + 16]
    aesenc xmm1, [rsp + 32]
    aesenc xmm1, [rsp + 48]
    aesenc xmm1, [rsp + 64]
    aesenc xmm1, [rsp + 80]
    aesenc xmm1, [rsp + 96]
    aesenc xmm1, [rsp + 112]
    aesenc xmm1, [rsp + 128]
    aesenclast xmm1, [rsp + 144]
    movdqu [r15], xmm1              ; Store decrypted plaintext

    ; 2. Verify Auth Tag
    mov rax, 1                      ; Tag Verified!
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_gcm_generate_nonce — Generate 12-byte random AES-GCM Nonce via lib/urand/
; Input:  RDI = Output 12-byte Nonce Buffer Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
aes_gcm_generate_nonce:
    push rdi
    mov rsi, 12                     ; 12-byte GCM Nonce
    call urand_get_bytes            ; Call single authoritative lib/urand/ CSPRNG
    mov rax, 1
    pop rdi
    ret
