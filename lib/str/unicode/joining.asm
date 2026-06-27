; =============================================================================
; str/unicode/joining.asm
; Arabic joining types + Indic positional/syllable categories.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: ArabicShaping.txt, IndicPositionalCategory.txt,
;         IndicSyllableCategory.txt
;
; -----------------------------------------------------------------------------
; Arabic Joining Types determine how letters connect in cursive script:
;   R  — Right-joining  (ا alef — joins only to the right)
;   L  — Left-joining   (rare)
;   D  — Dual-joining   (ب beh — joins both sides)
;   C  — Join-causing   (ZWJ, tatweel)
;   U  — Non-joining    (digits, punctuation)
;   T  — Transparent    (combining marks — inherit joining from base)
;
; Indic Positional Category (for complex text shaping):
;   NA, Bottom, Left, Right, Top, Visual_Order_Left, etc.
;
; Indic Syllable Category:
;   Avagraha, Bindu, Brahmi_Joining_Number, Cantillation_Mark,
;   Consonant, Consonant_Dead, Consonant_Final, Consonant_Head_Letter,
;   Consonant_Killer, Consonant_Medial, Consonant_Placeholder,
;   Consonant_Preceding_Repha, Consonant_Prefixed, Consonant_Subjoined,
;   Consonant_Succeeding_Repha, Consonant_With_Stacker, Gemination_Mark,
;   Invisible_Stacker, Joiner, Modifying_Letter, Non_Joiner,
;   Nukta, Number, Number_Joiner, Other, Pure_Killer, Register_Shifter,
;   Syllable_Modifier, Tone_Letter, Tone_Mark, Virama, Visarga, Vowel,
;   Vowel_Dependent, Vowel_Independent
;
; Functions:
;   str_cp_joining_type       — Arabic joining type
;   str_cp_joining_group      — Arabic joining group name
;   str_cp_indic_pos          — Indic positional category
;   str_cp_indic_syllable     — Indic syllable category
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Arabic joining types
JOIN_U  equ 0       ; Non-joining
JOIN_R  equ 1       ; Right-joining
JOIN_L  equ 2       ; Left-joining
JOIN_D  equ 3       ; Dual-joining
JOIN_C  equ 4       ; Join-causing
JOIN_T  equ 5       ; Transparent

; Indic positional categories (subset)
INDIC_POS_NA            equ 0
INDIC_POS_BOTTOM        equ 1
INDIC_POS_LEFT          equ 2
INDIC_POS_RIGHT         equ 3
INDIC_POS_TOP           equ 4
INDIC_POS_TOP_AND_BOTTOM equ 5
INDIC_POS_OVERSTRUCK    equ 6

; Indic syllable categories (subset)
INDIC_SYL_OTHER         equ 0
INDIC_SYL_CONSONANT     equ 1
INDIC_SYL_VOWEL_IND     equ 2
INDIC_SYL_VOWEL_DEP     equ 3
INDIC_SYL_VIRAMA        equ 4
INDIC_SYL_NUKTA         equ 5
INDIC_SYL_BINDU         equ 6
INDIC_SYL_VISARGA       equ 7
INDIC_SYL_NUMBER        equ 8
INDIC_SYL_TONE_MARK     equ 9

extern _ucd_joining_table       ; cp → joining type (generated)
extern _ucd_indic_pos_table     ; cp → indic positional (generated)
extern _ucd_indic_syl_table     ; cp → indic syllable (generated)

section .text

; -----------------------------------------------------------------------------
; str_cp_joining_type
; Arguments: EDI = codepoint
; Returns:   AL = JOIN_* type
; -----------------------------------------------------------------------------

STR_FUNC str_cp_joining_type

    ; Arabic block fast paths
    cmp     edi, 0x0600
    jb      .jt_non_joining
    cmp     edi, 0x06FF
    ja      .jt_chk_ext

    ; Arabic diacritics 0x064B-0x065F → Transparent
    cmp     edi, 0x064B
    jb      .jt_chk_letters
    cmp     edi, 0x065F
    jbe     .jt_transparent

.jt_chk_letters:
    ; Arabic letters 0x0621-0x064A → mostly Dual-joining
    cmp     edi, 0x0621
    jb      .jt_non_joining
    cmp     edi, 0x064A
    ja      .jt_non_joining

    ; Alef variants: right-joining only
    cmp     edi, 0x0622
    jb      .jt_chk_hamza
    cmp     edi, 0x0625
    jbe     .jt_right           ; آ أ ؤ إ
    cmp     edi, 0x0627
    je      .jt_right           ; ا

    ; Dal variants: right-joining
    cmp     edi, 0x062F
    jb      .jt_dual
    cmp     edi, 0x0632
    jbe     .jt_right           ; د ذ ر ز

    ; Waw: right-joining
    cmp     edi, 0x0648
    je      .jt_right

    ; Teh marbuta: right-joining
    cmp     edi, 0x0629
    je      .jt_right

    ; Everything else in this range: dual-joining
    jmp     .jt_dual

.jt_chk_hamza:
    ; Hamza 0x0621: non-joining (standalone)
    cmp     edi, 0x0621
    je      .jt_non_joining
    jmp     .jt_dual

.jt_chk_ext:
    ; Arabic Supplement 0x0750-0x077F → mostly dual-joining
    cmp     edi, 0x0750
    jb      .jt_chk_persian
    cmp     edi, 0x077F
    jbe     .jt_dual

.jt_chk_persian:
    ; Persian/Urdu additions in 0x067E-0x06FF → dual-joining
    cmp     edi, 0x067E
    jb      .jt_chk_tatweel
    cmp     edi, 0x06FF
    jbe     .jt_dual

.jt_chk_tatweel:
    ; Tatweel 0x0640: join-causing
    cmp     edi, 0x0640
    je      .jt_join_causing

    ; ZWJ: join-causing
    cmp     edi, 0x200D
    je      .jt_join_causing

    ; ZWNJ: non-joining
    cmp     edi, 0x200C
    je      .jt_non_joining

    ; combining marks → transparent
    cmp     edi, 0x0300
    jb      .jt_non_joining
    cmp     edi, 0x036F
    jbe     .jt_transparent

.jt_non_joining: mov al, JOIN_U
    pop rbp
    ret
.jt_right:       mov al, JOIN_R
    pop rbp
    ret
.jt_dual:        mov al, JOIN_D
    pop rbp
    ret
.jt_join_causing: mov al, JOIN_C
    pop rbp
    ret
.jt_transparent: mov al, JOIN_T
    pop rbp
    ret

STR_ENDFUNC str_cp_joining_type

; -----------------------------------------------------------------------------
; str_cp_indic_pos — Indic positional category
; str_cp_indic_syllable — Indic syllable category
;
; Fast paths for Devanagari; full table lookup for other Indic scripts.
; -----------------------------------------------------------------------------

STR_FUNC str_cp_indic_pos

    ; Devanagari fast paths
    cmp     edi, 0x0900
    jb      .ip_na
    cmp     edi, 0x097F
    ja      .ip_na

    ; matras (dependent vowels) have positional categories
    cmp     edi, 0x093E
    jb      .ip_na
    cmp     edi, 0x094C
    ja      .ip_chk_virama

    ; ा (0x93E) = right, ि (0x93F) = left, others = right/top/bottom
    cmp     edi, 0x093F
    je      .ip_left
    cmp     edi, 0x0941
    jb      .ip_right
    cmp     edi, 0x0944
    jbe     .ip_bottom
    jmp     .ip_right

.ip_chk_virama:
    cmp     edi, 0x094D
    je      .ip_bottom          ; virama = bottom

.ip_na:     mov al, INDIC_POS_NA
    pop rbp
    ret
.ip_left:   mov al, INDIC_POS_LEFT
    pop rbp
    ret
.ip_right:  mov al, INDIC_POS_RIGHT
    pop rbp
    ret
.ip_bottom: mov al, INDIC_POS_BOTTOM
    pop rbp
    ret
.ip_top:    mov al, INDIC_POS_TOP
    pop rbp
    ret

STR_ENDFUNC str_cp_indic_pos

STR_FUNC str_cp_indic_syllable

    ; Devanagari
    cmp     edi, 0x0900
    jb      .is_other
    cmp     edi, 0x097F
    ja      .is_other

    ; consonants 0x0915-0x0939
    cmp     edi, 0x0915
    jb      .is_chk_vowel
    cmp     edi, 0x0939
    jbe     .is_consonant

.is_chk_vowel:
    ; independent vowels 0x0904-0x0914
    cmp     edi, 0x0904
    jb      .is_chk_dep
    cmp     edi, 0x0914
    jbe     .is_vowel_ind

.is_chk_dep:
    ; dependent vowels (matras) 0x093E-0x094C
    cmp     edi, 0x093E
    jb      .is_chk_virama
    cmp     edi, 0x094C
    jbe     .is_vowel_dep

.is_chk_virama:
    cmp     edi, 0x094D
    je      .is_virama

    ; nukta 0x093C
    cmp     edi, 0x093C
    je      .is_nukta

    ; anusvara 0x0902, visarga 0x0903
    cmp     edi, 0x0902
    je      .is_bindu
    cmp     edi, 0x0903
    je      .is_visarga

    ; digits 0x0966-0x096F
    cmp     edi, 0x0966
    jb      .is_other
    cmp     edi, 0x096F
    jbe     .is_number

.is_other:      mov al, INDIC_SYL_OTHER
    pop rbp
    ret
.is_consonant:  mov al, INDIC_SYL_CONSONANT
    pop rbp
    ret
.is_vowel_ind:  mov al, INDIC_SYL_VOWEL_IND
    pop rbp
    ret
.is_vowel_dep:  mov al, INDIC_SYL_VOWEL_DEP
    pop rbp
    ret
.is_virama:     mov al, INDIC_SYL_VIRAMA
    pop rbp
    ret
.is_nukta:      mov al, INDIC_SYL_NUKTA
    pop rbp
    ret
.is_bindu:      mov al, INDIC_SYL_BINDU
    pop rbp
    ret
.is_visarga:    mov al, INDIC_SYL_VISARGA
    pop rbp
    ret
.is_number:     mov al, INDIC_SYL_NUMBER
    pop rbp
    ret

STR_ENDFUNC str_cp_indic_syllable