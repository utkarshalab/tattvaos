; =============================================================================
; Tattva OS — crypto/uhash/blake3/blake3.inc
; =============================================================================
; BLAKE3 Context Structure Definitions & Flags.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef CRYPTO_UHASH_BLAKE3_INC
%define CRYPTO_UHASH_BLAKE3_INC

BLAKE3_KEY_LEN      equ 32          ; 32-byte key/IV
BLAKE3_OUT_LEN      equ 32          ; 32-byte (256-bit) digest
BLAKE3_BLOCK_LEN    equ 64          ; 64-byte block
BLAKE3_CHUNK_LEN    equ 1024        ; 1024-byte chunk

; Flags
BLAKE3_CHUNK_START  equ (1 << 0)
BLAKE3_CHUNK_END    equ (1 << 1)
BLAKE3_ROOT         equ (1 << 3)

; -----------------------------------------------------------------------------
; BLAKE3 Context Structure (116 bytes)
; -----------------------------------------------------------------------------
struc blake3_ctx_t
    .cv                 resd 8      ; +00: Chaining Value (8 x 32-bit words)
    .chunk_counter      resq 1      ; +32: 64-bit Chunk Index Counter
    .buf                resb 64     ; +40: 64-byte chunk buffer
    .buf_len            resd 1      ; +104: Unprocessed bytes in buf (0..63)
    .blocks_compressed  resb 1      ; +108: Block count in current chunk
    .flags              resd 1      ; +109: Flag bitmask
endstruc

blake3_ctx_t_size equ 116

%endif ; CRYPTO_UHASH_BLAKE3_INC
