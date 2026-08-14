%ifndef GUARD_LIB_STR_ENCODING_SHIFTJIS_ASM
%define GUARD_LIB_STR_ENCODING_SHIFTJIS_ASM
; =============================================================================
; str/encoding/shiftjis.asm
; Shift-JIS (Japanese) ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm                  (EncCodec struct)
;   encoding/tables/shiftjis_table.s     (generated mapping)
;
; -----------------------------------------------------------------------------
; Shift-JIS (SJIS) is the classic Japanese encoding for Windows and many
; legacy systems.
;
; Structure:
;   - 0x00-0x7F:   ASCII (with ¥ at 0x5C and ‾ at 0x7E in strict JIS X 0201)
;   - 0xA1-0xDF:   half-width Katakana (single byte → U+FF61..U+FF9F)
;   - Double byte: lead 0x81-0x9F or 0xE0-0xFC,
;                  trail 0x40-0x7E or 0x80-0xFC
;
; The double-byte plane maps to JIS X 0208 kanji/kana via a table.
; Half-width katakana is a simple arithmetic offset.
;
; Functions:
;   str_shiftjis_decode_one
;   str_shiftjis_encode_one
;   str_shiftjis_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_shiftjis_name: db "Shift_JIS", 0




; double-byte trail span: 0x40-0x7E (63) + 0x80-0xFC (125) = 188
SJIS_TRAIL_SPAN equ 188

section .text

; trail byte → 0..187 index, or -1
_sjis_trail_index:
    cmp     al, 0x40
    jb      .sti_bad
    cmp     al, 0x7E
    jbe     .sti_low
    cmp     al, 0x80
    jb      .sti_bad            ; 0x7F invalid
    cmp     al, 0xFC
    ja      .sti_bad
    sub     eax, 0x80
    add     eax, 63
    ret
.sti_low:
    sub     eax, 0x40
    ret
.sti_bad:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; str_shiftjis_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_shiftjis_decode_one

    test    rsi, rsi
    jz      .sd_empty

    movzx   eax, byte [rdi]

    ; ASCII
    cmp     al, 0x80
    jb      .sd_ascii

    ; half-width katakana 0xA1-0xDF
    cmp     al, 0xA1
    jb      .sd_check_lead
    cmp     al, 0xDF
    jbe     .sd_katakana

.sd_check_lead:
    ; double-byte lead: 0x81-0x9F or 0xE0-0xFC
    cmp     al, 0x81
    jb      .sd_invalid
    cmp     al, 0x9F
    jbe     .sd_double
    cmp     al, 0xE0
    jb      .sd_invalid
    cmp     al, 0xFC
    ja      .sd_invalid

.sd_double:
    cmp     rsi, 2
    jb      .sd_short

    push    rax                 ; lead
    movzx   eax, byte [rdi + 1]
    call    _sjis_trail_index
    mov     ecx, eax
    pop     rax

    cmp     ecx, -1
    je      .sd_invalid

    ; index: map lead to a contiguous range
    ; leads 0x81-0x9F → 0..30, leads 0xE0-0xFC → 31..59
    cmp     al, 0x9F
    ja      .sd_lead_high
    sub     eax, 0x81
    jmp     .sd_lead_done
.sd_lead_high:
    sub     eax, 0xE0
    add     eax, 31
.sd_lead_done:
    imul    eax, eax, SJIS_TRAIL_SPAN
    add     eax, ecx

    lea     r8, [rel _sjis_to_unicode]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .sd_invalid

    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.sd_katakana:
    ; half-width katakana: byte 0xA1-0xDF → U+FF61-U+FF9F
    sub     eax, 0xA1
    add     eax, 0xFF61
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.sd_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.sd_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.sd_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

.sd_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_shiftjis_decode_one

; -----------------------------------------------------------------------------
; str_shiftjis_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_shiftjis_encode_one

    test    rdx, rdx
    jz      .se_nospace

    cmp     edi, 0x7F
    jbe     .se_ascii

    ; half-width katakana U+FF61-U+FF9F → 1 byte
    cmp     edi, 0xFF61
    jb      .se_double
    cmp     edi, 0xFF9F
    ja      .se_double
    mov     eax, edi
    sub     eax, 0xFF61
    add     eax, 0xA1
    mov     [rsi], al
    mov     rax, 1
    pop     rbp
    ret

.se_double:
    ; binary search reverse table
    lea     r8, [rel _sjis_from_unicode_keys]
    lea     r9, [rel _sjis_from_unicode_vals]
    mov     r10, [rel _sjis_from_unicode_count]
    xor     r11, r11

.se_search:
    cmp     r11, r10
    jae     .se_unmappable
    mov     rcx, r11
    add     rcx, r10
    shr     rcx, 1
    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .se_found
    jb      .se_right
    mov     r10, rcx
    jmp     .se_search
.se_right:
    lea     r11, [rcx + 1]
    jmp     .se_search

.se_found:
    cmp     rdx, 2
    jb      .se_nospace
    movzx   eax, word [r9 + rcx * 2]
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi], cl
    mov     [rsi + 1], al
    mov     rax, 2
    pop     rbp
    ret

.se_ascii:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.se_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.se_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_shiftjis_encode_one

; -----------------------------------------------------------------------------
; str_shiftjis_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_shiftjis_codec_struct:
    dq str_shiftjis_decode_one
    dq str_shiftjis_encode_one
    dq _shiftjis_name
    dq 2
    dq 0x02
    dq 0

section .text

STR_FUNC str_shiftjis_codec
    lea     rax, [rel _shiftjis_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_shiftjis_codec
%endif ; GUARD_LIB_STR_ENCODING_SHIFTJIS_ASM
