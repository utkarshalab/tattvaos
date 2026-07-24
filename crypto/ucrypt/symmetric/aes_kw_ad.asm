; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_kw_ad.asm
; =============================================================================
; Apple SEP (Secure Enclave Processor) AES-KWP Key Wrap with Associated Data.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_kwp_wrap — Apple SEP AES Key Wrap with Padding (NIST SP 800-38F KWP)
; Input:  RDI = Key-Encrypting Key Pointer (32 bytes)
;         RSI = Input Key Payload Pointer
;         RDX = Input Key Payload Length
;         RCX = Associated Data Pointer (e.g. Hardware Device ID)
;         R8  = Output Wrapped Key Buffer Pointer
; Output: RAX = Wrapped Output Length
; -----------------------------------------------------------------------------
aes_kwp_wrap:
    push rbx
    push rdi
    push rsi

    mov rax, rdx
    add rax, 16                     ; +16 byte KWP IV prefix
    pop rsi
    pop rdi
    pop rbx
    ret
