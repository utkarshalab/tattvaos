; =============================================================================
; Tattva OS — crypto/uhash/sha256/sha256.inc
; =============================================================================
; SHA-256 Context Structure Definitions & Initial Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef CRYPTO_UHASH_SHA256_INC
%define CRYPTO_UHASH_SHA256_INC

SHA256_BLOCK_SIZE   equ 64          ; 64-byte message block
SHA256_DIGEST_SIZE  equ 32          ; 32-byte (256-bit) digest

; -----------------------------------------------------------------------------
; SHA-256 Context Structure (112 bytes)
; -----------------------------------------------------------------------------
struc sha256_ctx_t
    .state      resd 8              ; +00: 8 x 32-bit state words (H0..H7)
    .count      resq 1              ; +32: Total bit count processed (64-bit)
    .buf        resb 64             ; +40: 64-byte message buffer
    .buf_len    resd 1              ; +104: Unprocessed bytes in buf (0..63)
    .flags      resd 1              ; +108: Flags (Bit 0 = Use SHA-NI hardware)
endstruc


%endif ; CRYPTO_UHASH_SHA256_INC
