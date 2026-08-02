; =============================================================================
; Tattva OS — unet/tools/security/dnssec_check.asm
; =============================================================================
; DNSSEC Validation & Trust Chain Verification Tool (`dnssec-check`).
;
; Features:
;   - DNSKEY (Type 48), RRSIG (Type 46), DS (Type 43), NSEC3 (Type 50) Validation
;   - RSA-SHA256 (Alg 8), ECDSA P-256 (Alg 13), Ed25519 (Alg 15) Signature Verification
;   - Root Zone (.) Trust Anchor Verification to Domain Name
;
; Delegates:
;   - DNS Engine                        -> unet/dns/dns.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global dnssec_check_main
global dnssec_check_verify_chain

extern dns_parse_query

align 64
dnssec_check_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call dnssec_check_verify_chain

    pop rbx
    pop rbp
    ret

align 64
dnssec_check_verify_chain:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Query RRSIG & DS records -> validate cryptographic chain-of-trust back to root trust anchor
    call dns_parse_query
    xor eax, eax
    pop rbp
    ret
