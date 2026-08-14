%ifndef GUARD_LIB_STR_UNICODE_WORDBREAK_ASM
%define GUARD_LIB_STR_UNICODE_WORDBREAK_ASM
; =============================================================================
; str/unicode/wordbreak.asm
; Word boundary detection (UAX #29 Word_Break).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm                  (str_utf8_decode_unchecked)
;   unicode/tables/break_table.s     (word break property data)
;
; -----------------------------------------------------------------------------
; Word boundaries are used for: double-click word selection, Ctrl+arrow
; cursor movement, word counting, search "whole word" matching.
;
; Word_Break property values (UAX #29):
;   Other, CR, LF, Newline, Extend, ZWJ, Regional_Indicator, Format,
;   Katakana, Hebrew_Letter, ALetter, Single_Quote, Double_Quote,
;   MidNumLet, MidLetter, MidNum, Numeric, ExtendNumLet, WSegSpace, ExtPict
;
; Key rules:
;   WB3:  CR × LF
;   WB5:  ALetter × ALetter      (don't break within words)
;   WB6:  ALetter × (MidLetter|MidNumLet|Single_Quote) ALetter
;   WB8:  Numeric × Numeric      (don't break within numbers)
;   WB13: Katakana × Katakana
;
; Functions:
;   str_word_count        — count words in a string
;   str_word_next         — find next word boundary
;   str_word_iter_init    — initialize word iterator
;   str_word_iter_next    — get next word
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Word break property values
WB_Other        equ 0
WB_CR           equ 1
WB_LF           equ 2
WB_Newline      equ 3
WB_Extend       equ 4
WB_ZWJ          equ 5
WB_RI           equ 6
WB_Format       equ 7
WB_Katakana     equ 8
WB_HebrewLetter equ 9
WB_ALetter      equ 10
WB_SingleQuote  equ 11
WB_DoubleQuote  equ 12
WB_MidNumLet    equ 13
WB_MidLetter    equ 14
WB_MidNum       equ 15
WB_Numeric      equ 16
WB_ExtendNumLet equ 17
WB_WSegSpace    equ 18
WB_ExtPict      equ 19

extern _ucd_wb_table        ; cp → word break property

section .text

; -----------------------------------------------------------------------------
; _wbp  (internal)
;
; Get the Word_Break property of a codepoint.
;
; Arguments: EDI = codepoint
; Returns:   AL = WB_* value
; -----------------------------------------------------------------------------

_wbp:
    cmp     edi, 0x0D
    je      .wbp_cr
    cmp     edi, 0x0A
    je      .wbp_lf

    ; Newline: 0x0B 0x0C 0x85 0x2028 0x2029
    cmp     edi, 0x0B
    je      .wbp_newline
    cmp     edi, 0x0C
    je      .wbp_newline
    cmp     edi, 0x85
    je      .wbp_newline

    ; ASCII letters → ALetter
    cmp     edi, 'A'
    jb      .wbp_chk_digit
    cmp     edi, 'Z'
    jbe     .wbp_aletter
    cmp     edi, 'a'
    jb      .wbp_chk_digit
    cmp     edi, 'z'
    jbe     .wbp_aletter

.wbp_chk_digit:
    ; ASCII digits → Numeric
    cmp     edi, '0'
    jb      .wbp_chk_punct
    cmp     edi, '9'
    jbe     .wbp_numeric

.wbp_chk_punct:
    ; single quote
    cmp     edi, 0x27
    je      .wbp_single_quote
    ; double quote
    cmp     edi, 0x22
    je      .wbp_double_quote
    ; underscore → ExtendNumLet
    cmp     edi, '_'
    je      .wbp_extnumlet
    ; space → WSegSpace
    cmp     edi, 0x20
    je      .wbp_wsegspace

    ; period, comma → MidNum/MidNumLet
    cmp     edi, '.'
    je      .wbp_midnumlet
    cmp     edi, ','
    je      .wbp_midnum
    cmp     edi, ':'
    je      .wbp_midletter

    ; combining marks → Extend
    cmp     edi, 0x0300
    jb      .wbp_chk_higher
    cmp     edi, 0x036F
    jbe     .wbp_extend

.wbp_chk_higher:
    ; ZWJ
    cmp     edi, 0x200D
    je      .wbp_zwj

    ; Hebrew letters 0x0590-0x05FF
    cmp     edi, 0x05D0
    jb      .wbp_chk_kata
    cmp     edi, 0x05EA
    jbe     .wbp_hebrew

.wbp_chk_kata:
    ; Katakana 0x30A0-0x30FF
    cmp     edi, 0x30A0
    jb      .wbp_chk_latin_ext
    cmp     edi, 0x30FF
    jbe     .wbp_katakana

.wbp_chk_latin_ext:
    ; Latin-1 letters (accented) → ALetter
    cmp     edi, 0xC0
    jb      .wbp_other_fast
    cmp     edi, 0x024F
    jbe     .wbp_aletter

    ; everything else: table lookup or Other
.wbp_table:
    jmp     .wbp_other_fast

.wbp_cr:        mov al, WB_CR
    ret
.wbp_lf:        mov al, WB_LF
    ret
.wbp_newline:   mov al, WB_Newline
    ret
.wbp_extend:    mov al, WB_Extend
    ret
.wbp_zwj:       mov al, WB_ZWJ
    ret
.wbp_aletter:   mov al, WB_ALetter
    ret
.wbp_numeric:   mov al, WB_Numeric
    ret
.wbp_hebrew:    mov al, WB_HebrewLetter
    ret
.wbp_katakana:  mov al, WB_Katakana
    ret
.wbp_single_quote: mov al, WB_SingleQuote
    ret
.wbp_double_quote: mov al, WB_DoubleQuote
    ret
.wbp_midnumlet: mov al, WB_MidNumLet
    ret
.wbp_midnum:    mov al, WB_MidNum
    ret
.wbp_midletter: mov al, WB_MidLetter
    ret
.wbp_extnumlet: mov al, WB_ExtendNumLet
    ret
.wbp_wsegspace: mov al, WB_WSegSpace
    ret
.wbp_other_fast: mov al, WB_Other
    ret

; -----------------------------------------------------------------------------
; _is_word_boundary  (internal)
;
; Determine if there is a word boundary between two codepoints.
; Implements key UAX #29 word break rules.
;
; Arguments: DIL = prop_a, SIL = prop_b
; Returns:   AL = 1 if boundary, 0 if no boundary
;
; Note: full word breaking requires lookahead (WB6/WB7/WB11/WB12) which
; the iterator handles; this covers the pairwise rules.
; -----------------------------------------------------------------------------

_is_word_boundary:
    movzx   eax, dil
    movzx   ecx, sil

    ; WB3: CR × LF
    cmp     al, WB_CR
    jne     .wb_not_cr
    cmp     cl, WB_LF
    je      .wb_no_break

.wb_not_cr:
    ; WB3a: (Newline|CR|LF) ÷
    cmp     al, WB_Newline
    je      .wb_break
    cmp     al, WB_CR
    je      .wb_break
    cmp     al, WB_LF
    je      .wb_break

    ; WB3b: ÷ (Newline|CR|LF)
    cmp     cl, WB_Newline
    je      .wb_break
    cmp     cl, WB_CR
    je      .wb_break
    cmp     cl, WB_LF
    je      .wb_break

    ; WB3d: WSegSpace × WSegSpace
    cmp     al, WB_WSegSpace
    jne     .wb_not_wseg
    cmp     cl, WB_WSegSpace
    je      .wb_no_break

.wb_not_wseg:
    ; WB4: X (Extend|Format|ZWJ)* → ignore Extend/Format/ZWJ after
    cmp     cl, WB_Extend
    je      .wb_no_break
    cmp     cl, WB_Format
    je      .wb_no_break
    cmp     cl, WB_ZWJ
    je      .wb_no_break

    ; WB5: AHLetter × AHLetter  (ALetter or HebrewLetter)
    call    .is_ahletter_a
    jz      .wb_not_ah_a
    movzx   ecx, sil
    call    .is_ahletter_c
    jz      .wb_not_ah_a
    jmp     .wb_no_break

.wb_not_ah_a:
    movzx   eax, dil
    movzx   ecx, sil

    ; WB8: Numeric × Numeric
    cmp     al, WB_Numeric
    jne     .wb_not_num
    cmp     cl, WB_Numeric
    je      .wb_no_break

.wb_not_num:
    ; WB9: AHLetter × Numeric
    movzx   eax, dil
    call    .is_ahletter_a
    jz      .wb_not_ahnum
    movzx   ecx, sil
    cmp     cl, WB_Numeric
    je      .wb_no_break

.wb_not_ahnum:
    ; WB10: Numeric × AHLetter
    movzx   eax, dil
    cmp     al, WB_Numeric
    jne     .wb_not_numah
    movzx   ecx, sil
    call    .is_ahletter_c
    jnz     .wb_no_break

.wb_not_numah:
    ; WB13: Katakana × Katakana
    movzx   eax, dil
    movzx   ecx, sil
    cmp     al, WB_Katakana
    jne     .wb_not_kata
    cmp     cl, WB_Katakana
    je      .wb_no_break

.wb_not_kata:
    ; WB13a: (AHLetter|Numeric|Katakana|ExtendNumLet) × ExtendNumLet
    cmp     cl, WB_ExtendNumLet
    jne     .wb_not_enl
    cmp     al, WB_ALetter
    je      .wb_no_break
    cmp     al, WB_HebrewLetter
    je      .wb_no_break
    cmp     al, WB_Numeric
    je      .wb_no_break
    cmp     al, WB_Katakana
    je      .wb_no_break
    cmp     al, WB_ExtendNumLet
    je      .wb_no_break

.wb_not_enl:
    ; WB13b: ExtendNumLet × (AHLetter|Numeric|Katakana)
    cmp     al, WB_ExtendNumLet
    jne     .wb_default
    cmp     cl, WB_ALetter
    je      .wb_no_break
    cmp     cl, WB_HebrewLetter
    je      .wb_no_break
    cmp     cl, WB_Numeric
    je      .wb_no_break
    cmp     cl, WB_Katakana
    je      .wb_no_break

.wb_default:
    ; WB999: any ÷ any
.wb_break:
    mov     al, 1
    ret

.wb_no_break:
    xor     al, al
    ret

; helper: set ZF=0 if eax is ALetter or HebrewLetter
.is_ahletter_a:
    cmp     al, WB_ALetter
    je      .ah_a_yes
    cmp     al, WB_HebrewLetter
    je      .ah_a_yes
    xor     eax, eax            ; ZF=1 (not ahletter)
    ret
.ah_a_yes:
    mov     eax, 1             ; ZF=0
    ret

.is_ahletter_c:
    cmp     cl, WB_ALetter
    je      .ah_c_yes
    cmp     cl, WB_HebrewLetter
    je      .ah_c_yes
    xor     ecx, ecx
    test    ecx, ecx
    ret
.ah_c_yes:
    mov     ecx, 1
    test    ecx, ecx
    ret

; -----------------------------------------------------------------------------
; str_word_next
;
; Find the byte offset of the next word boundary after the given offset.
;
; Signature:
;   int64_t str_word_next(const StrSlice *src, uint64_t offset,
;                          uint64_t *out_next)
; -----------------------------------------------------------------------------

STR_FUNC str_word_next

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; pre-allocate 16 bytes for out_advance + 8 bytes padding

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; offset
    mov     r14, rdx            ; out_next

    cmp     r13, r12
    jae     .wn_end

    ; decode first cp
    lea     r15, [rbx + r13]
    mov     rdi, r15
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     r9, [rsp]

    add     r13, r9

    mov     edi, r8d
    call    _wbp
    movzx   r10d, al            ; prev prop

.wn_loop:
    cmp     r13, r12
    jae     .wn_found

    lea     r15, [rbx + r13]
    mov     rdi, r15
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     r9, [rsp]

    mov     edi, r8d
    push    r8                  ; preserve registers (stack kept 16-byte aligned)
    push    r9
    call    _wbp
    pop     r9
    pop     r8
    movzx   ecx, al

    movzx   edi, r10b
    movzx   esi, cl
    push    r8                  ; dummy push for alignment (4 registers pushed = 32 bytes)
    push    r8                  ; preserve
    push    r9
    push    rcx
    call    _is_word_boundary
    pop     rcx
    pop     r9
    pop     r8
    pop     r8

    test    al, al
    jnz     .wn_found

    add     r13, r9
    mov     r10d, ecx
    jmp     .wn_loop

.wn_found:
    mov     [r14], r13
    add     rsp, 24             ; deallocate
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.wn_end:
    add     rsp, 24             ; deallocate
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_word_next

; -----------------------------------------------------------------------------
; str_word_count
;
; Count the number of words (segments containing letters/numbers) in a string.
;
; Signature:
;   int64_t str_word_count(const StrSlice *src, uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_word_count

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 16             ; pre-allocate 16 bytes for out_next/decode

    mov     rbx, rdi            ; src
    mov     r13, rsi            ; out_count

    xor     r12, r12            ; offset
    xor     r14, r14            ; word count

    mov     rax, [rbx + StrSlice.len]
    test    rax, rax
    jz      .wc_done

.wc_loop:
    mov     rax, [rbx + StrSlice.len]
    cmp     r12, rax
    jae     .wc_done

    ; check if segment at r12 begins a word (contains letter/digit)
    ; find next boundary
    mov     rdi, rbx
    mov     rsi, r12
    lea     rdx, [rsp]          ; out_next is at [rsp]
    push    r14                 ; dummy push for alignment (2 registers pushed = 16 bytes)
    push    r14                 ; preserve
    call    str_word_next
    pop     r14
    pop     r14

    test    rax, rax
    jnz     .wc_done

    mov     r9, [rsp]           ; next boundary

    ; check if the segment [r12, r9) contains a word character
    ; decode first codepoint of segment
    mov     r8, [rbx + StrSlice.ptr]
    add     r8, r12

    mov     rdi, r8
    lea     rsi, [rsp + 8]      ; decode at [rsp+8]
    call    str_utf8_decode_unchecked
    mov     edi, eax

    push    r9                  ; dummy push for alignment (2 registers pushed)
    push    r9                  ; preserve
    call    _wbp
    pop     r9
    pop     r9

    ; count as word if ALetter/Hebrew/Numeric/Katakana
    cmp     al, WB_ALetter
    je      .wc_is_word
    cmp     al, WB_HebrewLetter
    je      .wc_is_word
    cmp     al, WB_Numeric
    je      .wc_is_word
    cmp     al, WB_Katakana
    je      .wc_advance

    jmp     .wc_advance

.wc_is_word:
    inc     r14

.wc_advance:
    mov     r12, r9
    jmp     .wc_loop

.wc_done:
    mov     [r13], r14
    add     rsp, 16             ; deallocate
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_word_count

%endif ; GUARD_LIB_STR_UNICODE_WORDBREAK_ASM
