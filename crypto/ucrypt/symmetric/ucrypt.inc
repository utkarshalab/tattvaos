; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/ucrypt.inc
; =============================================================================
; Symmetric Ciphers Context Definitions, AEAD Schemas & Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef CRYPTO_UCRYPT_UCRYPT_INC
%define CRYPTO_UCRYPT_UCRYPT_INC

; Cipher Algorithm IDs
UCRYPT_ALGO_AES_GCM_128      equ 1
UCRYPT_ALGO_AES_GCM_256      equ 2
UCRYPT_ALGO_AES_XTS_512      equ 3      ; 2 x 256-bit keys for UXFS disk encryption
UCRYPT_ALGO_CHACHA20_POLY1305 equ 4

; Tag & Nonce sizes
UCRYPT_AES_GCM_TAG_LEN      equ 16
UCRYPT_AES_GCM_NONCE_LEN    equ 12
UCRYPT_XTS_SECTOR_SIZE      equ 512    ; Standard 512-byte disk sector

; -----------------------------------------------------------------------------
; Symmetric Cipher Context Structure (292 bytes)
; -----------------------------------------------------------------------------
struc ucrypt_ctx_t
    .cipher_algo      resd 1        ; +00: Algorithm ID (1=AES_GCM_128...)
    .key_bits         resd 1        ; +04: Key size in bits (128, 256, 512)
    .round_keys       resb 240      ; +08: 240-byte AES expanded round key schedule
    .h_key            resb 16       ; +248: 16-byte GHASH H key
    .nonce            resb 16       ; +264: 16-byte Nonce/IV
    .tag              resb 16       ; +280: 16-byte Tag
endstruc


%endif ; CRYPTO_UCRYPT_UCRYPT_INC
