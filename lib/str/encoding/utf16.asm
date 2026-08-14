%ifndef GUARD_LIB_STR_ENCODING_UTF16_ASM
%define GUARD_LIB_STR_ENCODING_UTF16_ASM
; =============================================================================
; str/encoding/utf16.asm
; UTF-16 LE/BE ↔ UTF-8 codec (with surrogate pair handling).
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
; UTF-16 encodes each codepoint as one or two 16-bit code units:
;   - BMP (U+0000..U+FFFF, excluding surrogates): one 16-bit unit
;   - Supplementary (U+10000..U+10FFFF): a surrogate pair
;       high surrogate: 0xD800 + ((cp - 0x10000) >> 10)
;       low surrogate:  0xDC00 + ((cp - 0x10000) & 0x3FF)
;
; Byte order:
;   LE (little-endian): low byte first
;   BE (big-endian):    high byte first
;
; Surrogates U+D800..U+DFFF are NOT valid standalone codepoints.
;
; Functions:
;   str_utf16le_decode_one / str_utf16be_decode_one
;   str_utf16le_encode_one / str_utf16be_encode_one
;   str_utf16le_codec / str_utf16be_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_utf16le_name: db "UTF-16LE", 0
_utf16be_name: db "UTF-16BE", 0

section .text

; -----------------------------------------------------------------------------
; str_utf16le_decode_one
;
; Decode one codepoint from a UTF-16LE byte stream.
;
; Signature:
;   int64_t str_utf16le_decode_one(const uint8_t *src, uint64_t src_len,
;                                   uint32_t *out_cp)
;
; Returns: bytes consumed (2 or 4), or negative error.
; -----------------------------------------------------------------------------

STR_FUNC str_utf16le_decode_one

    cmp     rsi, 2
    jb      .ld_short

    ; read first code unit (LE)
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rdi + 1]
    shl     ecx, 8
    or      eax, ecx            ; unit1

    ; high surrogate? 0xD800-0xDBFF
    cmp     eax, 0xD800
    jb      .ld_bmp
    cmp     eax, 0xDBFF
    ja      .ld_check_low

    ; high surrogate — need a low surrogate
    cmp     rsi, 4
    jb      .ld_short

    movzx   r8d, byte [rdi + 2]
    movzx   ecx, byte [rdi + 3]
    shl     ecx, 8
    or      r8d, ecx            ; unit2

    cmp     r8d, 0xDC00
    jb      .ld_invalid
    cmp     r8d, 0xDFFF
    ja      .ld_invalid

    ; combine: cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
    sub     eax, 0xD800
    shl     eax, 10
    sub     r8d, 0xDC00
    add     eax, r8d
    add     eax, 0x10000

    mov     [rdx], eax
    mov     rax, 4
    pop     rbp
    ret

.ld_check_low:
    ; lone low surrogate is invalid
    cmp     eax, 0xDC00
    jb      .ld_bmp
    cmp     eax, 0xDFFF
    jbe     .ld_invalid

.ld_bmp:
    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.ld_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ld_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf16le_decode_one

; -----------------------------------------------------------------------------
; str_utf16be_decode_one  (big-endian variant)
; -----------------------------------------------------------------------------

STR_FUNC str_utf16be_decode_one

    cmp     rsi, 2
    jb      .bd_short

    ; read first code unit (BE)
    movzx   eax, byte [rdi]
    shl     eax, 8
    movzx   ecx, byte [rdi + 1]
    or      eax, ecx            ; unit1

    cmp     eax, 0xD800
    jb      .bd_bmp
    cmp     eax, 0xDBFF
    ja      .bd_check_low

    cmp     rsi, 4
    jb      .bd_short

    movzx   r8d, byte [rdi + 2]
    shl     r8d, 8
    movzx   ecx, byte [rdi + 3]
    or      r8d, ecx

    cmp     r8d, 0xDC00
    jb      .bd_invalid
    cmp     r8d, 0xDFFF
    ja      .bd_invalid

    sub     eax, 0xD800
    shl     eax, 10
    sub     r8d, 0xDC00
    add     eax, r8d
    add     eax, 0x10000

    mov     [rdx], eax
    mov     rax, 4
    pop     rbp
    ret

.bd_check_low:
    cmp     eax, 0xDC00
    jb      .bd_bmp
    cmp     eax, 0xDFFF
    jbe     .bd_invalid

.bd_bmp:
    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.bd_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.bd_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf16be_decode_one

; -----------------------------------------------------------------------------
; str_utf16le_encode_one
;
; Signature:
;   int64_t str_utf16le_encode_one(uint32_t cp, uint8_t *dst, uint64_t dst_cap)
; -----------------------------------------------------------------------------

STR_FUNC str_utf16le_encode_one

    ; reject surrogates and out-of-range
    cmp     edi, 0x10FFFF
    ja      .le_invalid
    cmp     edi, 0xD800
    jb      .le_bmp
    cmp     edi, 0xDFFF
    jbe     .le_invalid

.le_bmp:
    cmp     edi, 0xFFFF
    ja      .le_supp

    ; single unit
    cmp     rdx, 2
    jb      .le_nospace

    mov     [rsi], dil          ; low byte
    mov     eax, edi
    shr     eax, 8
    mov     [rsi + 1], al       ; high byte
    mov     rax, 2
    pop     rbp
    ret

.le_supp:
    cmp     rdx, 4
    jb      .le_nospace

    ; cp -= 0x10000
    sub     edi, 0x10000

    ; high surrogate = 0xD800 + (cp >> 10)
    mov     eax, edi
    shr     eax, 10
    add     eax, 0xD800
    mov     [rsi], al
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi + 1], cl

    ; low surrogate = 0xDC00 + (cp & 0x3FF)
    mov     eax, edi
    and     eax, 0x3FF
    add     eax, 0xDC00
    mov     [rsi + 2], al
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi + 3], cl

    mov     rax, 4
    pop     rbp
    ret

.le_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.le_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf16le_encode_one

; -----------------------------------------------------------------------------
; str_utf16be_encode_one  (big-endian variant)
; -----------------------------------------------------------------------------

STR_FUNC str_utf16be_encode_one

    cmp     edi, 0x10FFFF
    ja      .be_invalid
    cmp     edi, 0xD800
    jb      .be_bmp
    cmp     edi, 0xDFFF
    jbe     .be_invalid

.be_bmp:
    cmp     edi, 0xFFFF
    ja      .be_supp

    cmp     rdx, 2
    jb      .be_nospace

    mov     eax, edi
    shr     eax, 8
    mov     [rsi], al           ; high byte first
    mov     [rsi + 1], dil      ; low byte
    mov     rax, 2
    pop     rbp
    ret

.be_supp:
    cmp     rdx, 4
    jb      .be_nospace

    sub     edi, 0x10000

    mov     eax, edi
    shr     eax, 10
    add     eax, 0xD800
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi], cl
    mov     [rsi + 1], al

    mov     eax, edi
    and     eax, 0x3FF
    add     eax, 0xDC00
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi + 2], cl
    mov     [rsi + 3], al

    mov     rax, 4
    pop     rbp
    ret

.be_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.be_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf16be_encode_one

; -----------------------------------------------------------------------------
; Codec descriptors
; -----------------------------------------------------------------------------

section .rodata
align 8
_utf16le_codec_struct:
    dq str_utf16le_decode_one
    dq str_utf16le_encode_one
    dq _utf16le_name
    dq 4
    dq 0
    dq 0

_utf16be_codec_struct:
    dq str_utf16be_decode_one
    dq str_utf16be_encode_one
    dq _utf16be_name
    dq 4
    dq 0
    dq 0

section .text

STR_FUNC str_utf16le_codec
    lea     rax, [rel _utf16le_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_utf16le_codec

STR_FUNC str_utf16be_codec
    lea     rax, [rel _utf16be_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_utf16be_codec
%endif ; GUARD_LIB_STR_ENCODING_UTF16_ASM
