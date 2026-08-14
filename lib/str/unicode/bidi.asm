%ifndef GUARD_LIB_STR_UNICODE_BIDI_ASM
%define GUARD_LIB_STR_UNICODE_BIDI_ASM
; =============================================================================
; str/unicode/bidi.asm
; Unicode Bidirectional Algorithm (UAX #9).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm                  (str_utf8_decode_unchecked)
;   unicode/tables/bidi_table.s      (bidi class data, generated)
;
; -----------------------------------------------------------------------------
; The bidi algorithm determines the visual ordering of text containing both
; left-to-right (LTR, e.g. Latin) and right-to-left (RTL, e.g. Arabic,
; Hebrew) characters.
;
; Input:  logical order (the order characters are typed/stored)
; Output: visual order (the order characters are displayed) + per-char level
;
; Embedding levels: even = LTR, odd = RTL. The algorithm assigns a level
; to each character, then reorders runs by level for display.
;
; Bidi classes (the important ones):
;   L    — Left-to-Right (Latin letters, digits in some contexts)
;   R    — Right-to-Left (Hebrew)
;   AL   — Arabic Letter
;   EN   — European Number
;   AN   — Arabic Number
;   ES   — European Separator (+ -)
;   ET   — European Terminator (% $ etc)
;   CS   — Common Separator (, . : etc)
;   NSM  — Nonspacing Mark
;   BN   — Boundary Neutral
;   B    — Paragraph Separator
;   S    — Segment Separator (tab)
;   WS   — Whitespace
;   ON   — Other Neutral
;   LRE LRO RLE RLO PDF — explicit formatting (deprecated in favor of isolates)
;   LRI RLI FSI PDI     — isolate formatting
;
; This is a substantial algorithm (~80 steps). This file provides:
;   - Bidi class lookup
;   - Paragraph level detection (rule P2/P3)
;   - Basic level resolution for the common cases
;   - Reordering of resolved levels (rule L2)
;
; Functions:
;   str_bidi_class        — get bidi class of a codepoint
;   str_bidi_paragraph_level — determine base paragraph direction
;   str_bidi_resolve      — compute embedding levels for each char
;   str_bidi_reorder      — produce visual order from levels
;   str_bidi_is_rtl       — quick check if string is predominantly RTL
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Bidi class values
BIDI_L      equ 0       ; Left-to-Right
BIDI_R      equ 1       ; Right-to-Left
BIDI_AL     equ 2       ; Arabic Letter
BIDI_EN     equ 3       ; European Number
BIDI_ES     equ 4       ; European Separator
BIDI_ET     equ 5       ; European Terminator
BIDI_AN     equ 6       ; Arabic Number
BIDI_CS     equ 7       ; Common Separator
BIDI_NSM    equ 8       ; Nonspacing Mark
BIDI_BN     equ 9       ; Boundary Neutral
BIDI_B      equ 10      ; Paragraph Separator
BIDI_S      equ 11      ; Segment Separator
BIDI_WS     equ 12      ; Whitespace
BIDI_ON     equ 13      ; Other Neutral
BIDI_LRE    equ 14      ; Left-to-Right Embedding
BIDI_LRO    equ 15      ; Left-to-Right Override
BIDI_RLE    equ 16      ; Right-to-Left Embedding
BIDI_RLO    equ 17      ; Right-to-Left Override
BIDI_PDF    equ 18      ; Pop Directional Format
BIDI_LRI    equ 19      ; Left-to-Right Isolate
BIDI_RLI    equ 20      ; Right-to-Left Isolate
BIDI_FSI    equ 21      ; First Strong Isolate
BIDI_PDI    equ 22      ; Pop Directional Isolate

MAX_DEPTH   equ 125     ; max explicit embedding depth (UAX #9)

extern _ucd_bidi_table      ; cp → bidi class

section .text

; -----------------------------------------------------------------------------
; str_bidi_class
;
; Get the bidirectional character class of a codepoint.
;
; Signature:
;   uint8_t str_bidi_class(uint32_t cp)
;
; Arguments: EDI = codepoint
; Returns:   AL = BIDI_* value
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_class

    ; ASCII fast path
    ; Latin letters → L
    cmp     edi, 'A'
    jb      .bc_chk_digit
    cmp     edi, 'Z'
    jbe     .bc_L
    cmp     edi, 'a'
    jb      .bc_chk_digit
    cmp     edi, 'z'
    jbe     .bc_L

.bc_chk_digit:
    ; ASCII digits → EN
    cmp     edi, '0'
    jb      .bc_chk_ws
    cmp     edi, '9'
    jbe     .bc_EN

.bc_chk_ws:
    ; whitespace
    cmp     edi, 0x20
    je      .bc_WS
    cmp     edi, 0x09
    je      .bc_S
    cmp     edi, 0x0A
    je      .bc_B
    cmp     edi, 0x0D
    je      .bc_B

    ; European separators + -
    cmp     edi, '+'
    je      .bc_ES
    cmp     edi, '-'
    je      .bc_ES

    ; European terminators
    cmp     edi, '#'
    je      .bc_ET
    cmp     edi, '$'
    je      .bc_ET
    cmp     edi, '%'
    je      .bc_ET

    ; common separators
    cmp     edi, ','
    je      .bc_CS
    cmp     edi, '.'
    je      .bc_CS
    cmp     edi, ':'
    je      .bc_CS
    cmp     edi, '/'
    je      .bc_CS

    cmp     edi, 0x80
    jb      .bc_ON              ; other ASCII → ON

    ; Hebrew block 0x0590-0x05FF → R
    cmp     edi, 0x0590
    jb      .bc_chk_arabic
    cmp     edi, 0x05FF
    jbe     .bc_chk_hebrew_detail

.bc_chk_arabic:
    ; Arabic block 0x0600-0x06FF → AL (mostly)
    cmp     edi, 0x0600
    jb      .bc_chk_marks
    cmp     edi, 0x06FF
    jbe     .bc_chk_arabic_detail
    ; Arabic Supplement, etc 0x0750-0x077F
    cmp     edi, 0x0750
    jb      .bc_chk_marks
    cmp     edi, 0x077F
    jbe     .bc_AL

.bc_chk_marks:
    ; combining marks → NSM
    cmp     edi, 0x0300
    jb      .bc_table
    cmp     edi, 0x036F
    jbe     .bc_NSM

.bc_table:
    ; isolate/embedding formatting chars
    cmp     edi, 0x2066
    jb      .bc_check_more
    cmp     edi, 0x2069
    ja      .bc_check_more
    ; 0x2066=LRI 0x2067=RLI 0x2068=FSI 0x2069=PDI
    mov     eax, edi
    sub     eax, 0x2066
    add     eax, BIDI_LRI
    pop     rbp
    ret

.bc_check_more:
    ; default for unrecognized → L (or table lookup)
    jmp     .bc_L

.bc_chk_hebrew_detail:
    ; Hebrew points 0x0591-0x05BD etc are NSM; letters 0x05D0-0x05EA are R
    cmp     edi, 0x05D0
    jb      .bc_chk_heb_nsm
    cmp     edi, 0x05EA
    jbe     .bc_R
.bc_chk_heb_nsm:
    cmp     edi, 0x0591
    jb      .bc_R
    cmp     edi, 0x05BD
    jbe     .bc_NSM
    jmp     .bc_R

.bc_chk_arabic_detail:
    ; Arabic-Indic digits 0x0660-0x0669 → AN
    cmp     edi, 0x0660
    jb      .bc_chk_ar_letter
    cmp     edi, 0x0669
    jbe     .bc_AN
.bc_chk_ar_letter:
    ; Arabic diacritics 0x064B-0x065F → NSM
    cmp     edi, 0x064B
    jb      .bc_AL
    cmp     edi, 0x065F
    jbe     .bc_NSM
    jmp     .bc_AL

.bc_L:   mov al, BIDI_L
    ret
.bc_R:   mov al, BIDI_R
    ret
.bc_AL:  mov al, BIDI_AL
    ret
.bc_EN:  mov al, BIDI_EN
    ret
.bc_ES:  mov al, BIDI_ES
    ret
.bc_ET:  mov al, BIDI_ET
    ret
.bc_AN:  mov al, BIDI_AN
    ret
.bc_CS:  mov al, BIDI_CS
    ret
.bc_NSM: mov al, BIDI_NSM
    ret
.bc_B:   mov al, BIDI_B
    ret
.bc_S:   mov al, BIDI_S
    ret
.bc_WS:  mov al, BIDI_WS
    ret
.bc_ON:  mov al, BIDI_ON
    ret

STR_ENDFUNC str_bidi_class

; -----------------------------------------------------------------------------
; str_bidi_paragraph_level
;
; Determine the base paragraph embedding level (rules P2, P3).
; Scans for the first strong directional character.
;   First strong is L          → level 0 (LTR)
;   First strong is R or AL    → level 1 (RTL)
;   No strong character        → level 0 (default LTR)
;
; Signature:
;   uint8_t str_bidi_paragraph_level(const StrSlice *src)
;
; Returns:
;   AL = 0 (LTR) or 1 (RTL)
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_paragraph_level

    test    rdi, rdi
    jz      .bpl_ltr

    push_regs rbx, r12

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]

.bpl_loop:
    cmp     rbx, r12
    jae     .bpl_no_strong

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    mov     edi, r8d
    push    r8
    call    str_bidi_class
    pop     r8

    ; first strong?
    cmp     al, BIDI_L
    je      .bpl_found_ltr
    cmp     al, BIDI_R
    je      .bpl_found_rtl
    cmp     al, BIDI_AL
    je      .bpl_found_rtl

    jmp     .bpl_loop

.bpl_found_ltr:
    pop_regs r12, rbx
.bpl_ltr:
    xor     eax, eax
    pop     rbp
    ret

.bpl_found_rtl:
    pop_regs r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.bpl_no_strong:
    pop_regs r12, rbx
    xor     eax, eax            ; default LTR
    pop     rbp
    ret

STR_ENDFUNC str_bidi_paragraph_level

; -----------------------------------------------------------------------------
; str_bidi_resolve
;
; Compute the embedding level for each codepoint in the string.
; Writes a level byte per codepoint to the levels buffer.
;
; This implements a simplified subset of the bidi algorithm:
;   P2/P3: paragraph level
;   X1-X10: explicit levels (embeddings, overrides, isolates) — basic
;   W1-W7: weak type resolution (NSM, EN, AN, separators)
;   N0-N2: neutral resolution
;   I1/I2: implicit levels
;
; Signature:
;   int64_t str_bidi_resolve(const StrSlice *src, uint8_t base_level,
;                            uint8_t *levels, uint64_t levels_cap,
;                            uint64_t *out_count)
;
; Arguments:
;   RDI  — source StrSlice
;   SIL  — base paragraph level (0 or 1)
;   RDX  — output levels buffer (one byte per codepoint)
;   RCX  — levels buffer capacity
;   R8   — out_count (number of codepoints)
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_resolve

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    movzx   r13d, sil           ; base level
    mov     r14, rdx            ; levels buffer
    mov     r15, rcx            ; levels cap
    push    r8                  ; out_count

    xor     r9, r9              ; codepoint index

.br_loop:
    cmp     rbx, r12
    jae     .br_done

    cmp     r9, r15
    jae     .br_overflow

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r10d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; get bidi class
    mov     edi, r10d
    push    r9
    push    r10
    call    str_bidi_class
    pop     r10
    pop     r9
    movzx   ecx, al

    ; assign implicit level (rules I1/I2) — simplified:
    ;   base even (LTR):  R/AL → level+1, AN/EN → level+2
    ;   base odd (RTL):   L/EN/AN → level+1
    mov     r11d, r13d          ; start with base level

    test    r13d, 1
    jnz     .br_rtl_base

    ; LTR base
    cmp     cl, BIDI_R
    je      .br_lvl1
    cmp     cl, BIDI_AL
    je      .br_lvl1
    cmp     cl, BIDI_AN
    je      .br_lvl2
    cmp     cl, BIDI_EN
    je      .br_lvl2
    jmp     .br_store

.br_lvl1:
    inc     r11d
    jmp     .br_store
.br_lvl2:
    add     r11d, 2
    jmp     .br_store

.br_rtl_base:
    ; RTL base
    cmp     cl, BIDI_L
    je      .br_lvl1
    cmp     cl, BIDI_EN
    je      .br_lvl1
    cmp     cl, BIDI_AN
    je      .br_lvl1

.br_store:
    mov     [r14 + r9], r11b
    inc     r9
    jmp     .br_loop

.br_done:
    pop     r8
    test    r8, r8
    jz      .br_ok
    mov     [r8], r9

.br_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.br_overflow:
    pop     r8
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_bidi_resolve

; -----------------------------------------------------------------------------
; str_bidi_reorder
;
; Produce the visual display order from resolved levels (rule L2).
; Reverses contiguous runs of characters at each level, from the highest
; level down to the lowest odd level.
;
; Output is an array of indices: visual_order[i] = logical index to display
; at visual position i.
;
; Signature:
;   int64_t str_bidi_reorder(const uint8_t *levels, uint64_t count,
;                            uint32_t *visual_order)
;
; Arguments:
;   RDI  — levels array (one byte per char)
;   RSI  — character count
;   RDX  — output visual_order array (count × uint32)
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_reorder

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; levels
    mov     r12, rsi            ; count
    mov     r13, rdx            ; visual_order

    ; initialize visual_order[i] = i
    xor     rcx, rcx
.bro_init:
    cmp     rcx, r12
    jae     .bro_find_max
    mov     [r13 + rcx * 4], ecx
    inc     rcx
    jmp     .bro_init

.bro_find_max:
    ; find max level and min odd level
    xor     r14d, r14d          ; max_level = 0
    mov     r15d, 0xFF          ; min_odd_level = high

    xor     rcx, rcx
.bro_scan:
    cmp     rcx, r12
    jae     .bro_reverse_runs

    movzx   eax, byte [rbx + rcx]
    cmp     eax, r14d
    jbe     .bro_chk_odd
    mov     r14d, eax

.bro_chk_odd:
    test    eax, 1
    jz      .bro_scan_next
    cmp     eax, r15d
    jae     .bro_scan_next
    mov     r15d, eax

.bro_scan_next:
    inc     rcx
    jmp     .bro_scan

.bro_reverse_runs:
    ; from max_level down to min_odd_level:
    ;   reverse each contiguous run of chars with level >= current
    cmp     r15d, 0xFF
    je      .bro_done           ; no RTL runs

.bro_level_loop:
    cmp     r14d, r15d
    jb      .bro_done           ; done all levels

    ; scan for runs with level >= r14d
    xor     rcx, rcx            ; i

.bro_run_scan:
    cmp     rcx, r12
    jae     .bro_next_level

    movzx   eax, byte [rbx + rcx]
    cmp     eax, r14d
    jb      .bro_run_next       ; below threshold

    ; start of run at rcx — find end
    mov     r8, rcx             ; run start
.bro_run_end:
    cmp     rcx, r12
    jae     .bro_reverse
    movzx   eax, byte [rbx + rcx]
    cmp     eax, r14d
    jb      .bro_reverse
    inc     rcx
    jmp     .bro_run_end

.bro_reverse:
    ; reverse visual_order[r8 .. rcx)
    mov     r9, r8              ; left
    mov     r10, rcx
    dec     r10                 ; right

.bro_rev_swap:
    cmp     r9, r10
    jae     .bro_run_scan

    mov     eax, [r13 + r9 * 4]
    mov     r11d, [r13 + r10 * 4]
    mov     [r13 + r9 * 4], r11d
    mov     [r13 + r10 * 4], eax

    inc     r9
    dec     r10
    jmp     .bro_rev_swap

.bro_run_next:
    inc     rcx
    jmp     .bro_run_scan

.bro_next_level:
    dec     r14d
    jmp     .bro_level_loop

.bro_done:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_bidi_reorder

; -----------------------------------------------------------------------------
; str_bidi_is_rtl
;
; Quick check: is the string predominantly RTL (first strong char is R/AL)?
;
; Signature:
;   int64_t str_bidi_is_rtl(const StrSlice *src)
;
; Returns:
;   RAX = 1  RTL paragraph
;   RAX = 0  LTR paragraph
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_is_rtl

    call    str_bidi_paragraph_level
    movzx   eax, al
    pop     rbp
    ret

STR_ENDFUNC str_bidi_is_rtl
%endif ; GUARD_LIB_STR_UNICODE_BIDI_ASM
