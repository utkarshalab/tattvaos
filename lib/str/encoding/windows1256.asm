%ifndef GUARD_LIB_STR_ENCODING_WINDOWS1256_ASM
%define GUARD_LIB_STR_ENCODING_WINDOWS1256_ASM
; =============================================================================
; str/encoding/windows1256.asm
; Windows-1256 (Arabic) codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/encode.asm   (str_utf8_encode_unchecked)
;
; -----------------------------------------------------------------------------
; Windows-1256 is the standard Arabic codepage on Windows.
; It covers Arabic letters, Persian additions, and French accented chars
; (for North African French/Arabic bilingual text).
;
; 0x00-0x7F = ASCII
; 0x80-0xFF = Arabic letters + some Latin + typographic symbols
;
; Functions:
;   str_cp1256_decode_one  — decode one byte → codepoint
;   str_cp1256_to_utf8     — bulk CP1256 → UTF-8
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
align 16

; High-half mapping: 0x80-0xFF → Unicode
_cp1256_to_unicode:
    ; 0x80-0x8F
    dw 0x20AC   ; 0x80  €
    dw 0x067E   ; 0x81  پ  (Persian pe)
    dw 0x201A   ; 0x82  ‚
    dw 0x0192   ; 0x83  ƒ
    dw 0x201E   ; 0x84  „
    dw 0x2026   ; 0x85  …
    dw 0x2020   ; 0x86  †
    dw 0x2021   ; 0x87  ‡
    dw 0x02C6   ; 0x88  ˆ
    dw 0x2030   ; 0x89  ‰
    dw 0x0679   ; 0x8A  ٹ  (Urdu tte)
    dw 0x2039   ; 0x8B  ‹
    dw 0x0152   ; 0x8C  Œ
    dw 0x0686   ; 0x8D  چ  (Persian che)
    dw 0x0698   ; 0x8E  ژ  (Persian zhe)
    dw 0x0688   ; 0x8F  ڈ  (Urdu dal)
    ; 0x90-0x9F
    dw 0x06AF   ; 0x90  گ  (Persian gaf)
    dw 0x2018   ; 0x91  '
    dw 0x2019   ; 0x92  '
    dw 0x201C   ; 0x93  "
    dw 0x201D   ; 0x94  "
    dw 0x2022   ; 0x95  •
    dw 0x2013   ; 0x96  –
    dw 0x2014   ; 0x97  —
    dw 0x06A9   ; 0x98  ک  (Persian kaf)
    dw 0x2122   ; 0x99  ™
    dw 0x0691   ; 0x9A  ڑ  (Urdu rre)
    dw 0x203A   ; 0x9B  ›
    dw 0x0153   ; 0x9C  œ
    dw 0x200C   ; 0x9D  ZWNJ
    dw 0x200D   ; 0x9E  ZWJ
    dw 0x06BA   ; 0x9F  ں  (Urdu noon ghunna)
    ; 0xA0-0xAF
    dw 0x00A0   ; 0xA0  NBSP
    dw 0x060C   ; 0xA1  ،  Arabic comma
    dw 0x00A2   ; 0xA2  ¢
    dw 0x00A3   ; 0xA3  £
    dw 0x00A4   ; 0xA4  ¤
    dw 0x00A5   ; 0xA5  ¥
    dw 0x00A6   ; 0xA6  ¦
    dw 0x00A7   ; 0xA7  §
    dw 0x00A8   ; 0xA8  ¨
    dw 0x00A9   ; 0xA9  ©
    dw 0x06BE   ; 0xAA  ھ  (Urdu heh doachashmee)
    dw 0x00AB   ; 0xAB  «
    dw 0x00AC   ; 0xAC  ¬
    dw 0x00AD   ; 0xAD  SHY
    dw 0x00AE   ; 0xAE  ®
    dw 0x00AF   ; 0xAF  ¯
    ; 0xB0-0xBF
    dw 0x00B0   ; 0xB0  °
    dw 0x00B1   ; 0xB1  ±
    dw 0x00B2   ; 0xB2  ²
    dw 0x00B3   ; 0xB3  ³
    dw 0x00B4   ; 0xB4  ´
    dw 0x00B5   ; 0xB5  µ
    dw 0x00B6   ; 0xB6  ¶
    dw 0x00B7   ; 0xB7  ·
    dw 0x00B8   ; 0xB8  ¸
    dw 0x00B9   ; 0xB9  ¹
    dw 0x061B   ; 0xBA  ؛  Arabic semicolon
    dw 0x00BB   ; 0xBB  »
    dw 0x00BC   ; 0xBC  ¼
    dw 0x00BD   ; 0xBD  ½
    dw 0x00BE   ; 0xBE  ¾
    dw 0x061F   ; 0xBF  ؟  Arabic question mark
    ; 0xC0-0xCF
    dw 0x06C1   ; 0xC0  ہ  (Urdu heh goal)
    dw 0x0621   ; 0xC1  ء  hamza
    dw 0x0622   ; 0xC2  آ  alef madda
    dw 0x0623   ; 0xC3  أ  alef hamza above
    dw 0x0624   ; 0xC4  ؤ  waw hamza
    dw 0x0625   ; 0xC5  إ  alef hamza below
    dw 0x0626   ; 0xC6  ئ  yeh hamza
    dw 0x0627   ; 0xC7  ا  alef
    dw 0x0628   ; 0xC8  ب  beh
    dw 0x0629   ; 0xC9  ة  teh marbuta
    dw 0x062A   ; 0xCA  ت  teh
    dw 0x062B   ; 0xCB  ث  theh
    dw 0x062C   ; 0xCC  ج  jeem
    dw 0x062D   ; 0xCD  ح  hah
    dw 0x062E   ; 0xCE  خ  khah
    dw 0x062F   ; 0xCF  د  dal
    ; 0xD0-0xDF
    dw 0x0630   ; 0xD0  ذ  thal
    dw 0x0631   ; 0xD1  ر  reh
    dw 0x0632   ; 0xD2  ز  zain
    dw 0x0633   ; 0xD3  س  seen
    dw 0x0634   ; 0xD4  ش  sheen
    dw 0x0635   ; 0xD5  ص  sad
    dw 0x0636   ; 0xD6  ض  dad
    dw 0x00D7   ; 0xD7  ×
    dw 0x0637   ; 0xD8  ط  tah
    dw 0x0638   ; 0xD9  ظ  zah
    dw 0x0639   ; 0xDA  ع  ain
    dw 0x063A   ; 0xDB  غ  ghain
    dw 0x0640   ; 0xDC  ـ  tatweel
    dw 0x0641   ; 0xDD  ف  feh
    dw 0x0642   ; 0xDE  ق  qaf
    dw 0x0643   ; 0xDF  ك  kaf
    ; 0xE0-0xEF
    dw 0x00E0   ; 0xE0  à
    dw 0x0644   ; 0xE1  ل  lam
    dw 0x00E2   ; 0xE2  â
    dw 0x0645   ; 0xE3  م  meem
    dw 0x0646   ; 0xE4  ن  noon
    dw 0x0647   ; 0xE5  ه  heh
    dw 0x0648   ; 0xE6  و  waw
    dw 0x00E7   ; 0xE7  ç
    dw 0x00E8   ; 0xE8  è
    dw 0x00E9   ; 0xE9  é
    dw 0x00EA   ; 0xEA  ê
    dw 0x00EB   ; 0xEB  ë
    dw 0x0649   ; 0xEC  ى  alef maksura
    dw 0x064A   ; 0xED  ي  yeh
    dw 0x00EE   ; 0xEE  î
    dw 0x00EF   ; 0xEF  ï
    ; 0xF0-0xFF
    dw 0x064B   ; 0xF0  ً  fathatan
    dw 0x064C   ; 0xF1  ٌ  dammatan
    dw 0x064D   ; 0xF2  ٍ  kasratan
    dw 0x064E   ; 0xF3  َ  fatha
    dw 0x00F4   ; 0xF4  ô
    dw 0x064F   ; 0xF5  ُ  damma
    dw 0x0650   ; 0xF6  ِ  kasra
    dw 0x00F7   ; 0xF7  ÷
    dw 0x0651   ; 0xF8  ّ  shadda
    dw 0x00F9   ; 0xF9  ù
    dw 0x0652   ; 0xFA  ْ  sukun
    dw 0x00FB   ; 0xFB  û
    dw 0x00FC   ; 0xFC  ü
    dw 0x200E   ; 0xFD  LRM
    dw 0x200F   ; 0xFE  RLM
    dw 0x06D2   ; 0xFF  ے  (Urdu yeh barree)

section .text

; -----------------------------------------------------------------------------
; str_cp1256_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_cp1256_decode_one

    guard_null rsi, STR_ERR_NULL

    movzx   eax, dil

    cmp     al, 0x80
    jb      .d56_ascii

    movzx   ecx, al
    sub     ecx, 0x80
    lea     r8, [rel _cp1256_to_unicode]
    movzx   eax, word [r8 + rcx * 2]

    test    eax, eax
    jz      .d56_undef

    mov     [rsi], eax
    xor     eax, eax
    pop     rbp
    ret

.d56_ascii:
    mov     [rsi], eax
    xor     eax, eax
    pop     rbp
    ret

.d56_undef:
    mov     dword [rsi], 0xFFFD
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret

STR_ENDFUNC str_cp1256_decode_one

; -----------------------------------------------------------------------------
; str_cp1256_to_utf8 — bulk decode (same pattern as cp1250)
; -----------------------------------------------------------------------------

STR_FUNC str_cp1256_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8

    xor     r9, r9
    xor     r10, r10

.t56_loop:
    cmp     r9, r12
    jae     .t56_done

    movzx   edi, byte [rbx + r9]
    inc     r9

    sub     rsp, 8
    and     rsp, -8
    mov     rsi, rsp
    push    r9
    push    r10
    call    str_cp1256_decode_one
    pop     r10
    pop     r9
    mov     edi, [rsp]
    add     rsp, 8

    lea     rax, [r10 + 4]
    cmp     rax, r14
    ja      .t56_overflow

    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    add     r10, rax
    jmp     .t56_loop

.t56_done:
    test    r15, r15
    jz      .t56_ok
    mov     [r15], r10

.t56_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.t56_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_cp1256_to_utf8
%endif ; GUARD_LIB_STR_ENCODING_WINDOWS1256_ASM
