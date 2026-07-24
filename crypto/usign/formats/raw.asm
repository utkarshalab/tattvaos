; =============================================================================
; Tattva OS — crypto/usign/formats/raw.asm
; =============================================================================
; Raw Binary Signature Envelope Parser.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

; -----------------------------------------------------------------------------
; parse_raw_sig — Parse raw binary signature
; Input:  RDI = Signature buffer pointer, RSI = Length (64 bytes)
;         RDX = Output usign_meta_t pointer
; Output: RAX = 1 if valid, 0 if invalid
; -----------------------------------------------------------------------------
parse_raw_sig:
    cmp rsi, 64
    jb .invalid

    mov dword [rdx + usign_meta_t.format_id], USIGN_FMT_RAW
    mov [rdx + usign_meta_t.sig_ptr], rdi
    mov dword [rdx + usign_meta_t.sig_len], 64

    mov rax, 1
    ret

.invalid:
    xor rax, rax
    ret
