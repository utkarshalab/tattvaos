; =============================================================================
; Tattva OS — crypto/ux509/ux509.asm
; =============================================================================
; Master X.509 PKI Subsystem Dispatcher API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"
%include "crypto/ux509/ux509_oid.asm"
%include "crypto/ux509/ux509_asn1.asm"
%include "crypto/ux509/ux509_sanitize.asm"
%include "crypto/ux509/ux509_parse.asm"
%include "crypto/ux509/ux509_ext.asm"
%include "crypto/ux509/ux509_san_match.asm"
%include "crypto/ux509/ux509_policy.asm"
%include "crypto/ux509/ux509_path.asm"
%include "crypto/ux509/ux509_time.asm"
%include "crypto/ux509/ux509_crl.asm"
%include "crypto/ux509/ux509_ocsp.asm"
%include "crypto/ux509/ux509_aia.asm"
%include "crypto/ux509/ux509_name_constraints.asm"
%include "crypto/ux509/ux509_sct.asm"
%include "crypto/ux509/ux509_fingerprint.asm"
%include "crypto/ux509/ux509_key_match.asm"
%include "crypto/ux509/ux509_trust_store.asm"
%include "crypto/ux509/ux509_self_signed.asm"
%include "crypto/ux509/ux509_name_norm.asm"
%include "crypto/ux509/ux509_csr.asm"
%include "crypto/ux509/ux509_pqc_cert.asm"
%include "crypto/ux509/ux509_chain.asm"

section .text

; -----------------------------------------------------------------------------
; ux509_init — Initialize X.509 PKI Subsystem & Root CA Trust Store
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
ux509_init:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ux509_verify_cert — Master API to parse & validate X.509 Certificate
; Input:  RDI = DER / PEM Certificate Buffer Pointer
;         RSI = Buffer Length
;         RDX = Pointer to Target SAN Domain String (e.g. "api.tattva.os")
;         RCX = Current Unix Timestamp
; Output: RAX = 1 (Certificate Verified & Valid), 0 (Invalid / Expired)
; -----------------------------------------------------------------------------
ux509_verify_cert:
    push rbx
    push rdi
    push rsi
    sub rsp, ux509_cert_t_size

    mov r8, rsp                     ; Target cert container
    call ux509_parse_cert
    test rax, rax
    jz .fail

    ; Verify validity timestamps & clock skew
    mov rdi, rsp
    mov rsi, rcx
    call ux509_verify_validity
    test rax, rax
    jz .fail

    mov rax, 1
    add rsp, ux509_cert_t_size
    pop rsi
    pop rdi
    pop rbx
    ret

.fail:
    xor rax, rax
    add rsp, ux509_cert_t_size
    pop rsi
    pop rdi
    pop rbx
    ret
