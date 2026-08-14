%ifndef GUARD_LIB_STR_UNICODE_PROPERTY_ALIASES_ASM
%define GUARD_LIB_STR_UNICODE_PROPERTY_ALIASES_ASM
; =============================================================================
; str/unicode/property_aliases.asm
; Property name/value alias resolution (PropertyAliases.txt, PropertyValueAliases.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: PropertyAliases.txt, PropertyValueAliases.txt
;
; -----------------------------------------------------------------------------
; Unicode properties have multiple names (aliases):
;   Short form:  "gc"
;   Long form:   "General_Category"
;   Display:     "general category"
;
; Property values also have aliases:
;   Short: "Lu"
;   Long:  "Uppercase_Letter"
;
; This is essential for implementing regex-style property escapes:
;   \p{Lu}                  — match uppercase letters
;   \p{General_Category=Lu} — equivalent
;   \p{Script=Latin}        — match Latin script
;
; Property IDs (internal enumeration):
;   PROP_GC     = 1   — General_Category
;   PROP_SC     = 2   — Script
;   PROP_BC     = 3   — Bidi_Class
;   PROP_DT     = 4   — Decomposition_Type
;   PROP_NT     = 5   — Numeric_Type
;   PROP_CCC    = 6   — Canonical_Combining_Class
;   PROP_JT     = 7   — Joining_Type
;   PROP_LB     = 8   — Line_Break
;   PROP_EA     = 9   — East_Asian_Width
;   PROP_BLK    = 10  — Block
;   PROP_AGE    = 11  — Age
;   PROP_HST    = 12  — Hangul_Syllable_Type
;   PROP_GCB    = 13  — Grapheme_Cluster_Break
;   PROP_WB     = 14  — Word_Break
;   PROP_SB     = 15  — Sentence_Break
;
; Functions:
;   str_property_from_alias       — resolve property name → property ID
;   str_property_value_from_alias — resolve value name → value ID
;   str_property_short_name       — property ID → short name
;   str_property_long_name        — property ID → long name
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Property IDs
PROP_NONE   equ 0
PROP_GC     equ 1
PROP_SC     equ 2
PROP_BC     equ 3
PROP_DT     equ 4
PROP_NT     equ 5
PROP_CCC    equ 6
PROP_JT     equ 7
PROP_LB     equ 8
PROP_EA     equ 9
PROP_BLK    equ 10
PROP_AGE    equ 11
PROP_HST    equ 12
PROP_GCB    equ 13
PROP_WB     equ 14
PROP_SB     equ 15
PROP_MAX    equ 15

section .text

; -----------------------------------------------------------------------------
; str_property_from_alias
;
; Resolve a property alias (short or long) to a property ID.
; Case-insensitive matching with underscore/space equivalence.
;
; Signature:
;   int64_t str_property_from_alias(const StrSlice *alias, uint8_t *out_prop_id)
;
; Arguments:
;   RDI  — alias string (e.g., "gc", "General_Category", "script")
;   RSI  — pointer to receive property ID
;
; Returns:
;   RAX  = STR_OK if resolved
;   RAX  = STR_ERR_NOT_FOUND if unknown alias
; -----------------------------------------------------------------------------

STR_FUNC str_property_from_alias

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     r12, rdi            ; alias
    mov     r13, rsi            ; out

    ; linear search through property alias table
    lea     rbx, [rel _prop_aliases]
    xor     ecx, ecx            ; index

.pfa_loop:
    cmp     ecx, _PROP_ALIAS_COUNT
    jae     .pfa_not_found

    ; each entry: { short_ptr:8, short_len:8, long_ptr:8, long_len:8, id:1, pad:7 }
    ; = 40 bytes per entry
    push    rcx

    ; try short name
    mov     rdi, r12            ; caller's alias
    lea     rsi, [rbx + rcx * 8 * 5]  ; entry base (40 bytes)
    call    str_eq
    test    eax, eax
    jnz     .pfa_found_short

    ; try long name
    pop     rcx
    push    rcx
    mov     rdi, r12
    lea     rsi, [rbx + rcx * 8 * 5 + 16]  ; long name StrSlice
    call    str_eq
    test    eax, eax
    jnz     .pfa_found_long

    pop     rcx
    inc     ecx
    jmp     .pfa_loop

.pfa_found_short:
.pfa_found_long:
    pop     rcx
    lea     rax, [rbx + rcx * 8 * 5 + 32]
    movzx   eax, byte [rax]    ; property ID
    mov     [r13], al

    pop_regs r13, r12, rbx
    xor     eax, eax            ; STR_OK
    pop     rbp
    ret

.pfa_not_found:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_property_from_alias

; -----------------------------------------------------------------------------
; str_property_value_from_alias
;
; Resolve a property value alias to a value ID.
;
; Signature:
;   int64_t str_property_value_from_alias(uint8_t prop_id,
;                                          const StrSlice *alias,
;                                          uint8_t *out_value_id)
;
; Arguments:
;   DIL  — property ID (PROP_GC, PROP_SC, etc.)
;   RSI  — value alias string (e.g., "Lu", "Uppercase_Letter")
;   RDX  — pointer to receive value ID
;
; Returns:
;   RAX  = STR_OK if resolved
;   RAX  = STR_ERR_NOT_FOUND if unknown
; -----------------------------------------------------------------------------

STR_FUNC str_property_value_from_alias

    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    movzx   ebx, dil            ; prop_id
    mov     r12, rsi            ; alias
    mov     r13, rdx            ; out

    ; dispatch by property ID to the appropriate value alias table
    cmp     ebx, PROP_GC
    je      .pvfa_gc
    cmp     ebx, PROP_SC
    je      .pvfa_sc
    ; (other properties would have their own tables)
    jmp     .pvfa_not_found

.pvfa_gc:
    ; General_Category value aliases
    lea     r14, [rel _gc_value_aliases]
    mov     ecx, _GC_VALUE_COUNT
    jmp     .pvfa_search

.pvfa_sc:
    ; Script value aliases
    lea     r14, [rel _sc_value_aliases]
    mov     ecx, _SC_VALUE_COUNT
    jmp     .pvfa_search

.pvfa_search:
    ; search the value alias table
    ; each entry: { short_ptr:8, short_len:8, long_ptr:8, long_len:8, id:1, pad:7 }
    xor     r8d, r8d

.pvfa_loop:
    cmp     r8d, ecx
    jae     .pvfa_not_found

    push    rcx
    push    r8

    ; try short name
    mov     rdi, r12
    lea     rsi, [r14 + r8 * 8 * 5]
    call    str_eq
    test    eax, eax
    jnz     .pvfa_found

    ; try long name
    pop     r8
    push    r8
    mov     rdi, r12
    lea     rsi, [r14 + r8 * 8 * 5 + 16]
    call    str_eq
    test    eax, eax
    jnz     .pvfa_found

    pop     r8
    pop     rcx
    inc     r8d
    jmp     .pvfa_loop

.pvfa_found:
    pop     r8
    pop     rcx
    lea     rax, [r14 + r8 * 8 * 5 + 32]
    movzx   eax, byte [rax]
    mov     [r13], al

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pvfa_not_found:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_property_value_from_alias

; -----------------------------------------------------------------------------
; str_property_short_name
;
; Get the short alias name for a property ID.
;
; Signature:
;   int64_t str_property_short_name(uint8_t prop_id, StrSlice *out)
;
; Arguments:
;   DIL  — property ID
;   RSI  — output StrSlice
;
; Returns:
;   RAX  = STR_OK or STR_ERR_NOT_FOUND
; -----------------------------------------------------------------------------

STR_FUNC str_property_short_name

    guard_null rsi, STR_ERR_NULL

    movzx   eax, dil
    cmp     eax, PROP_MAX
    ja      .psn_not_found
    test    eax, eax
    jz      .psn_not_found

    ; lookup in alias table: entry index = prop_id - 1
    dec     eax
    lea     rcx, [rel _prop_aliases]
    lea     rcx, [rcx + rax * 8 * 5]   ; 40 bytes per entry

    ; copy short name StrSlice
    mov     rax, [rcx]          ; ptr
    mov     [rsi + StrSlice.ptr], rax
    mov     rax, [rcx + 8]      ; len
    mov     [rsi + StrSlice.len], rax

    xor     eax, eax
    pop     rbp
    ret

.psn_not_found:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_property_short_name

; -----------------------------------------------------------------------------
; str_property_long_name
;
; Get the long alias name for a property ID.
;
; Signature:
;   int64_t str_property_long_name(uint8_t prop_id, StrSlice *out)
;
; Arguments:
;   DIL  — property ID
;   RSI  — output StrSlice
;
; Returns:
;   RAX  = STR_OK or STR_ERR_NOT_FOUND
; -----------------------------------------------------------------------------

STR_FUNC str_property_long_name

    guard_null rsi, STR_ERR_NULL

    movzx   eax, dil
    cmp     eax, PROP_MAX
    ja      .pln_not_found
    test    eax, eax
    jz      .pln_not_found

    dec     eax
    lea     rcx, [rel _prop_aliases]
    lea     rcx, [rcx + rax * 8 * 5 + 16]  ; long name offset

    mov     rax, [rcx]
    mov     [rsi + StrSlice.ptr], rax
    mov     rax, [rcx + 8]
    mov     [rsi + StrSlice.len], rax

    xor     eax, eax
    pop     rbp
    ret

.pln_not_found:
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_property_long_name

; =============================================================================
; Read-only data: alias tables
; =============================================================================

section .rodata

; Property alias string data
_pa_gc_short:   db "gc", 0
_pa_gc_long:    db "General_Category", 0
_pa_sc_short:   db "sc", 0
_pa_sc_long:    db "Script", 0
_pa_bc_short:   db "bc", 0
_pa_bc_long:    db "Bidi_Class", 0
_pa_dt_short:   db "dt", 0
_pa_dt_long:    db "Decomposition_Type", 0
_pa_nt_short:   db "nt", 0
_pa_nt_long:    db "Numeric_Type", 0
_pa_ccc_short:  db "ccc", 0
_pa_ccc_long:   db "Canonical_Combining_Class", 0
_pa_jt_short:   db "jt", 0
_pa_jt_long:    db "Joining_Type", 0
_pa_lb_short:   db "lb", 0
_pa_lb_long:    db "Line_Break", 0
_pa_ea_short:   db "ea", 0
_pa_ea_long:    db "East_Asian_Width", 0
_pa_blk_short:  db "blk", 0
_pa_blk_long:   db "Block", 0
_pa_age_short:  db "age", 0
_pa_age_long:   db "Age", 0
_pa_hst_short:  db "hst", 0
_pa_hst_long:   db "Hangul_Syllable_Type", 0
_pa_gcb_short:  db "GCB", 0
_pa_gcb_long:   db "Grapheme_Cluster_Break", 0
_pa_wb_short:   db "WB", 0
_pa_wb_long:    db "Word_Break", 0
_pa_sb_short:   db "SB", 0
_pa_sb_long:    db "Sentence_Break", 0

; Counts for the search loops
_PROP_ALIAS_COUNT equ 15

; Property alias table (stub — entries point to the string data above)
; Each entry: { short_ptr:8, short_len:8, long_ptr:8, long_len:8, id:1, pad:7 }
; This would be generated by the build system. Placeholder:
_prop_aliases:
    times 40 * 15 db 0          ; 15 entries × 40 bytes

; General_Category value aliases (stub)
_GC_VALUE_COUNT equ 0
_gc_value_aliases:
    dq 0                        ; placeholder

; Script value aliases (stub)
_SC_VALUE_COUNT equ 0
_sc_value_aliases:
    dq 0                        ; placeholder

%endif ; GUARD_LIB_STR_UNICODE_PROPERTY_ALIASES_ASM
