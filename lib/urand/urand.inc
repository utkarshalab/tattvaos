; =============================================================================
; Tattva OS — lib/urand/urand.inc
; =============================================================================
; Hardware TRNG & ChaCha20 CSPRNG Context Definitions & Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_URAND_URAND_INC
%define LIB_URAND_URAND_INC

URAND_SEED_SIZE     equ 32          ; 256-bit entropy seed
URAND_KEY_SIZE      equ 32          ; 256-bit ChaCha20 key
URAND_NONCE_SIZE    equ 12          ; 96-bit ChaCha20 nonce
URAND_RESEED_LIMIT  equ 1024        ; Reseed every 1024 random generation requests

; -----------------------------------------------------------------------------
; CSPRNG Context Structure (96 bytes)
; -----------------------------------------------------------------------------
struc urand_ctx_t
    .key            resb 32         ; +00: 256-bit ChaCha20 CSPRNG Key
    .nonce          resb 12         ; +32: 96-bit Nonce
    .counter        resq 1          ; +44: 64-bit Block Counter
    .reseed_counter resq 1          ; +52: Reseed Counter
    .pool           resb 32         ; +60: 256-bit Hardware Entropy Pool
    .initialized    resd 1          ; +92: Initialization status flag
endstruc

urand_ctx_t_size equ 96

%endif ; LIB_URAND_URAND_INC
