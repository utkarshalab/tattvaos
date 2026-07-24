; =============================================================================
; Tattva OS — lib/urand/urand.inc
; =============================================================================
; Ultimate Hyperscale Hardware TRNG & Fortuna CSPRNG Schemas & Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_URAND_URAND_INC
%define LIB_URAND_URAND_INC

URAND_SEED_SIZE     equ 32          ; 256-bit entropy seed
URAND_KEY_SIZE      equ 32          ; 256-bit ChaCha20 / AES key
URAND_NONCE_SIZE    equ 12          ; 96-bit nonce
URAND_FORTUNA_POOLS equ 32          ; Fortuna 32-Pool architecture
URAND_RESEED_LIMIT  equ 1024        ; Reseed limit

; Generator Selection IDs
URAND_GEN_CHACHA20  equ 1
URAND_GEN_AES_DRBG  equ 2

; Health Status Codes
URAND_HEALTH_OK     equ 1
URAND_HEALTH_FAILED equ 0

; -----------------------------------------------------------------------------
; Master Fortuna CSPRNG State Structure (512 bytes)
; -----------------------------------------------------------------------------
struc urand_ctx_t
    .key            resb 32         ; +000: Active 256-bit Key
    .nonce          resb 12         ; +032: Active Nonce
    .counter        resq 1          ; +044: 64-bit Block Counter
    .reseed_counter resq 1          ; +052: Reseed Counter
    .pools          resb (32 * 8)   ; +060: 32 x 8-byte Fortuna Entropy Pools
    .health_status  resd 1          ; +316: NIST SP 800-90B Health Status Flag
    .generator_id   resd 1          ; +320: Active Generator (CHACHA20 or AES)
    .initialized    resd 1          ; +324: Initialization status
    .reserved       resq 23         ; +328..+512: L1 Cache Line Padding
endstruc

urand_ctx_t_size equ 512

%endif ; LIB_URAND_URAND_INC
