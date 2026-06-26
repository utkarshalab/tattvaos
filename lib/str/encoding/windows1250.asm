; =============================================================================
; str/encoding/windows1250.asm
; Windows-1250 (Central European) codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/encode.asm   (str_utf8_encode_unchecked)
;   utf8/decode.asm   (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; Windows-1250 covers Central/Eastern European languages using Latin script:
;   Polish, Czech, Slovak, Hungarian, Slovenian, Croatian, Romanian, Albanian
;
; 0x00-0x7F = ASCII (identical)
; 0x80-0xFF = 128 entries mapped via the table below
;
; The 0x80-0x9F range is the key difference from ISO-8859-2:
;   0x80 = €  (U+20AC)
;   0x8A = Š  (U+0160)
;   0x8E = Ž  (U+017D)
;   0x9A = š  (U+0161)
;   0x9E = ž  (U+017E)
;   etc.
;
; Functions:
;   str_cp1250_decode_one  — decode one byte → codepoint
;   str_cp1250_encode_one  — encode one codepoint → byte
;   str_cp1250_to_utf8     — bulk CP1250 → UTF-8
;   str_cp1250_from_utf8   — bulk UTF-8 → CP1250
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_encode_unchecked
extern str_utf8_decode_unchecked

section .rodata
align 16

; High-half mapping table: byte 0x80-0xFF → Unicode codepoint
; 128 entries × 2 bytes = 256 bytes
; 0x0000 = undefined/unmapped
_cp1250_to_unicode:
    ; 0x80-0x8F
    dw 0x20AC   ; 0x80  €
    dw 0x0000   ; 0x81  undefined
    dw 0x201A   ; 0x82  ‚
    dw 0x0000   ; 0x83  undefined
    dw 0x201E   ; 0x84  „
    dw 0x2026   ; 0x85  …
    dw 0x2020   ; 0x86  †
    dw 0x2021   ; 0x87  ‡
    dw 0x0000   ; 0x88  undefined
    dw 0x2030   ; 0x89  ‰
    dw 0x0160   ; 0x8A  Š
    dw 0x2039   ; 0x8B  ‹
    dw 0x015A   ; 0x8C  Ś
    dw 0x0164   ; 0x8D  Ť
    dw 0x017D   ; 0x8E  Ž
    dw 0x0179   ; 0x8F  Ź
    ; 0x90-0x9F
    dw 0x0000   ; 0x90  undefined
    dw 0x2018   ; 0x91  '
    dw 0x2019   ; 0x92  '
    dw 0x201C   ; 0x93  "
    dw 0x201D   ; 0x94  "
    dw 0x2022   ; 0x95  •
    dw 0x2013   ; 0x96  –
    dw 0x2014   ; 0x97  —
    dw 0x0000   ; 0x98  undefined
    dw 0x2122   ; 0x99  ™
    dw 0x0161   ; 0x9A  š
    dw 0x203A   ; 0x9B  ›
    dw 0x015B   ; 0x9C  ś
    dw 0x0165   ; 0x9D  ť
    dw 0x017E   ; 0x9E  ž
    dw 0x017A   ; 0x9F  ź
    ; 0xA0-0xAF
    dw 0x00A0   ; 0xA0  NBSP
    dw 0x02C7   ; 0xA1  ˇ  caron
    dw 0x02D8   ; 0xA2  ˘  breve
    dw 0x0141   ; 0xA3  Ł
    dw 0x00A4   ; 0xA4  ¤
    dw 0x0104   ; 0xA5  Ą
    dw 0x00A6   ; 0xA6  ¦
    dw 0x00A7   ; 0xA7  §
    dw 0x00A8   ; 0xA8  ¨
    dw 0x00A9   ; 0xA9  ©
    dw 0x015E   ; 0xAA  Ş
    dw 0x00AB   ; 0xAB  «
    dw 0x00AC   ; 0xAC  ¬
    dw 0x00AD   ; 0xAD  SHY
    dw 0x00AE   ; 0xAE  ®
    dw 0x017B   ; 0xAF  Ż
    ; 0xB0-0xBF
    dw 0x00B0   ; 0xB0  °
    dw 0x00B1   ; 0xB1  ±
    dw 0x02DB   ; 0xB2  ˛  ogonek
    dw 0x0142   ; 0xB3  ł
    dw 0x00B4   ; 0xB4  ´
    dw 0x00B5   ; 0xB5  µ
    dw 0x00B6   ; 0xB6  ¶
    dw 0x00B7   ; 0xB7  ·
    dw 0x00B8   ; 0xB8  ¸
    dw 0x0105   ; 0xB9  ą
    dw 0x015F   ; 0xBA  ş
    dw 0x00BB   ; 0xBB  »
    dw 0x013D   ; 0xBC  Ľ
    dw 0x02DD   ; 0xBD  ˝  double acute
    dw 0x013E   ; 0xBE  ľ
    dw 0x017C   ; 0xBF  ż
    ; 0xC0-0xCF
    dw 0x0154   ; 0xC0  Ŕ
    dw 0x00C1   ; 0xC1  Á
    dw 0x00C2   ; 0xC2  Â
    dw 0x0102   ; 0xC3  Ă
    dw 0x00C4   ; 0xC4  Ä
    dw 0x0139   ; 0xC5  Ĺ
    dw 0x0106   ; 0xC6  Ć
    dw 0x00C7   ; 0xC7  Ç
    dw 0x010C   ; 0xC8  Č
    dw 0x00C9   ; 0xC9  É
    dw 0x0118   ; 0xCA  Ę
    dw 0x00CB   ; 0xCB  Ë
    dw 0x011A   ; 0xCC  Ě
    dw 0x00CD   ; 0xCD  Í
    dw 0x00CE   ; 0xCE  Î
    dw 0x010E   ; 0xCF  Ď
    ; 0xD0-0xDF
    dw 0x0110   ; 0xD0  Đ
    dw 0x0143   ; 0xD1  Ń
    dw 0x0147   ; 0xD2  Ň
    dw 0x00D3   ; 0xD3  Ó
    dw 0x00D4   ; 0xD4  Ô
    dw 0x0150   ; 0xD5  Ő
    dw 0x00D6   ; 0xD6  Ö
    dw 0x00D7   ; 0xD7  ×
    dw 0x0158   ; 0xD8  Ř
    dw 0x016E   ; 0xD9  Ů
    dw 0x00DA   ; 0xDA  Ú
    dw 0x0170   ; 0xDB  Ű
    dw 0x00DC   ; 0xDC  Ü
    dw 0x00DD   ; 0xDD  Ý
    dw 0x0162   ; 0xDE  Ţ
    dw 0x00DF   ; 0xDF  ß
    ; 0xE0-0xEF
    dw 0x0155   ; 0xE0  ŕ
    dw 0x00E1   ; 0xE1  á
    dw 0x00E2   ; 0xE2  â
    dw 0x0103   ; 0xE3  ă
    dw 0x00E4   ; 0xE4  ä
    dw 0x013A   ; 0xE5  ĺ
    dw 0x0107   ; 0xE6  ć
    dw 0x00E7   ; 0xE7  ç
    dw 0x010D   ; 0xE8  č
    dw 0x00E9   ; 0xE9  é
    dw 0x0119   ; 0xEA  ę
    dw 0x00EB   ; 0xEB  ë
    dw 0x011B   ; 0xEC  ě
    dw 0x00ED   ; 0xED  í
    dw 0x00EE   ; 0xEE  î
    dw 0x010F   ; 0xEF  ď
    ; 0xF0-0xFF
    dw 0x0111   ; 0xF0  đ
    dw 0x0144   ; 0xF1  ń
    dw 0x0148   ; 0xF2  ň
    dw 0x00F3   ; 0xF3  ó
    dw 0x00F4   ; 0xF4  ô
    dw 0x0151   ; 0xF5  ő
    dw 0x00F6   ; 0xF6  ö
    dw 0x00F7   ; 0xF7  ÷
    dw 0x0159   ; 0xF8  ř
    dw 0x016F   ; 0xF9  ů
    dw 0x00FA   ; 0xFA  ú
    dw 0x0171   ; 0xFB  ű
    dw 0x00FC   ; 0xFC  ü
    dw 0x00FD   ; 0xFD  ý
    dw 0x0163   ; 0xFE  ţ
    dw 0x02D9   ; 0xFF  ˙  dot above

section .text

; -----------------------------------------------------------------------------
; str_cp1250_decode_one
;
; Decode one CP1250 byte to Unicode codepoint.
;
; Signature:
;   int64_t str_cp1250_decode_one(uint8_t byte, uint32_t *out_cp)
; -----------------------------------------------------------------------------

STR_FUNC str_cp1250_decode_one

    guard_null rsi, STR_ERR_NULL

    movzx   eax, dil

    ; ASCII pass-through
    cmp     al, 0x80
    jb      .d50_ascii

    ; high half: table lookup
    movzx   ecx, al
    sub     ecx, 0x80
    lea     r8, [rel _cp1250_to_unicode]
    movzx   eax, word [r8 + rcx * 2]

    test    eax, eax
    jz      .d50_undef

    mov     [rsi], eax
    xor     eax, eax
    pop     rbp
    ret

.d50_ascii:
    mov     [rsi], eax
    xor     eax, eax
    pop     rbp
    ret

.d50_undef:
    mov     dword [rsi], 0xFFFD
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret

STR_ENDFUNC str_cp1250_decode_one

; -----------------------------------------------------------------------------
; str_cp1250_to_utf8
;
; Bulk convert CP1250 → UTF-8.
;
; Signature:
;   int64_t str_cp1250_to_utf8(const uint8_t *src, uint64_t src_len,
;                               uint8_t *dst, uint64_t dst_cap,
;                               uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_cp1250_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8

    xor     r9, r9              ; src offset
    xor     r10, r10            ; dst offset

.t50_loop:
    cmp     r9, r12
    jae     .t50_done

    movzx   edi, byte [rbx + r9]
    inc     r9

    ; decode
    sub     rsp, 8
    and     rsp, -8
    mov     rsi, rsp
    push    r9
    push    r10
    call    str_cp1250_decode_one
    pop     r10
    pop     r9
    mov     edi, [rsp]
    add     rsp, 8

    ; encode to UTF-8
    lea     rax, [r10 + 4]
    cmp     rax, r14
    ja      .t50_overflow

    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    add     r10, rax
    jmp     .t50_loop

.t50_done:
    test    r15, r15
    jz      .t50_ok
    mov     [r15], r10

.t50_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.t50_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_cp1250_to_utf8