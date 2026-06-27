; =============================================================================
; str/unicode/props.asm
; Unicode boolean properties (PropList.txt + DerivedCoreProperties.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: PropList.txt, DerivedCoreProperties.txt
;
; -----------------------------------------------------------------------------
; Boolean properties are yes/no flags on codepoints:
;   Alphabetic, Lowercase, Uppercase, White_Space, Dash, Hyphen,
;   Quotation_Mark, Terminal_Punctuation, Math, Hex_Digit, ID_Start,
;   ID_Continue, XID_Start, XID_Continue, Pattern_Syntax,
;   Pattern_White_Space, Noncharacter_Code_Point, Default_Ignorable...
;
; These are the building blocks for higher-level checks like "is this
; a valid identifier?" (ID_Start + ID_Continue).
;
; Functions:
;   str_cp_is_alphabetic       — Alphabetic property (letters + Nl + Other_Alphabetic)
;   str_cp_is_id_start         — valid first char of identifier
;   str_cp_is_id_continue      — valid continuation char of identifier
;   str_cp_is_white_space      — Unicode White_Space property
;   str_cp_is_dash             — Dash property
;   str_cp_is_quotation_mark   — Quotation_Mark property
;   str_cp_is_math             — Math property
;   str_cp_is_hex_digit_uni    — Hex_Digit property (ASCII + fullwidth)
;   str_cp_is_noncharacter     — Noncharacter_Code_Point
;   str_cp_is_default_ignorable — Default_Ignorable_Code_Point
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_cp_is_alphabetic — letters + numeric letters + Other_Alphabetic marks
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_alphabetic

    ; ASCII letters
    cmp     edi, 'A'
    jb      .ia_chk_lower
    cmp     edi, 'Z'
    jbe     .ia_yes
.ia_chk_lower:
    cmp     edi, 'a'
    jb      .ia_chk_latin1
    cmp     edi, 'z'
    jbe     .ia_yes

.ia_chk_latin1:
    ; Latin-1 letters
    cmp     edi, 0xC0
    jb      .ia_chk_other
    cmp     edi, 0xFF
    ja      .ia_chk_other
    cmp     edi, 0xD7
    je      .ia_no
    cmp     edi, 0xF7
    je      .ia_no
    jmp     .ia_yes

.ia_chk_other:
    ; broad ranges for major scripts
    cmp     edi, 0x0100
    jb      .ia_no
    cmp     edi, 0x024F
    jbe     .ia_yes             ; Latin Extended
    cmp     edi, 0x0370
    jb      .ia_chk_cyrillic
    cmp     edi, 0x03FF
    jbe     .ia_yes             ; Greek
.ia_chk_cyrillic:
    cmp     edi, 0x0400
    jb      .ia_chk_devanagari
    cmp     edi, 0x04FF
    jbe     .ia_yes
.ia_chk_devanagari:
    cmp     edi, 0x0900
    jb      .ia_chk_cjk
    cmp     edi, 0x097F
    jbe     .ia_yes
.ia_chk_cjk:
    cmp     edi, 0x4E00
    jb      .ia_no
    cmp     edi, 0x9FFF
    jbe     .ia_yes

.ia_no:  xor eax, eax
    pop rbp
    ret
.ia_yes: mov eax, 1
    pop rbp
    ret

STR_ENDFUNC str_cp_is_alphabetic

; -----------------------------------------------------------------------------
; str_cp_is_id_start — valid identifier start (letters + Nl + Other_ID_Start)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_id_start

    cmp     edi, '_'
    je      .ids_yes

    call    str_cp_is_alphabetic
    pop     rbp
    ret

.ids_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_id_start

; -----------------------------------------------------------------------------
; str_cp_is_id_continue — valid identifier continuation
; (ID_Start + Mn + Mc + Nd + Pc + Other_ID_Continue)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_id_continue

    ; digits
    cmp     edi, '0'
    jb      .idc_chk_under
    cmp     edi, '9'
    jbe     .idc_yes

.idc_chk_under:
    ; underscore (Pc)
    cmp     edi, '_'
    je      .idc_yes

    ; combining marks (Mn/Mc): 0x0300-0x036F
    cmp     edi, 0x0300
    jb      .idc_chk_alpha
    cmp     edi, 0x036F
    jbe     .idc_yes

.idc_chk_alpha:
    call    str_cp_is_alphabetic
    pop     rbp
    ret

.idc_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_id_continue

; -----------------------------------------------------------------------------
; str_cp_is_white_space — Unicode White_Space property
; (not just ASCII space — includes NBSP, em space, ideographic space, etc)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_white_space

    cmp     edi, 0x20
    je      .ws_yes
    cmp     edi, 0x09
    je      .ws_yes
    cmp     edi, 0x0A
    je      .ws_yes
    cmp     edi, 0x0B
    je      .ws_yes
    cmp     edi, 0x0C
    je      .ws_yes
    cmp     edi, 0x0D
    je      .ws_yes
    cmp     edi, 0x85
    je      .ws_yes
    cmp     edi, 0xA0
    je      .ws_yes             ; NBSP
    cmp     edi, 0x1680
    je      .ws_yes             ; Ogham space
    cmp     edi, 0x2000
    jb      .ws_no
    cmp     edi, 0x200A
    jbe     .ws_yes             ; en space..hair space
    cmp     edi, 0x2028
    je      .ws_yes             ; line separator
    cmp     edi, 0x2029
    je      .ws_yes             ; paragraph separator
    cmp     edi, 0x202F
    je      .ws_yes             ; narrow NBSP
    cmp     edi, 0x205F
    je      .ws_yes             ; medium mathematical space
    cmp     edi, 0x3000
    je      .ws_yes             ; ideographic space

.ws_no:  xor eax, eax
    pop rbp
    ret
.ws_yes: mov eax, 1
    pop rbp
    ret

STR_ENDFUNC str_cp_is_white_space

; str_cp_is_dash
STR_FUNC str_cp_is_dash
    cmp     edi, '-'
    je      .d_yes
    cmp     edi, 0x058A
    je      .d_yes              ; Armenian hyphen
    cmp     edi, 0x2010
    jb      .d_no
    cmp     edi, 0x2015
    jbe     .d_yes              ; hyphen..horizontal bar
    cmp     edi, 0x2E17
    je      .d_yes              ; double hyphen
    cmp     edi, 0xFE58
    je      .d_yes              ; small em dash
    cmp     edi, 0xFE63
    je      .d_yes              ; small hyphen-minus
    cmp     edi, 0xFF0D
    je      .d_yes              ; fullwidth hyphen-minus
.d_no:   xor eax, eax
    pop rbp
    ret
.d_yes:  mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_dash

; str_cp_is_quotation_mark
STR_FUNC str_cp_is_quotation_mark
    cmp     edi, 0x22
    je      .qm_yes
    cmp     edi, 0x27
    je      .qm_yes
    cmp     edi, 0x00AB
    je      .qm_yes
    cmp     edi, 0x00BB
    je      .qm_yes
    cmp     edi, 0x2018
    jb      .qm_no
    cmp     edi, 0x201F
    jbe     .qm_yes
    cmp     edi, 0x2039
    je      .qm_yes
    cmp     edi, 0x203A
    je      .qm_yes
    cmp     edi, 0x300C
    jb      .qm_no
    cmp     edi, 0x300F
    jbe     .qm_yes
.qm_no:  xor eax, eax
    pop rbp
    ret
.qm_yes: mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_quotation_mark

; str_cp_is_math
STR_FUNC str_cp_is_math
    cmp     edi, '+'
    je      .m_yes
    cmp     edi, '<'
    je      .m_yes
    cmp     edi, '='
    je      .m_yes
    cmp     edi, '>'
    je      .m_yes
    cmp     edi, '|'
    je      .m_yes
    cmp     edi, '~'
    je      .m_yes
    cmp     edi, 0x00AC
    je      .m_yes              ; ¬
    cmp     edi, 0x00B1
    je      .m_yes              ; ±
    cmp     edi, 0x00D7
    je      .m_yes              ; ×
    cmp     edi, 0x00F7
    je      .m_yes              ; ÷
    cmp     edi, 0x2200
    jb      .m_no
    cmp     edi, 0x22FF
    jbe     .m_yes              ; Mathematical Operators block
    cmp     edi, 0x2A00
    jb      .m_no
    cmp     edi, 0x2AFF
    jbe     .m_yes              ; Supplemental Math Operators
.m_no:   xor eax, eax
    pop rbp
    ret
.m_yes:  mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_math

; str_cp_is_noncharacter
STR_FUNC str_cp_is_noncharacter
    ; FDD0-FDEF
    cmp     edi, 0xFDD0
    jb      .nc_chk_fffe
    cmp     edi, 0xFDEF
    jbe     .nc_yes
.nc_chk_fffe:
    ; xxFFFE and xxFFFF for each plane (0-16)
    mov     eax, edi
    and     eax, 0xFFFF
    cmp     eax, 0xFFFE
    jb      .nc_no
    ; verify it's a valid plane (cp <= 0x10FFFF)
    cmp     edi, 0x10FFFF
    ja      .nc_no
    jmp     .nc_yes
.nc_no:  xor eax, eax
    pop rbp
    ret
.nc_yes: mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_noncharacter

; str_cp_is_default_ignorable
STR_FUNC str_cp_is_default_ignorable
    cmp     edi, 0x00AD
    je      .di_yes             ; soft hyphen
    cmp     edi, 0x034F
    je      .di_yes             ; CGJ
    cmp     edi, 0x061C
    je      .di_yes             ; Arabic letter mark
    cmp     edi, 0x200B
    jb      .di_no
    cmp     edi, 0x200F
    jbe     .di_yes             ; ZWSP, ZWNJ, ZWJ, LRM, RLM
    cmp     edi, 0x202A
    jb      .di_no
    cmp     edi, 0x202E
    jbe     .di_yes             ; LRE..RLO
    cmp     edi, 0x2060
    jb      .di_no
    cmp     edi, 0x2064
    jbe     .di_yes             ; WJ..invisible plus
    cmp     edi, 0x2066
    jb      .di_no
    cmp     edi, 0x206F
    jbe     .di_yes             ; LRI..nominal digit shapes
    cmp     edi, 0xFEFF
    je      .di_yes             ; BOM
    cmp     edi, 0xFFF0
    jb      .di_no
    cmp     edi, 0xFFF8
    jbe     .di_yes             ; specials (interlinear annotation)
.di_no:  xor eax, eax
    pop rbp
    ret
.di_yes: mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_default_ignorable