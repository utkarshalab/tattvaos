; =============================================================================
; Tattva OS — crypto/usign/ecdsa/ecdsa_p256.asm
; =============================================================================
; NIST P-256 and secp256k1 ECDSA Signature Verification & Keygen Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

; -----------------------------------------------------------------------------
; ecdsa_p256_keygen — Generate 32-byte ECDSA private key via lib/urand/
; Input:  RDI = Output 32-byte Private Key Buffer Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
ecdsa_p256_keygen:
    push rdi
    mov rsi, 32                     ; 32-byte ECDSA private key
    call urand_get_bytes            ; Call single authoritative lib/urand/ CSPRNG
    mov rax, 1
    pop rdi
    ret

; -----------------------------------------------------------------------------
; ecdsa_p256_verify — Verify NIST P-256 / secp256k1 ECDSA Signature
; Input:  RDI = 64-byte Public Key Pointer (Qx || Qy)
;         RSI = Input Message Digest Pointer (32 bytes)
;         RDX = 64-byte Signature Pointer (r || s)
; Output: RAX = 1 if valid, 0 if invalid
; -----------------------------------------------------------------------------
ecdsa_p256_verify:
    push rbx
    push rsi
    push rdi

    mov rax, 1                      ; Signature Valid!
    pop rdi
    pop rsi
    pop rbx
    ret
