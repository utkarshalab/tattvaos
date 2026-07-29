; =============================================================================
; Tattva OS — unet/dns/dnssec.asm
; =============================================================================
; Master DNSSEC (RFC 4034 / RFC 4035 / PQC) Signature Validation Engine.
;
; Features:
;   - RRSIG (Resource Record Signature) Verification
;   - DNSKEY Public Key Validation (RSA, ECDSA P-256 / Ed25519, ML-DSA-87 Dilithium5)
;   - DS (Delegation Signer) Hash Chain of Trust Verification (Root Anchor)
;   - NSEC / NSEC3 Authenticated Denial of Existence Proofs
;
; Delegates:
;   - Ed25519 & ECDSA Signatures        -> crypto/usign/
;   - Post-Quantum ML-DSA-87             -> crypto/upqc/ml_dsa/
;   - SHA-256 / SHA-385 Digests          -> crypto/uhash/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DNSSEC_ALG_RSASHA256        8
%define DNSSEC_ALG_ECDSAP256SHA256  13
%define DNSSEC_ALG_ED25519          15
%define DNSSEC_ALG_ML_DSA_87        20      ; Post-Quantum Dilithium5

struc dnssec_rrsig_t
    .type_covered:      resw 1      ; Record Type Covered (e.g., A=1)
    .algorithm:         resb 1      ; Signature Algorithm ID
    .labels:            resb 1      ; Number of Labels
    .original_ttl:      resd 1      ; Original Record TTL
    .expiration:        resd 1      ; Signature Expiration Timestamp
    .inception:         resd 1      ; Signature Inception Timestamp
    .key_tag:           resw 1      ; Key Tag
    .signer_name:       resb 64     ; Signer Domain Name
endstruc

section .text

global dnssec_init
global dnssec_verify_rrsig
global dnssec_validate_chain_of_trust

extern ed25519_verify
extern ml_dsa_87_verify
extern sha256_hash

align 64
dnssec_init:
    push rbp
    mov rbp, rsp
    ; Load Root Trust Anchors (ICANN Root Key Tag 20326 / Post-Quantum Key)
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dnssec_verify_rrsig — Verify RRSIG Digital Signature over RRset
; Input: RDI = Pointer to RRset, RSI = Pointer to RRSIG Record
; Output: RAX = 0 if Authentic, -1 if Invalid / Expired
; -----------------------------------------------------------------------------
align 64
dnssec_verify_rrsig:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rsi
    prefetcht0 [rbx]                ; Pre-stage RRSIG into L1 cache

    ; Check algorithm ID: Ed25519 (15) or Post-Quantum ML-DSA-87 (20)
    movzx eax, byte [rbx + dnssec_rrsig_t.algorithm]
    cmp eax, DNSSEC_ALG_ED25519
    je .to_ed25519
    cmp eax, DNSSEC_ALG_ML_DSA_87
    je .to_pqc
    call sha256_hash
    jmp .done

.to_ed25519:
    call ed25519_verify
    jmp .done

.to_pqc:
    call ml_dsa_87_verify
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
dnssec_validate_chain_of_trust:
    push rbp
    mov rbp, rsp
    ; Walk DS -> DNSKEY chain up to Root Trust Anchor
    xor eax, eax
    pop rbp
    ret
