; =============================================================================
; str/encoding/ascii.asm
; US-ASCII ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm  (EncCodec struct, callback ABI)
;
; -----------------------------------------------------------------------------
; US-ASCII is the simplest encoding: 7-bit, bytes 0x00-0x7F map directly
; to codepoints U+0000-U+007F. Bytes >= 0x80 are invalid.
;
; This codec is the reference implementation of the codec callback ABI:
;   decode_one(src, src_len, *out_cp) → bytes consumed (always 1), or error
;   encode_one(cp, dst, dst_cap)      → bytes written (1), or error
;
; Functions:
;   str_ascii_decode_one  — decode one ASCII byte → codepoint
;   str_ascii_encode_one  — encode one codepoint → ASCII byte
;   str_ascii_codec       — get the EncCodec descriptor
;   str_ascii_validate    — check if a buffer is valid ASCII
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_ascii_name: db "US-ASCII", 0

section .text

; -----------------------------------------------------------------------------
; str_ascii_decode_one
;
; Decode a single ASCII byte to a codepoint.
;
; Signature:
;   int64_t str_ascii_decode_one(const uint8_t *src, uint64_t src_len,
;                                 uint32_t *out_cp)
;
; Arguments:
;   RDI  — source bytes
;   RSI  — remaining source length
;   RDX  — pointer to output codepoint
;
; Returns:
;   RAX  = 1               bytes consumed
;   RAX  = STR_ERR_ENCODING (negative)  invalid byte (>= 0x80)
;   RAX  = STR_ERR_ITER_END (negative)  no input
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_decode_one

    test    rsi, rsi
    jz      .ad_empty

    movzx   eax, byte [rdi]
    test    al, 0x80
    jnz     .ad_invalid         ; high bit set → not ASCII

    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.ad_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ad_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_ascii_decode_one

; -----------------------------------------------------------------------------
; str_ascii_encode_one
;
; Encode a codepoint to a single ASCII byte.
;
; Signature:
;   int64_t str_ascii_encode_one(uint32_t cp, uint8_t *dst, uint64_t dst_cap)
;
; Returns:
;   RAX  = 1   bytes written
;   RAX  = STR_ERR_ENCODING  codepoint not representable in ASCII (>= 0x80)
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_encode_one

    cmp     edi, 0x7F
    ja      .ae_unmappable

    test    rdx, rdx
    jz      .ae_nospace

    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.ae_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ae_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ascii_encode_one

; -----------------------------------------------------------------------------
; str_ascii_validate
;
; Check whether a byte buffer is valid US-ASCII (all bytes < 0x80).
;
; Signature:
;   int64_t str_ascii_validate(const uint8_t *src, uint64_t len)
;
; Returns:
;   RAX  = 1   valid ASCII
;   RAX  = 0   contains non-ASCII bytes
; -----------------------------------------------------------------------------

STR_FUNC str_ascii_validate

    test    rsi, rsi
    jz      .av_valid

    xor     rcx, rcx

    ; process 8 bytes at a time
.av_word_loop:
    mov     rax, rsi
    sub     rax, rcx
    cmp     rax, 8
    jb      .av_byte_loop

    mov     rax, [rdi + rcx]
    mov     r8, 0x8080808080808080
    test    rax, r8
    jnz     .av_invalid

    add     rcx, 8
    jmp     .av_word_loop

.av_byte_loop:
    cmp     rcx, rsi
    jae     .av_valid

    movzx   eax, byte [rdi + rcx]
    test    al, 0x80
    jnz     .av_invalid

    inc     rcx
    jmp     .av_byte_loop

.av_valid:
    mov     eax, 1
    pop     rbp
    ret

.av_invalid:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ascii_validate

; -----------------------------------------------------------------------------
; str_ascii_codec
;
; Return a pointer to the static EncCodec descriptor for US-ASCII.
;
; Signature:
;   const EncCodec *str_ascii_codec(void)
; -----------------------------------------------------------------------------

section .rodata
align 8
_ascii_codec_struct:
    dq str_ascii_decode_one     ; decode_one
    dq str_ascii_encode_one     ; encode_one
    dq _ascii_name              ; name
    dq 1                        ; max_bytes
    dq 0x02                     ; flags: ASCII_SUPERSET
    dq 0                        ; state_init

section .text

STR_FUNC str_ascii_codec
    lea     rax, [rel _ascii_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_ascii_codec