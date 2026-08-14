; =============================================================================
; Tattva OS — crypto/ux509/ux509.inc
; =============================================================================
; X.509 v3 PKI Certificate Context Definitions, OIDs & Policy Flags.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef CRYPTO_UX509_UX509_INC
%define CRYPTO_UX509_UX509_INC

; ASN.1 DER Tag Constants
ASN1_TAG_INTEGER        equ 0x02
ASN1_TAG_BIT_STRING     equ 0x03
ASN1_TAG_OCTET_STRING   equ 0x04
ASN1_TAG_NULL           equ 0x05
ASN1_TAG_OID            equ 0x06
ASN1_TAG_SEQUENCE       equ 0x30
ASN1_TAG_SET            equ 0x31
ASN1_TAG_UTCTIME        equ 0x17
ASN1_TAG_GENERALIZED    equ 0x18

; Extended Key Usage (EKU) Flags
UX509_EKU_SERVER_AUTH   equ (1 << 0)  ; TLS 1.3 Web Server Authentication
UX509_EKU_CLIENT_AUTH   equ (1 << 1)  ; mTLS Client Authentication
UX509_EKU_CODE_SIGNING  equ (1 << 2)  ; Kernel Driver & Boot Binary Signing

; OID Algorithm IDs
UX509_OID_ED25519       equ 1
UX509_OID_ECDSA_P256    equ 2
UX509_OID_RSA_SHA256    equ 3
UX509_OID_DILITHIUM     equ 4

; Maximum Depth Limit for ASN.1 DER Nesting
UX509_MAX_RECURSION     equ 16

; -----------------------------------------------------------------------------
; Master Certificate Container Structure (512 bytes)
; -----------------------------------------------------------------------------
struc ux509_cert_t
    .version        resd 1          ; +000: X.509 Version (3 = v3)
    .sig_algo       resd 1          ; +004: Signature Algo ID (Ed25519, ECDSA_P256, RSA...)
    .serial         resb 16         ; +008: 16-byte Serial Number
    .not_before     resq 1          ; +024: 64-bit Unix Timestamp (Validity start)
    .not_after      resq 1          ; +032: 64-bit Unix Timestamp (Validity expiry)
    .pubkey_algo    resd 1          ; +040: Public Key Algo ID
    .pubkey_ptr     resq 1          ; +044: Pointer to extracted Public Key
    .pubkey_len     resd 1          ; +052: Public Key size in bytes
    .issuer_str     resb 64           ; +056: Sanitized ASCII Issuer string
    .subject_str    resb 64           ; +120: Sanitized ASCII Subject string
    .san_domain     resb 64           ; +184: Primary SAN Domain Name (e.g. "*.tattva.os")
    .fingerprint    resb 32         ; +248: 32-byte SHA-256 Certificate Thumbprint
    .is_ca          resd 1          ; +280: 1 if CA certificate, 0 if End-Entity
    .is_self_signed resd 1          ; +284: 1 if Self-Signed Root CA
    .path_len_limit resd 1          ; +288: Max intermediate path length constraint
    .eku_flags      resd 1          ; +292: Extended Key Usage flags (serverAuth...)
    .flags          resd 1          ; +296: Security & Validation Flags
    .sig_ptr        resq 1          ; +300: Pointer to raw Signature bytes
    .sig_len        resd 1          ; +308: Raw Signature length
    .reserved       resq 25         ; +312..+512: L1 Cache Line Padding
endstruc

ux509_cert_t_size equ 512

%endif ; CRYPTO_UX509_UX509_INC
