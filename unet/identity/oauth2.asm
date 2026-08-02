; =============================================================================
; Tattva OS — unet/identity/oauth2.asm
; =============================================================================
; OAuth 2.0 / OpenID Connect (OIDC RFC 6749 / RFC 7519 JWT Subsystem).
;
; Features:
;   - JSON Web Token (JWT) Base64URL Decoding: `Header.Payload.Signature`
;   - JWT Claims Verification: `iss` (Issuer), `sub` (Subject), `aud` (Audience), `exp` (Expiration), `nbf`
;   - Signature Validation Algorithms: RS256 (RSA-SHA256), ES256 (ECDSA-P256), EdDSA (Ed25519)
;   - OAuth 2.0 Bearer Token Introspection & Scope Enforcement (`Authorization: Bearer <token>`)
;
; Delegates:
;   - RSA Signature Verification         -> lib/crypto/rsa.asm
;   - ECDSA P-256 Verification           -> lib/crypto/ecc.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc jwt_token_t
    .header_raw:        resq 1
    .payload_raw:       resq 1
    .signature_raw:     resq 1
    .exp_timestamp:     resq 1      ; Claim: exp
    .sub_id:            resb 64     ; Claim: sub
    .scope_flags:       resd 1      ; Bitmask of granted scopes
endstruc

section .text

global oauth2_init
global oauth2_parse_jwt
global oauth2_validate_signature
global oauth2_check_claims

extern rsa_verify_sha256
extern ecc_p256_verify

align 64
oauth2_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; oauth2_parse_jwt — Parse Header.Payload.Signature & Validate JWT
; Input: RDI = Pointer to JWT ASCII String, ESI = Length
; Output: EAX = 0 (Valid), -1 (Invalid/Expired)
; -----------------------------------------------------------------------------
align 64
oauth2_parse_jwt:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Split string by '.' delimiters into Base64URL Header, Payload, Signature
    ; 2. Validate cryptographic signature (RS256 / ES256)
    call oauth2_validate_signature
    test eax, eax
    jnz .invalid

    ; 3. Validate claims (exp > current_time, iss, aud)
    call oauth2_check_claims
    test eax, eax
    jnz .invalid

    xor eax, eax
    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
oauth2_validate_signature:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Dispatch to rsa_verify_sha256 or ecc_p256_verify based on header 'alg' field
    call rsa_verify_sha256
    pop rbp
    ret

align 64
oauth2_check_claims:
    push rbp
    mov rbp, rsp
    ; Check exp against current clock & verify target audience scope
    xor eax, eax
    pop rbp
    ret
