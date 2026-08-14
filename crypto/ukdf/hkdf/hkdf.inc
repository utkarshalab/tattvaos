; =============================================================================
; Tattva OS — crypto/ukdf/hkdf/hkdf.inc
; =============================================================================
; HKDF (RFC 5869), Argon2id, and PBKDF2 Context Definitions & Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef CRYPTO_UKDF_HKDF_INC
%define CRYPTO_UKDF_HKDF_INC

; KDF Algorithm IDs
UKDF_ALGO_HKDF_SHA256 equ 1
UKDF_ALGO_HKDF_SHA512 equ 2
UKDF_ALGO_ARGON2ID    equ 3
UKDF_ALGO_PBKDF2      equ 4

; Maximum Output Key Limit (bytes)
HKDF_MAX_OKM_SIZE     equ 8192

; -----------------------------------------------------------------------------
; HKDF Context Structure (72 bytes)
; -----------------------------------------------------------------------------
struc hkdf_ctx_t
    .hash_algo          resd 1      ; +00: Hash Algorithm ID (1=SHA256, 2=SHA512)
    .prk_len            resd 1      ; +04: PRK length in bytes (32 for SHA256, 64 for SHA512)
    .prk                resb 64     ; +08: 64-byte Pseudo-Random Key buffer
endstruc


%endif ; CRYPTO_UKDF_HKDF_INC
