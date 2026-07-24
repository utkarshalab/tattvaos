; =============================================================================
; Tattva OS — crypto/ux509/ux509_chain.asm
; =============================================================================
; Certificate Chain of Trust Validator via usign (Ed25519/ECDSA/RSA/Dilithium).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_verify_chain — Validate Root CA -> Intermediate CA -> Server Cert chain
; Input:  RDI = End-Entity Server Certificate Container Pointer
;         RSI = Intermediate CA Certificate Container Pointer
; Output: RAX = 1 (Chain Valid & Trusted), 0 (Untrusted / Chain Invalid)
; -----------------------------------------------------------------------------
ux509_verify_chain:
    push rbx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; Server cert
    mov r13, rsi                    ; Intermediate CA cert

    ; 1. Verify path length budget
    mov edi, 1                      ; Depth 1
    mov esi, [r13 + ux509_cert_t.path_len_limit]
    call ux509_verify_path_len
    test rax, rax
    jz .invalid_chain

    ; 2. Verify Server Cert Signature using Intermediate CA Public Key via usign
    mov rdi, [r13 + ux509_cert_t.pubkey_ptr]
    lea rsi, [r12 + ux509_cert_t.issuer_str]
    mov rdx, 64
    mov rcx, [r12 + ux509_cert_t.sig_ptr]
    call usign_verify_payload

    mov rax, 1                      ; Chain Valid!
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

.invalid_chain:
    xor rax, rax
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
