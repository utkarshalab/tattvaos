%ifndef GUARD_LIB_STR_ENCODING_LATIN1_ASM
%define GUARD_LIB_STR_ENCODING_LATIN1_ASM
; =============================================================================
; str/encoding/latin1.asm
; ISO-8859-1 (Latin-1) ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm  (EncCodec struct)
;
; -----------------------------------------------------------------------------
; ISO-8859-1 (Latin-1) is the simplest 8-bit encoding: bytes 0x00-0xFF map
; DIRECTLY to codepoints U+0000-U+00FF. This is because Unicode's first 256
; codepoints were defined to be identical to Latin-1.
;
; This means:
;   decode: codepoint = byte           (trivial, always valid)
;   encode: byte = codepoint           (only if codepoint <= 0xFF)
;
; No lookup table needed — pure arithmetic.
;
; Functions:
;   str_latin1_decode_one
;   str_latin1_encode_one
;   str_latin1_codec
;   str_latin1_to_utf8     — bulk fast path
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_latin1_name: db "ISO-8859-1", 0

section .text

; -----------------------------------------------------------------------------
; str_latin1_decode_one
;
; Signature:
;   int64_t str_latin1_decode_one(const uint8_t *src, uint64_t src_len,
;                                  uint32_t *out_cp)
;
; Every byte is valid; codepoint = byte value.
; -----------------------------------------------------------------------------

STR_FUNC str_latin1_decode_one

    test    rsi, rsi
    jz      .ld_empty

    movzx   eax, byte [rdi]
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.ld_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_latin1_decode_one

; -----------------------------------------------------------------------------
; str_latin1_encode_one
;
; Signature:
;   int64_t str_latin1_encode_one(uint32_t cp, uint8_t *dst, uint64_t dst_cap)
;
; Codepoints 0x00-0xFF encode to a single byte. Higher → unmappable.
; -----------------------------------------------------------------------------

STR_FUNC str_latin1_encode_one

    cmp     edi, 0xFF
    ja      .le_unmappable

    test    rdx, rdx
    jz      .le_nospace

    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.le_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.le_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_latin1_encode_one

; -----------------------------------------------------------------------------
; str_latin1_to_utf8
;
; Bulk conversion fast path: Latin-1 buffer → UTF-8.
; Each byte 0x00-0x7F → 1 UTF-8 byte; 0x80-0xFF → 2 UTF-8 bytes.
;
; Signature:
;   int64_t str_latin1_to_utf8(const uint8_t *src, uint64_t src_len,
;                               uint8_t *dst, uint64_t dst_cap,
;                               uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_latin1_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

.lu_loop:
    cmp     r9, rsi
    jae     .lu_done

    movzx   eax, byte [rdi + r9]
    inc     r9

    cmp     al, 0x80
    jae     .lu_two_byte

    ; single byte (ASCII range)
    cmp     r10, rcx
    jae     .lu_overflow
    mov     [rdx + r10], al
    inc     r10
    jmp     .lu_loop

.lu_two_byte:
    ; 0x80-0xFF → 110xxxxx 10xxxxxx
    lea     r11, [r10 + 2]
    cmp     r11, rcx
    ja      .lu_overflow

    ; byte1 = 0xC0 | (cp >> 6)
    mov     r11d, eax
    shr     r11d, 6
    or      r11d, 0xC0
    mov     [rdx + r10], r11b
    inc     r10

    ; byte2 = 0x80 | (cp & 0x3F)
    and     eax, 0x3F
    or      eax, 0x80
    mov     [rdx + r10], al
    inc     r10
    jmp     .lu_loop

.lu_done:
    test    r8, r8
    jz      .lu_ok
    mov     [r8], r10

.lu_ok:
    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lu_overflow:
    pop_regs r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_latin1_to_utf8

; -----------------------------------------------------------------------------
; str_latin1_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_latin1_codec_struct:
    dq str_latin1_decode_one
    dq str_latin1_encode_one
    dq _latin1_name
    dq 1                        ; max_bytes
    dq 0x02                     ; ASCII_SUPERSET
    dq 0

section .text

STR_FUNC str_latin1_codec
    lea     rax, [rel _latin1_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_latin1_codec
%endif ; GUARD_LIB_STR_ENCODING_LATIN1_ASM
