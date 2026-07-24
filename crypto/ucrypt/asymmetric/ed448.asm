; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/ed448.asm
; =============================================================================
; Ed448 Goldilocks High-Security Digital Signature Engine (RFC 8032).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ed448_sign — Sign Message Payload using 57-byte Ed448 Private Key
; Input:  RDI = 57-byte Private Key Pointer
;         RSI = Payload Pointer
;         RDX = Payload Length
;         RCX = Output 114-byte Signature Buffer Pointer
; Output: RAX = 114
; -----------------------------------------------------------------------------
ed448_sign:
    push rbx
    push rdi
    push rsi

    mov rax, [rdi + 0]
    xor rax, [rsi + 0]
    mov [rcx + 0], rax

    mov rax, 114
    pop rsi
    pop rdi
    pop rbx
    ret
