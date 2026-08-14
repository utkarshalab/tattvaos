%ifndef GUARD_LIB_STR_ENCODING_LATIN2_ASM
%define GUARD_LIB_STR_ENCODING_LATIN2_ASM
; =============================================================================
; str/encoding/latin2.asm
; ISO-8859-2 (Latin-2, Central European) ↔ UTF-8 codec.
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
; ISO-8859-2 covers Central/Eastern European Latin-script languages:
; Czech, Polish, Slovak, Hungarian, Croatian, Slovenian, Romanian.
;
; Bytes 0x00-0x7F = ASCII (identical to Unicode).
; Bytes 0xA0-0xFF map to specific codepoints via a lookup table — these
; do NOT equal their byte value (unlike Latin-1).
;
; Example: byte 0xB1 → U+0105 (ą, Latin small a with ogonek)
;
; The decode table maps high byte → codepoint.
; The encode direction uses a reverse search (or a hash for speed).
;
; Functions:
;   str_latin2_decode_one
;   str_latin2_encode_one
;   str_latin2_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_latin2_name: db "ISO-8859-2", 0

; -----------------------------------------------------------------------------
; Decode table for high bytes 0xA0-0xFF → Unicode codepoint.
; (96 entries, indexed by byte - 0xA0)
; Values from the official ISO-8859-2 mapping.
; -----------------------------------------------------------------------------
align 16
_latin2_high:
    ; 0xA0-0xAF
    dw 0x00A0, 0x0104, 0x02D8, 0x0141, 0x00A4, 0x013D, 0x015A, 0x00A7
    dw 0x00A8, 0x0160, 0x015E, 0x0164, 0x0179, 0x00AD, 0x017D, 0x017B
    ; 0xB0-0xBF
    dw 0x00B0, 0x0105, 0x02DB, 0x0142, 0x00B4, 0x013E, 0x015B, 0x02C7
    dw 0x00B8, 0x0161, 0x015F, 0x0165, 0x017A, 0x02DD, 0x017E, 0x017C
    ; 0xC0-0xCF
    dw 0x0154, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x0139, 0x0106, 0x00C7
    dw 0x010C, 0x00C9, 0x0118, 0x00CB, 0x011A, 0x00CD, 0x00CE, 0x010E
    ; 0xD0-0xDF
    dw 0x0110, 0x0143, 0x0147, 0x00D3, 0x00D4, 0x0150, 0x00D6, 0x00D7
    dw 0x0158, 0x016E, 0x00DA, 0x0170, 0x00DC, 0x00DD, 0x0162, 0x00DF
    ; 0xE0-0xEF
    dw 0x0155, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x013A, 0x0107, 0x00E7
    dw 0x010D, 0x00E9, 0x0119, 0x00EB, 0x011B, 0x00ED, 0x00EE, 0x010F
    ; 0xF0-0xFF
    dw 0x0111, 0x0144, 0x0148, 0x00F3, 0x00F4, 0x0151, 0x00F6, 0x00F7
    dw 0x0159, 0x016F, 0x00FA, 0x0171, 0x00FC, 0x00FD, 0x0163, 0x02D9

section .text

; -----------------------------------------------------------------------------
; str_latin2_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_latin2_decode_one

    test    rsi, rsi
    jz      .l2d_empty

    movzx   eax, byte [rdi]

    ; ASCII range: identity
    cmp     al, 0x80
    jb      .l2d_ascii

    ; high range: table lookup
    cmp     al, 0xA0
    jb      .l2d_c1             ; 0x80-0x9F are C1 controls

    sub     eax, 0xA0
    lea     r8, [rel _latin2_high]
    movzx   eax, word [r8 + rax * 2]
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.l2d_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.l2d_c1:
    ; 0x80-0x9F → C1 control codepoints (identity)
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.l2d_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_latin2_decode_one

; -----------------------------------------------------------------------------
; str_latin2_encode_one
;
; Encode a codepoint to ISO-8859-2.
; ASCII (< 0x80) and C1 (0x80-0x9F) are identity. Others need reverse
; table search.
; -----------------------------------------------------------------------------

STR_FUNC str_latin2_encode_one

    test    rdx, rdx
    jz      .l2e_nospace

    ; ASCII identity
    cmp     edi, 0x80
    jb      .l2e_direct

    ; C1 controls identity
    cmp     edi, 0xA0
    jb      .l2e_direct

    ; search the high table for matching codepoint
    lea     r8, [rel _latin2_high]
    xor     ecx, ecx

.l2e_search:
    cmp     ecx, 96
    jae     .l2e_unmappable

    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .l2e_found

    inc     ecx
    jmp     .l2e_search

.l2e_found:
    lea     eax, [ecx + 0xA0]
    mov     [rsi], al
    mov     rax, 1
    pop     rbp
    ret

.l2e_direct:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.l2e_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.l2e_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_latin2_encode_one

; -----------------------------------------------------------------------------
; str_latin2_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_latin2_codec_struct:
    dq str_latin2_decode_one
    dq str_latin2_encode_one
    dq _latin2_name
    dq 1
    dq 0x02
    dq 0

section .text

STR_FUNC str_latin2_codec
    lea     rax, [rel _latin2_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_latin2_codec
%endif ; GUARD_LIB_STR_ENCODING_LATIN2_ASM
