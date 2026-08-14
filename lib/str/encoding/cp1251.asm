%ifndef GUARD_LIB_STR_ENCODING_CP1251_ASM
%define GUARD_LIB_STR_ENCODING_CP1251_ASM
; =============================================================================
; str/encoding/cp1251.asm
; Windows-1251 (Cyrillic) ↔ UTF-8 codec.
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
; Windows-1251 is the standard 8-bit encoding for Cyrillic-script languages
; on legacy Windows: Russian, Ukrainian, Bulgarian, Serbian, Macedonian.
;
; Bytes 0x00-0x7F: ASCII
; Bytes 0x80-0xFF: lookup table → Cyrillic block (mostly U+0410-U+044F)
;                  plus some punctuation and the Euro sign.
;
; The Russian alphabet А-Я (0xC0-0xDF) and а-я (0xE0-0xFF) map to a
; contiguous Unicode range, so much of the high range is arithmetic:
;   0xC0-0xFF → U+0410-U+044F  (cp = byte - 0xC0 + 0x0410)
;
; Functions:
;   str_cp1251_decode_one
;   str_cp1251_encode_one
;   str_cp1251_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_cp1251_name: db "windows-1251", 0

; Mapping for bytes 0x80-0xBF → Unicode (0xC0-0xFF is arithmetic).
; 0x0000 = undefined.
align 16
_cp1251_low:
    ; 0x80-0x8F
    dw 0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021
    dw 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F
    ; 0x90-0x9F
    dw 0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014
    dw 0x0000, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F
    ; 0xA0-0xAF
    dw 0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7
    dw 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407
    ; 0xB0-0xBF
    dw 0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7
    dw 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457

section .text

; -----------------------------------------------------------------------------
; str_cp1251_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_cp1251_decode_one

    test    rsi, rsi
    jz      .cd_empty

    movzx   eax, byte [rdi]

    ; ASCII
    cmp     al, 0x80
    jb      .cd_ascii

    ; 0xC0-0xFF: arithmetic → U+0410-U+044F
    cmp     al, 0xC0
    jae     .cd_cyrillic

    ; 0x80-0xBF: table
    sub     eax, 0x80
    lea     r8, [rel _cp1251_low]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .cd_invalid

    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.cd_cyrillic:
    ; byte - 0xC0 + 0x0410
    sub     eax, 0xC0
    add     eax, 0x0410
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.cd_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.cd_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.cd_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_cp1251_decode_one

; -----------------------------------------------------------------------------
; str_cp1251_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_cp1251_encode_one

    test    rdx, rdx
    jz      .ce_nospace

    ; ASCII identity
    cmp     edi, 0x80
    jb      .ce_direct

    ; Cyrillic block U+0410-U+044F → 0xC0-0xFF
    cmp     edi, 0x0410
    jb      .ce_search
    cmp     edi, 0x044F
    ja      .ce_search

    ; arithmetic: cp - 0x0410 + 0xC0
    mov     eax, edi
    sub     eax, 0x0410
    add     eax, 0xC0
    mov     [rsi], al
    mov     rax, 1
    pop     rbp
    ret

.ce_search:
    ; search the low table (0x80-0xBF range)
    lea     r8, [rel _cp1251_low]
    xor     ecx, ecx

.ce_search_loop:
    cmp     ecx, 64
    jae     .ce_unmappable

    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .ce_found

    inc     ecx
    jmp     .ce_search_loop

.ce_found:
    lea     eax, [ecx + 0x80]
    mov     [rsi], al
    mov     rax, 1
    pop     rbp
    ret

.ce_direct:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.ce_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ce_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_cp1251_encode_one

; -----------------------------------------------------------------------------
; str_cp1251_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_cp1251_codec_struct:
    dq str_cp1251_decode_one
    dq str_cp1251_encode_one
    dq _cp1251_name
    dq 1
    dq 0x02
    dq 0

section .text

STR_FUNC str_cp1251_codec
    lea     rax, [rel _cp1251_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_cp1251_codec
%endif ; GUARD_LIB_STR_ENCODING_CP1251_ASM
