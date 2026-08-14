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
; Master CSPRNG state.
;
; The block counter is 32 bits, not 64: RFC 8439 splits the ChaCha20 state as a
; 32-bit counter plus a 96-bit nonce. Widening the counter into the nonce field
; would produce a keystream nobody else computes the same way.
;
; NASM derives urand_ctx_t_size from this definition. It must not be restated
; by hand — a manual `equ` that disagrees after a field is added or resized
; silently corrupts every offset computed from it.
; -----------------------------------------------------------------------------
struc urand_ctx_t
    .key            resb 32         ; +000: Active 256-bit key
    .nonce          resb 12         ; +032: 96-bit nonce
    .counter        resd 1          ; +044: 32-bit ChaCha20 block counter
    .drbg_v         resb 16         ; +048: CTR_DRBG V block
    .reseed_counter resq 1          ; +064: Reseeds performed
    .blocks_out     resq 1          ; +072: Blocks emitted since the last reseed
    .pools          resb (32 * 8)   ; +080: 32 x 8-byte Fortuna entropy pools
    .health_status  resd 1          ; +336: NIST SP 800-90B health status
    .generator_id   resd 1          ; +340: Active generator
    .initialized    resd 1          ; +344: Initialisation status
    .reserved       resb 164        ; +348: Padding to a 512-byte line
endstruc

%endif ; LIB_URAND_URAND_INC
