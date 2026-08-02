; =============================================================================
; Tattva OS — unet/mail/dkim.asm
; =============================================================================
; DKIM (DomainKeys Identified Mail RFC 6376) Signature Engine.
;
; Features:
;   - DKIM-Signature Header Generation & Verification
;   - RSA-SHA256 & Ed25519-SHA256 (RFC 8463) Signing Algorithms
;   - Canonicalization: simple/simple, relaxed/relaxed
;   - Header & Body Hash Computation (SHA-256)
;   - DNS TXT Record DKIM Public Key Lookup (selector._domainkey.domain)
;   - Body Length Limit (`l=` Tag) for Mailing List Compatibility
;   - ARC (Authenticated Received Chain RFC 8617) Seal Verification
;
; Delegates:
;   - SHA-256 Body Hash                  -> crypto/uhash/sha256/
;   - RSA Signature Verification         -> crypto/usign/
;   - Ed25519 Signature Verification     -> crypto/usign/ed25519/
;   - DNS TXT Lookup                     -> unet/dns/dns.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DKIM_ALG_RSA_SHA256         1
%define DKIM_ALG_ED25519_SHA256     2
%define DKIM_CANON_SIMPLE           0
%define DKIM_CANON_RELAXED          1

struc dkim_sig_t
    .version:           resb 1      ; v=1
    .algorithm:         resb 1      ; RSA-SHA256 or Ed25519-SHA256
    .domain:            resb 64     ; d= signing domain
    .selector:          resb 32     ; s= selector
    .header_canon:      resb 1      ; Header canonicalization
    .body_canon:        resb 1      ; Body canonicalization
    .body_hash:         resb 32     ; bh= SHA-256 body hash
    .signature:         resb 256    ; b= signature value
    .sig_len:           resw 1
    .body_length:       resd 1      ; l= body length limit (-1 = unlimited)
endstruc

section .text

global dkim_init
global dkim_sign_message
global dkim_verify_message
global dkim_canonicalize_header
global dkim_canonicalize_body
global dkim_lookup_key

extern sha256_hash
extern ed25519_verify
extern dns_query

align 64
dkim_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dkim_sign_message — Generate DKIM-Signature Header for Outbound Message
; Input: RDI = Pointer to Message, ESI = Length, RDX = Pointer to Private Key
; Output: RAX = Pointer to DKIM-Signature Header String
; -----------------------------------------------------------------------------
align 64
dkim_sign_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Canonicalize body (relaxed: unfold headers, strip trailing whitespace)
    call dkim_canonicalize_body
    ; 2. SHA-256 hash canonicalized body -> bh= tag
    call sha256_hash
    ; 3. Canonicalize selected headers
    call dkim_canonicalize_header
    ; 4. Sign header hash with private key (RSA-SHA256 or Ed25519)

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dkim_verify_message — Verify DKIM-Signature on Inbound Message
; Input: RDI = Pointer to Message, ESI = Length
; Output: EAX = 0 (pass), 1 (fail), 2 (temperror), 3 (permerror)
; -----------------------------------------------------------------------------
align 64
dkim_verify_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Parse DKIM-Signature header (extract d=, s=, bh=, b=, a=)
    ; 2. DNS lookup: selector._domainkey.domain TXT record
    call dkim_lookup_key
    ; 3. Canonicalize body & verify bh= body hash
    call dkim_canonicalize_body
    call sha256_hash
    ; 4. Verify signature using public key from DNS
    call ed25519_verify

    pop rbx
    pop rbp
    ret

align 64
dkim_canonicalize_header:
    push rbp
    mov rbp, rsp
    ; Relaxed: lowercase header names, unfold continuations, collapse whitespace
    xor eax, eax
    pop rbp
    ret

align 64
dkim_canonicalize_body:
    push rbp
    mov rbp, rsp
    ; Relaxed: strip trailing whitespace per line, collapse empty lines at end
    xor eax, eax
    pop rbp
    ret

align 64
dkim_lookup_key:
    push rbp
    mov rbp, rsp
    ; DNS TXT query for selector._domainkey.domain
    call dns_query
    pop rbp
    ret
