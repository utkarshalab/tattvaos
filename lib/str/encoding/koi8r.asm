; =============================================================================
; str/encoding/koi8r.asm
; KOI8-R (Russian) ↔ UTF-8 codec.
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
; KOI8-R is the historically dominant Russian encoding on Unix and early
; internet (predates Windows-1251). Unlike CP1251, its Cyrillic letters are
; NOT in alphabetical order — they're arranged so that stripping the high
; bit yields a readable Latin transliteration (a clever design for 7-bit
; gateways).
;
; Bytes 0x00-0x7F: ASCII
; Bytes 0x80-0xFF: box-drawing chars, then Cyrillic via lookup table.
;
; Because of the non-alphabetical layout, a full 128-entry table is needed.
;
; Functions:
;   str_koi8r_decode_one
;   str_koi8r_encode_one
;   str_koi8r_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_koi8r_name: db "KOI8-R", 0

; Mapping for bytes 0x80-0xFF → Unicode codepoint.
; Box drawing + Cyrillic. (128 entries)
align 16
_koi8r_high:
    ; 0x80-0x8F (box drawing / block elements)
    dw 0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524
    dw 0x252C, 0x2534, 0x253C, 0x2580, 0x2584, 0x2588, 0x258C, 0x2590
    ; 0x90-0x9F
    dw 0x2591, 0x2592, 0x2593, 0x2320, 0x25A0, 0x2219, 0x221A, 0x2248
    dw 0x2264, 0x2265, 0x00A0, 0x2321, 0x00B0, 0x00B2, 0x00B7, 0x00F7
    ; 0xA0-0xAF
    dw 0x2550, 0x2551, 0x2552, 0x0451, 0x2553, 0x2554, 0x2555, 0x2556
    dw 0x2557, 0x2558, 0x2559, 0x255A, 0x255B, 0x255C, 0x255D, 0x255E
    ; 0xB0-0xBF
    dw 0x255F, 0x2560, 0x2561, 0x0401, 0x2562, 0x2563, 0x2564, 0x2565
    dw 0x2566, 0x2567, 0x2568, 0x2569, 0x256A, 0x256B, 0x256C, 0x00A9
    ; 0xC0-0xCF (lowercase Cyrillic)
    dw 0x044E, 0x0430, 0x0431, 0x0446, 0x0434, 0x0435, 0x0444, 0x0433
    dw 0x0445, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E
    ; 0xD0-0xDF
    dw 0x043F, 0x044F, 0x0440, 0x0441, 0x0442, 0x0443, 0x0436, 0x0432
    dw 0x044C, 0x044B, 0x0437, 0x0448, 0x044D, 0x0449, 0x0447, 0x044A
    ; 0xE0-0xEF (uppercase Cyrillic)
    dw 0x042E, 0x0410, 0x0411, 0x0426, 0x0414, 0x0415, 0x0424, 0x0413
    dw 0x0425, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E
    ; 0xF0-0xFF
    dw 0x041F, 0x042F, 0x0420, 0x0421, 0x0422, 0x0423, 0x0416, 0x0412
    dw 0x042C, 0x042B, 0x0417, 0x0428, 0x042D, 0x0429, 0x0427, 0x042A

section .text

; -----------------------------------------------------------------------------
; str_koi8r_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_koi8r_decode_one

    test    rsi, rsi
    jz      .kd_empty

    movzx   eax, byte [rdi]

    cmp     al, 0x80
    jb      .kd_ascii

    sub     eax, 0x80
    lea     r8, [rel _koi8r_high]
    movzx   eax, word [r8 + rax * 2]
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.kd_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.kd_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_koi8r_decode_one

; -----------------------------------------------------------------------------
; str_koi8r_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_koi8r_encode_one

    test    rdx, rdx
    jz      .ke_nospace

    cmp     edi, 0x80
    jb      .ke_direct

    ; search high table
    lea     r8, [rel _koi8r_high]
    xor     ecx, ecx

.ke_search:
    cmp     ecx, 128
    jae     .ke_unmappable

    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .ke_found

    inc     ecx
    jmp     .ke_search

.ke_found:
    lea     eax, [ecx + 0x80]
    mov     [rsi], al
    mov     rax, 1
    pop     rbp
    ret

.ke_direct:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.ke_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ke_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_koi8r_encode_one

; -----------------------------------------------------------------------------
; str_koi8r_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_koi8r_codec_struct:
    dq str_koi8r_decode_one
    dq str_koi8r_encode_one
    dq _koi8r_name
    dq 1
    dq 0x02
    dq 0

section .text

STR_FUNC str_koi8r_codec
    lea     rax, [rel _koi8r_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_koi8r_codec