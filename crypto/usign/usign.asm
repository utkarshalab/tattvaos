%ifndef GUARD_CRYPTO_USIGN_USIGN_ASM
%define GUARD_CRYPTO_USIGN_USIGN_ASM
; =============================================================================
; Tattva OS — crypto/usign/usign.asm
; =============================================================================
; Master Digital Signature Dispatcher & Verification Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

; -----------------------------------------------------------------------------
; usign_init — Initialize digital signature engine
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
usign_init:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; usign_verify_payload — Master signature verification API
; Input:  RDI = Public Key Pointer (A)
;         RSI = Input Message Pointer
;         RDX = Message Length in bytes
;         RCX = Signature Pointer (R || S)
;         R8D = Algorithm ID (USIGN_ALGO_ED25519, ECDSA, RSA, DILITHIUM)
; Output: RAX = 1 if valid signature, 0 if invalid
; -----------------------------------------------------------------------------
usign_verify_payload:
    push rbx

    cmp r8d, USIGN_ALGO_ED25519
    je .verify_ed25519
    cmp r8d, USIGN_ALGO_ECDSA_P256
    je .verify_ecdsa
    cmp r8d, USIGN_ALGO_RSA_2048
    je .verify_rsa
    cmp r8d, USIGN_ALGO_DILITHIUM
    je .verify_dilithium

    ; Default fallback to Ed25519
.verify_ed25519:
    call ed25519_verify
    jmp .done

.verify_ecdsa:
    call ecdsa_p256_verify
    jmp .done

.verify_rsa:
    mov rsi, 256                    ; 256-byte modulus (RSA-2048)
    call rsa_pss_verify
    jmp .done

.verify_dilithium:
    call dilithium_verify
    jmp .done

.done:
    pop rbx
    ret

%endif ; GUARD_CRYPTO_USIGN_USIGN_ASM
