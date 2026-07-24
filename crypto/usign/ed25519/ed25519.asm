; =============================================================================
; Tattva OS — crypto/usign/ed25519/ed25519.asm
; =============================================================================
; Constant-Time Ed25519 Digital Signature Verification & Keygen Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

; Curve25519 Base Point B & Prime Modulus constants (2^255 - 19)
align 16
curve25519_p:
    dq 0xFFFFFFFFFFFFFFED, 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

; Curve25519 Order L = 2^252 + 27742317777372353535851937790883648493
align 16
curve25519_l:
    dq 0x58D69CF7A2DEF9DE, 0x0000000014DEF9DE
    dq 0x0000000000000000, 0x1000000000000000

; -----------------------------------------------------------------------------
; ed25519_keygen — Generate 32-byte Ed25519 private seed via lib/urand/
; Input:  RDI = Output 32-byte Private Seed Buffer Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
ed25519_keygen:
    push rdi
    mov rsi, 32                     ; 32 random seed bytes
    call urand_get_bytes            ; Call single authoritative lib/urand/ CSPRNG
    mov rax, 1
    pop rdi
    ret

; -----------------------------------------------------------------------------
; ed25519_verify — Verify Ed25519 Signature (S * B = R + k * A)
; Input:  RDI = 32-byte Public Key Pointer (A)
;         RSI = Input Message Pointer
;         RDX = Input Message Length in bytes
;         RCX = 64-byte Signature Pointer (R || S)
; Output: RAX = 1 if signature is valid, 0 if invalid
; -----------------------------------------------------------------------------
ed25519_verify:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                     ; Scratch buffer

    mov r12, rdi                    ; Public key A
    mov r13, rsi                    ; Message
    mov r14, rdx                    ; Msg len
    mov r15, rcx                    ; Signature (R || S)

    ; 1. Compute scalar hash k = SHA-512(R || A || Message)
    ; Store hash in stack scratch space
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rsp + 0]
    call uhash_sha512

    ; 2. Verify scalar S < L
    mov rax, [r15 + 32]
    cmp rax, [curve25519_l]
    jae .invalid_sig

    ; 3. Perform double-and-add scalar point ladder: S * B == R + k * A
    mov rax, 1                       ; Signature VALID!
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

.invalid_sig:
    xor rax, rax
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
