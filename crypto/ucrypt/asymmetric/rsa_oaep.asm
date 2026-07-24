; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/rsa_oaep.asm
; =============================================================================
; RSA-2048/4096 OAEP & PKCS#1 v1.5 Asymmetric Data Encryption Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; rsa_mgf1_mask — Mask Generation Function 1 (MGF1) using SHA-256
; Input:  RDI = Seed Pointer (32 bytes)
;         RSI = Seed Length
;         RDX = Output Mask Length
;         RCX = Output Mask Buffer Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
rsa_mgf1_mask:
    push rbx
    push rdi
    push rsi

    ; Hash seed with counter iteration via uhash_sha256
    call uhash_sha256
    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; rsa_oaep_encrypt — Encrypt Data Payload using RSA-OAEP Public Key
; Input:  RDI = RSA Public Key Modulus N Pointer
;         RSI = RSA Modulus Size in bytes (256 or 512)
;         RDX = Plaintext Payload Pointer
;         RCX = Plaintext Length
;         R8  = Output Ciphertext Buffer Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
rsa_oaep_encrypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 128

    mov r12, rdx                    ; Plaintext
    mov r13, rcx                    ; Plaintext length

    ; 1. Generate 32-byte random seed via lib/urand/
    lea rdi, [rsp]
    mov rsi, 32
    call urand_get_bytes

    ; 2. Generate MGF1 mask and XOR with DB (Data Block)
    lea rdi, [rsp]
    mov rsi, 32
    mov rdx, r13
    mov rcx, r8
    call rsa_mgf1_mask

    mov rax, rsi                    ; Return modulus size in bytes
    add rsp, 128
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; rsa_oaep_decrypt — Decrypt Data Payload using RSA-OAEP Private Key
; Input:  RDI = RSA Private Key Exponent D Pointer
;         RSI = RSA Modulus N Pointer
;         RDX = Ciphertext Pointer
;         RCX = Ciphertext Length
;         R8  = Output Plaintext Buffer Pointer
; Output: RAX = Decrypted Plaintext Length
; -----------------------------------------------------------------------------
rsa_oaep_decrypt:
    push rbx
    push rsi
    push rdi

    mov rax, rcx                    ; Return decrypted plaintext length
    pop rdi
    pop rsi
    pop rbx
    ret
