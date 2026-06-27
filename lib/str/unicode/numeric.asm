; =============================================================================
; str/unicode/numeric.asm
; Numeric type and value lookup (DerivedNumericType/Values).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: DerivedNumericType.txt, DerivedNumericValues.txt
;
; -----------------------------------------------------------------------------
; Unicode numeric types:
;   Decimal — 0-9 in any script (Nd category)
;   Digit   — superscript/subscript digits (compatibility)
;   Numeric — fractions (½), Roman numerals (Ⅳ), etc.
;   None    — not numeric
;
; This lets you parse "٣" (Arabic 3) or "१" (Devanagari 1) as the integer 3/1,
; or recognize ½ (U+00BD) as the value 0.5.
;
; Functions:
;   str_cp_numeric_type   — Decimal/Digit/Numeric/None
;   str_cp_numeric_value  — integer value (0-9 for decimal digits)
;   str_cp_digit_value    — any decimal digit in any script → 0-9
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

NUM_TYPE_NONE    equ 0
NUM_TYPE_DECIMAL equ 1
NUM_TYPE_DIGIT   equ 2
NUM_TYPE_NUMERIC equ 3

section .text

STR_FUNC str_cp_numeric_type

    ; ASCII digits
    cmp     edi, '0'
    jb      .nt_chk_scripts
    cmp     edi, '9'
    jbe     .nt_decimal

.nt_chk_scripts:
    ; Devanagari digits 0x0966-0x096F
    cmp     edi, 0x0966
    jb      .nt_chk_arabic
    cmp     edi, 0x096F
    jbe     .nt_decimal

.nt_chk_arabic:
    ; Arabic-Indic digits 0x0660-0x0669
    cmp     edi, 0x0660
    jb      .nt_chk_ext_arabic
    cmp     edi, 0x0669
    jbe     .nt_decimal

.nt_chk_ext_arabic:
    ; Extended Arabic-Indic 0x06F0-0x06F9
    cmp     edi, 0x06F0
    jb      .nt_chk_bengali
    cmp     edi, 0x06F9
    jbe     .nt_decimal

.nt_chk_bengali:
    cmp     edi, 0x09E6
    jb      .nt_chk_thai
    cmp     edi, 0x09EF
    jbe     .nt_decimal

.nt_chk_thai:
    cmp     edi, 0x0E50
    jb      .nt_chk_fullwidth
    cmp     edi, 0x0E59
    jbe     .nt_decimal

.nt_chk_fullwidth:
    ; Fullwidth digits 0xFF10-0xFF19
    cmp     edi, 0xFF10
    jb      .nt_chk_super
    cmp     edi, 0xFF19
    jbe     .nt_decimal

.nt_chk_super:
    ; Superscript digits ² ³ ¹
    cmp     edi, 0x00B2
    je      .nt_digit
    cmp     edi, 0x00B3
    je      .nt_digit
    cmp     edi, 0x00B9
    je      .nt_digit
    ; Subscript digits 0x2080-0x2089
    cmp     edi, 0x2080
    jb      .nt_chk_frac
    cmp     edi, 0x2089
    jbe     .nt_digit

.nt_chk_frac:
    ; Fractions: ¼ ½ ¾
    cmp     edi, 0x00BC
    jb      .nt_chk_roman
    cmp     edi, 0x00BE
    jbe     .nt_numeric

.nt_chk_roman:
    ; Roman numerals 0x2160-0x2188
    cmp     edi, 0x2160
    jb      .nt_none
    cmp     edi, 0x2188
    jbe     .nt_numeric

.nt_none:    mov al, NUM_TYPE_NONE
    pop rbp
    ret
.nt_decimal: mov al, NUM_TYPE_DECIMAL
    pop rbp
    ret
.nt_digit:   mov al, NUM_TYPE_DIGIT
    pop rbp
    ret
.nt_numeric: mov al, NUM_TYPE_NUMERIC
    pop rbp
    ret

STR_ENDFUNC str_cp_numeric_type

; -----------------------------------------------------------------------------
; str_cp_digit_value — get 0-9 value of any decimal digit in any script
; Returns: EAX = 0-9, or -1 if not a decimal digit
; -----------------------------------------------------------------------------

STR_FUNC str_cp_digit_value

    ; ASCII
    cmp     edi, '0'
    jb      .dv_chk
    cmp     edi, '9'
    jbe     .dv_ascii

.dv_chk:
    ; All decimal digit blocks are contiguous 10-codepoint ranges
    ; starting at X0. Value = cp - block_start.

    ; Devanagari 0x0966
    cmp     edi, 0x0966
    jb      .dv_chk2
    cmp     edi, 0x096F
    jbe     .dv_offset_0966

.dv_chk2:
    ; Arabic-Indic 0x0660
    cmp     edi, 0x0660
    jb      .dv_chk3
    cmp     edi, 0x0669
    jbe     .dv_offset_0660

.dv_chk3:
    ; Extended Arabic-Indic 0x06F0
    cmp     edi, 0x06F0
    jb      .dv_chk4
    cmp     edi, 0x06F9
    jbe     .dv_offset_06F0

.dv_chk4:
    ; Bengali 0x09E6
    cmp     edi, 0x09E6
    jb      .dv_chk5
    cmp     edi, 0x09EF
    jbe     .dv_offset_09E6

.dv_chk5:
    ; Thai 0x0E50
    cmp     edi, 0x0E50
    jb      .dv_chk6
    cmp     edi, 0x0E59
    jbe     .dv_offset_0E50

.dv_chk6:
    ; Fullwidth 0xFF10
    cmp     edi, 0xFF10
    jb      .dv_none
    cmp     edi, 0xFF19
    jbe     .dv_offset_FF10

.dv_none:
    mov     eax, -1
    pop     rbp
    ret

.dv_ascii:        mov eax, edi
    sub eax, '0'
    pop rbp
    ret
.dv_offset_0966:  mov eax, edi
    sub eax, 0x0966
    pop rbp
    ret
.dv_offset_0660:  mov eax, edi
    sub eax, 0x0660
    pop rbp
    ret
.dv_offset_06F0:  mov eax, edi
    sub eax, 0x06F0
    pop rbp
    ret
.dv_offset_09E6:  mov eax, edi
    sub eax, 0x09E6
    pop rbp
    ret
.dv_offset_0E50:  mov eax, edi
    sub eax, 0x0E50
    pop rbp
    ret
.dv_offset_FF10:  mov eax, edi
    sub eax, 0xFF10
    pop rbp
    ret

STR_ENDFUNC str_cp_digit_value