%ifndef GUARD_LIB_STR_UNICODE_VERTICAL_ASM
%define GUARD_LIB_STR_UNICODE_VERTICAL_ASM
; =============================================================================
; str/unicode/vertical.asm
; Vertical text orientation (VerticalOrientation.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: VerticalOrientation.txt
;
; -----------------------------------------------------------------------------
; When rendering CJK text vertically (top-to-bottom), each glyph has
; a preferred orientation:
;   U  — Upright       (CJK ideographs, fullwidth forms)
;   R  — Rotated 90°   (Latin letters, digits — turn sideways)
;   Tu — Transliterate Upright (small set)
;   Tr — Transliterate Rotated
;
; Functions:
;   str_cp_vertical_orientation  — get orientation class
;   str_cp_is_vertical_upright   — would be displayed upright in vertical text
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

VERT_R   equ 0      ; Rotated (Latin, digits → turn sideways)
VERT_U   equ 1      ; Upright (CJK, fullwidth → keep upright)
VERT_Tu  equ 2      ; Transliterate upright
VERT_Tr  equ 3      ; Transliterate rotated

section .text

STR_FUNC str_cp_vertical_orientation

    ; ASCII → Rotated
    cmp     edi, 0x80
    jb      .vo_r

    ; CJK Ideographs → Upright
    cmp     edi, 0x4E00
    jb      .vo_chk_kana
    cmp     edi, 0x9FFF
    jbe     .vo_u
    cmp     edi, 0x3400
    jb      .vo_chk_kana
    cmp     edi, 0x4DBF
    jbe     .vo_u

.vo_chk_kana:
    ; Hiragana, Katakana → Upright
    cmp     edi, 0x3040
    jb      .vo_chk_hangul
    cmp     edi, 0x30FF
    jbe     .vo_u

.vo_chk_hangul:
    ; Hangul → Upright
    cmp     edi, 0xAC00
    jb      .vo_chk_cjk_sym
    cmp     edi, 0xD7AF
    jbe     .vo_u

.vo_chk_cjk_sym:
    ; CJK Symbols, CJK punctuation → Upright
    cmp     edi, 0x3000
    jb      .vo_chk_fullwidth
    cmp     edi, 0x303F
    jbe     .vo_u

.vo_chk_fullwidth:
    ; Fullwidth Latin → Upright (they're fullwidth for a reason)
    cmp     edi, 0xFF01
    jb      .vo_chk_enclosed
    cmp     edi, 0xFF60
    jbe     .vo_u

.vo_chk_enclosed:
    ; Enclosed CJK → Upright
    cmp     edi, 0x3200
    jb      .vo_chk_emoji
    cmp     edi, 0x33FF
    jbe     .vo_u

.vo_chk_emoji:
    ; Emoji → Upright
    cmp     edi, 0x1F300
    jb      .vo_chk_bopomofo
    cmp     edi, 0x1FAFF
    jbe     .vo_u

.vo_chk_bopomofo:
    ; Bopomofo → Upright
    cmp     edi, 0x3100
    jb      .vo_chk_yi
    cmp     edi, 0x312F
    jbe     .vo_u

.vo_chk_yi:
    ; Yi → Upright
    cmp     edi, 0xA000
    jb      .vo_chk_supp
    cmp     edi, 0xA4CF
    jbe     .vo_u

.vo_chk_supp:
    ; CJK Ext B → Upright
    cmp     edi, 0x20000
    jb      .vo_r
    cmp     edi, 0x2FA1F
    jbe     .vo_u

    ; default: Rotated (Latin/Greek/Cyrillic/etc. turn sideways)
.vo_r:  mov al, VERT_R
    pop rbp
    ret
.vo_u:  mov al, VERT_U
    pop rbp
    ret

STR_ENDFUNC str_cp_vertical_orientation

STR_FUNC str_cp_is_vertical_upright
    call    str_cp_vertical_orientation
    cmp     al, VERT_U
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_vertical_upright
%endif ; GUARD_LIB_STR_UNICODE_VERTICAL_ASM
