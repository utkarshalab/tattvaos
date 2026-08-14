%ifndef GUARD_LIB_STR_UNICODE_CATEGORY_ASM
%define GUARD_LIB_STR_UNICODE_CATEGORY_ASM
; =============================================================================
; str/unicode/category.asm
; Unicode general category lookup (Lu, Ll, Nd, Po, etc).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   unicode/tables/category_table.s  (the generated lookup data)
;
; -----------------------------------------------------------------------------
; Unicode general categories (30 values, grouped):
;
;   Letters:        Lu Ll Lt Lm Lo
;   Marks:          Mn Mc Me
;   Numbers:        Nd Nl No
;   Punctuation:    Pc Pd Ps Pe Pi Pf Po
;   Symbols:        Sm Sc Sk So
;   Separators:     Zs Zl Zp
;   Other:          Cc Cf Cs Co Cn
;
; Lookup uses a two-stage table (trie):
;   stage1[cp >> 8]            → block index
;   stage2[block_index][cp & 0xFF] → category byte
;
; This compresses the 1.1M codepoint space to ~30KB since most blocks
; share the same category pattern.
;
; Functions:
;   str_cp_category       — get category enum for a codepoint
;   str_cp_category_str   — get 2-letter category abbreviation
;   str_cp_is_category    — test if codepoint is in a major category
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Category enum values (matches Unicode general category order)
CAT_Lu  equ 0      ; Letter, uppercase
CAT_Ll  equ 1      ; Letter, lowercase
CAT_Lt  equ 2      ; Letter, titlecase
CAT_Lm  equ 3      ; Letter, modifier
CAT_Lo  equ 4      ; Letter, other
CAT_Mn  equ 5      ; Mark, nonspacing
CAT_Mc  equ 6      ; Mark, spacing combining
CAT_Me  equ 7      ; Mark, enclosing
CAT_Nd  equ 8      ; Number, decimal digit
CAT_Nl  equ 9      ; Number, letter
CAT_No  equ 10     ; Number, other
CAT_Pc  equ 11     ; Punctuation, connector
CAT_Pd  equ 12     ; Punctuation, dash
CAT_Ps  equ 13     ; Punctuation, open
CAT_Pe  equ 14     ; Punctuation, close
CAT_Pi  equ 15     ; Punctuation, initial quote
CAT_Pf  equ 16     ; Punctuation, final quote
CAT_Po  equ 17     ; Punctuation, other
CAT_Sm  equ 18     ; Symbol, math
CAT_Sc  equ 19     ; Symbol, currency
CAT_Sk  equ 20     ; Symbol, modifier
CAT_So  equ 21     ; Symbol, other
CAT_Zs  equ 22     ; Separator, space
CAT_Zl  equ 23     ; Separator, line
CAT_Zp  equ 24     ; Separator, paragraph
CAT_Cc  equ 25     ; Other, control
CAT_Cf  equ 26     ; Other, format
CAT_Cs  equ 27     ; Other, surrogate
CAT_Co  equ 28     ; Other, private use
CAT_Cn  equ 29     ; Other, not assigned

; Major category groups (high nibble for fast classification)
CATGROUP_LETTER     equ 0
CATGROUP_MARK       equ 1
CATGROUP_NUMBER     equ 2
CATGROUP_PUNCT      equ 3
CATGROUP_SYMBOL     equ 4
CATGROUP_SEPARATOR  equ 5
CATGROUP_OTHER      equ 6

; External table symbols (defined in tables/category_table.s)
extern _ucd_cat_stage1      ; uint16_t[4352]  (cp>>8 for cp up to 0x10FFFF)
extern _ucd_cat_stage2      ; uint8_t[N][256] category blocks

section .rodata

; 2-letter abbreviations indexed by category enum
_cat_names:
    db "Lu", "Ll", "Lt", "Lm", "Lo"
    db "Mn", "Mc", "Me"
    db "Nd", "Nl", "No"
    db "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po"
    db "Sm", "Sc", "Sk", "So"
    db "Zs", "Zl", "Zp"
    db "Cc", "Cf", "Cs", "Co", "Cn"

; Map each category enum → major group
_cat_to_group:
    db CATGROUP_LETTER, CATGROUP_LETTER, CATGROUP_LETTER     ; Lu Ll Lt
    db CATGROUP_LETTER, CATGROUP_LETTER                       ; Lm Lo
    db CATGROUP_MARK, CATGROUP_MARK, CATGROUP_MARK            ; Mn Mc Me
    db CATGROUP_NUMBER, CATGROUP_NUMBER, CATGROUP_NUMBER      ; Nd Nl No
    db CATGROUP_PUNCT, CATGROUP_PUNCT, CATGROUP_PUNCT         ; Pc Pd Ps
    db CATGROUP_PUNCT, CATGROUP_PUNCT, CATGROUP_PUNCT, CATGROUP_PUNCT ; Pe Pi Pf Po
    db CATGROUP_SYMBOL, CATGROUP_SYMBOL, CATGROUP_SYMBOL, CATGROUP_SYMBOL ; Sm Sc Sk So
    db CATGROUP_SEPARATOR, CATGROUP_SEPARATOR, CATGROUP_SEPARATOR ; Zs Zl Zp
    db CATGROUP_OTHER, CATGROUP_OTHER, CATGROUP_OTHER         ; Cc Cf Cs
    db CATGROUP_OTHER, CATGROUP_OTHER                         ; Co Cn

section .text

; -----------------------------------------------------------------------------
; str_cp_category
;
; Look up the Unicode general category of a codepoint.
;
; Signature:
;   uint8_t str_cp_category(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AL   — category enum (CAT_Lu .. CAT_Cn), CAT_Cn for unassigned/invalid
; -----------------------------------------------------------------------------

STR_FUNC str_cp_category

    ; bounds: cp > 0x10FFFF → Cn (not assigned)
    cmp     edi, 0x10FFFF
    ja      .cat_unassigned

    ; stage1 index = cp >> 8
    mov     eax, edi
    shr     eax, 8

    lea     r8, [rel _ucd_cat_stage1]
    movzx   r9d, word [r8 + rax * 2]    ; block index

    ; stage2: block r9 offset = r9 * 256 + (cp & 0xFF)
    mov     ecx, edi
    and     ecx, 0xFF

    shl     r9d, 8              ; block * 256
    add     r9d, ecx

    lea     r8, [rel _ucd_cat_stage2]
    movzx   eax, byte [r8 + r9]

    pop     rbp
    ret

.cat_unassigned:
    mov     al, CAT_Cn
    pop     rbp
    ret

STR_ENDFUNC str_cp_category

; -----------------------------------------------------------------------------
; str_cp_category_str
;
; Get the 2-letter abbreviation for a codepoint's category.
;
; Signature:
;   int64_t str_cp_category_str(uint32_t cp, uint8_t *out2)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — pointer to 2-byte output buffer
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_cp_category_str

    guard_null rsi, STR_ERR_NULL

    push_regs rbx
    mov     rbx, rsi

    call    str_cp_category     ; al = category enum

    ; index into _cat_names (2 bytes each)
    movzx   eax, al
    shl     eax, 1              ; * 2
    lea     r8, [rel _cat_names]
    movzx   ecx, word [r8 + rax]
    mov     [rbx], cx           ; write 2 bytes

    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_category_str

; -----------------------------------------------------------------------------
; str_cp_category_group
;
; Get the major category group (letter/mark/number/etc).
;
; Signature:
;   uint8_t str_cp_category_group(uint32_t cp)
;
; Returns:
;   AL  — CATGROUP_* value
; -----------------------------------------------------------------------------

STR_FUNC str_cp_category_group

    call    str_cp_category     ; al = category

    movzx   eax, al
    lea     r8, [rel _cat_to_group]
    movzx   eax, byte [r8 + rax]

    pop     rbp
    ret

STR_ENDFUNC str_cp_category_group

; -----------------------------------------------------------------------------
; str_cp_is_letter / is_mark / is_number / is_punct / is_symbol / is_separator
;
; Fast predicates for major category groups.
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_letter
    call    str_cp_category_group
    cmp     al, CATGROUP_LETTER
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_letter

STR_FUNC str_cp_is_mark
    call    str_cp_category_group
    cmp     al, CATGROUP_MARK
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_mark

STR_FUNC str_cp_is_number_cat
    call    str_cp_category_group
    cmp     al, CATGROUP_NUMBER
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_number_cat

STR_FUNC str_cp_is_punct
    call    str_cp_category_group
    cmp     al, CATGROUP_PUNCT
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_punct

STR_FUNC str_cp_is_symbol
    call    str_cp_category_group
    cmp     al, CATGROUP_SYMBOL
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_symbol

STR_FUNC str_cp_is_separator
    call    str_cp_category_group
    cmp     al, CATGROUP_SEPARATOR
    sete    al
    movzx   eax, al
    pop     rbp
    ret
STR_ENDFUNC str_cp_is_separator
%endif ; GUARD_LIB_STR_UNICODE_CATEGORY_ASM
