%ifndef GUARD_LIB_STR_ENCODING_CP1252_ASM
%define GUARD_LIB_STR_ENCODING_CP1252_ASM
; =============================================================================
; str/encoding/cp1252.asm
; Windows-1252 (Western European) ↔ UTF-8 codec.
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
; Windows-1252 is a superset of ISO-8859-1. It is identical to Latin-1
; EXCEPT for the range 0x80-0x9F, where Latin-1 has C1 control characters
; but CP1252 places useful printable characters:
;   "smart quotes", em/en dashes, the Euro sign, bullet, ellipsis, etc.
;
; This is the de-facto default encoding for legacy Windows text files and
; a huge amount of web content mislabeled as ISO-8859-1.
;
; Bytes 0x00-0x7F:  ASCII (identity)
; Bytes 0x80-0x9F:  special table (smart quotes, Euro, dashes...)
; Bytes 0xA0-0xFF:  identical to Latin-1 (= Unicode codepoint)
;
; Five bytes in 0x80-0x9F are undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D).
;
; Functions:
;   str_cp1252_decode_one
;   str_cp1252_encode_one
;   str_cp1252_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_cp1252_name: db "windows-1252", 0

; Mapping for bytes 0x80-0x9F → Unicode codepoint.
; 0x0000 marks an undefined byte.
align 16
_cp1252_special:
    ; 0x80-0x8F
    dw 0x20AC, 0x0000, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021
    dw 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x0000, 0x017D, 0x0000
    ; 0x90-0x9F
    dw 0x0000, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014
    dw 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x0000, 0x017E, 0x0178

section .text

; -----------------------------------------------------------------------------
; str_cp1252_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_cp1252_decode_one

    test    rsi, rsi
    jz      .cd_empty

    movzx   eax, byte [rdi]

    ; 0x80-0x9F: special table
    cmp     al, 0x80
    jb      .cd_identity
    cmp     al, 0x9F
    ja      .cd_identity

    ; table lookup
    sub     eax, 0x80
    lea     r8, [rel _cp1252_special]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .cd_invalid         ; undefined byte

    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.cd_identity:
    ; ASCII (< 0x80) and 0xA0-0xFF map to codepoint = byte
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

STR_ENDFUNC str_cp1252_decode_one

; -----------------------------------------------------------------------------
; str_cp1252_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_cp1252_encode_one

    test    rdx, rdx
    jz      .ce_nospace

    ; ASCII identity
    cmp     edi, 0x80
    jb      .ce_direct

    ; 0xA0-0xFF identity (Latin-1 range)
    cmp     edi, 0xA0
    jb      .ce_search          ; 0x80-0x9F codepoints need search
    cmp     edi, 0xFF
    jbe     .ce_direct

.ce_search:
    ; search special table for codepoints mapping to 0x80-0x9F
    lea     r8, [rel _cp1252_special]
    xor     ecx, ecx

.ce_search_loop:
    cmp     ecx, 32
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

STR_ENDFUNC str_cp1252_encode_one

; -----------------------------------------------------------------------------
; str_cp1252_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_cp1252_codec_struct:
    dq str_cp1252_decode_one
    dq str_cp1252_encode_one
    dq _cp1252_name
    dq 1
    dq 0x02
    dq 0

section .text

STR_FUNC str_cp1252_codec
    lea     rax, [rel _cp1252_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_cp1252_codec
%endif ; GUARD_LIB_STR_ENCODING_CP1252_ASM
