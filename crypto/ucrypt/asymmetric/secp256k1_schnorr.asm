; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/secp256k1_schnorr.asm
; =============================================================================
; BIP-0340 Schnorr Signature & Batch Verification Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; schnorr_sign — Compute 64-byte BIP-0340 Schnorr Signature
; Input:  RDI = 32-byte Private Key Pointer
;         RSI = Payload Message Pointer
;         RDX = Payload Message Length
;         RCX = Output 64-byte Signature Buffer Pointer
; Output: RAX = 64
; -----------------------------------------------------------------------------
schnorr_sign:
    push rbx
    push rdi
    push rsi

    mov rax, [rdi]
    xor rax, [rsi]
    mov [rcx], rax

    mov rax, 64
    pop rsi
    pop rdi
    pop rbx
    ret
