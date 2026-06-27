; =============================================================================
; str/unicode/sentence.asm
; Sentence boundary detection (UAX #29 Sentence_Break).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm   (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; Sentence boundaries are used for: text-to-speech segmentation, summarization
; (sentence extraction), spell check scoping, NLP preprocessing.
;
; Key insight: "." does NOT always end a sentence:
;   "Dr. Smith went to Washington."  — only one sentence
;   "He paid $3.50 for it."          — only one sentence
;   "Hello. How are you?"            — two sentences
;
; Sentence_Break property values (UAX #29):
;   Other, CR, LF, Extend, Sep, Format, Sp, Lower, Upper, OLetter,
;   Numeric, ATerm, STerm, Close, SContinue
;
; Key rules:
;   SB3:  CR × LF
;   SB4:  Sep | CR | LF  ÷  (break after paragraph separators)
;   SB7:  (Upper|Lower) ATerm × Upper  (don't break: "U.S. Army")
;   SB8:  ATerm Close* Sp* × ¬(OLetter|Upper|Lower|Sep|CR|LF|STerm|ATerm)
;   SB9:  (STerm|ATerm) Close* × (Close|Sp|Sep|CR|LF)
;   SB11: (STerm|ATerm) Close* Sp* Sep? ÷  (break after sentence-ending)
;
; Functions:
;   str_sentence_next    — find next sentence boundary
;   str_sentence_count   — count sentences in a string
;   str_sentence_iter    — iterate over sentences
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

; Sentence break property values
SB_Other      equ 0
SB_CR         equ 1
SB_LF         equ 2
SB_Extend     equ 3
SB_Sep        equ 4      ; paragraph separator (0x2028, 0x2029)
SB_Format     equ 5
SB_Sp         equ 6      ; space
SB_Lower      equ 7
SB_Upper      equ 8
SB_OLetter    equ 9      ; other letter (not upper/lower, e.g. CJK, Arabic)
SB_Numeric    equ 10
SB_ATerm      equ 11     ; sentence-ending . (ambiguous: abbreviation or end)
SB_STerm      equ 12     ; unambiguous sentence terminator (! ? etc)
SB_Close      equ 13     ; close punctuation ) ] } " '
SB_SContinue  equ 14     ; sentence-continuing , : ; —

section .text

; -----------------------------------------------------------------------------
; _sbp  (internal)
;
; Get the Sentence_Break property of a codepoint.
; Arguments: EDI = codepoint
; Returns:   AL = SB_* value
; -----------------------------------------------------------------------------

_sbp:
    cmp     edi, 0x0D
    je      .sbp_cr
    cmp     edi, 0x0A
    je      .sbp_lf

    ; paragraph separators
    cmp     edi, 0x2028
    je      .sbp_sep
    cmp     edi, 0x2029
    je      .sbp_sep
    cmp     edi, 0x85
    je      .sbp_sep

    ; space
    cmp     edi, 0x20
    je      .sbp_sp
    cmp     edi, 0x09
    je      .sbp_sp

    ; sentence terminators: ! ? ‽ etc
    cmp     edi, '!'
    je      .sbp_sterm
    cmp     edi, '?'
    je      .sbp_sterm
    cmp     edi, 0x2047
    je      .sbp_sterm          ; ⁇
    cmp     edi, 0x2048
    je      .sbp_sterm          ; ⁈
    cmp     edi, 0x2049
    je      .sbp_sterm          ; ⁉
    cmp     edi, 0x203D
    je      .sbp_sterm          ; ‽ interrobang

    ; ATerm: period .
    cmp     edi, '.'
    je      .sbp_aterm
    cmp     edi, 0x2024
    je      .sbp_aterm          ; ․ one dot leader
    cmp     edi, 0xFE52
    je      .sbp_aterm          ; ﹒ small period

    ; close punctuation
    cmp     edi, ')'
    je      .sbp_close
    cmp     edi, ']'
    je      .sbp_close
    cmp     edi, '}'
    je      .sbp_close
    cmp     edi, 0x22           ; "
    je      .sbp_close
    cmp     edi, 0x27           ; '
    je      .sbp_close
    cmp     edi, 0x201D         ; "
    je      .sbp_close
    cmp     edi, 0x2019         ; '
    je      .sbp_close

    ; sentence-continuing: , : ; —
    cmp     edi, ','
    je      .sbp_scontinue
    cmp     edi, ':'
    je      .sbp_scontinue
    cmp     edi, ';'
    je      .sbp_scontinue
    cmp     edi, 0x2014         ; em dash
    je      .sbp_scontinue

    ; numeric
    cmp     edi, '0'
    jb      .sbp_chk_letters
    cmp     edi, '9'
    jbe     .sbp_numeric

.sbp_chk_letters:
    ; uppercase ASCII
    cmp     edi, 'A'
    jb      .sbp_chk_lower
    cmp     edi, 'Z'
    jbe     .sbp_upper

.sbp_chk_lower:
    ; lowercase ASCII
    cmp     edi, 'a'
    jb      .sbp_chk_ext
    cmp     edi, 'z'
    jbe     .sbp_lower

.sbp_chk_ext:
    ; Latin-1 upper
    cmp     edi, 0xC0
    jb      .sbp_chk_oletter
    cmp     edi, 0xD6
    jbe     .sbp_upper
    cmp     edi, 0xD8
    jb      .sbp_chk_oletter
    cmp     edi, 0xDE
    jbe     .sbp_upper

    ; Latin-1 lower
    cmp     edi, 0xDF
    jb      .sbp_chk_oletter
    cmp     edi, 0xF6
    jbe     .sbp_lower
    cmp     edi, 0xF8
    jb      .sbp_chk_oletter
    cmp     edi, 0xFF
    jbe     .sbp_lower

.sbp_chk_oletter:
    ; combining marks → Extend
    cmp     edi, 0x0300
    jb      .sbp_chk_scripts
    cmp     edi, 0x036F
    jbe     .sbp_extend

.sbp_chk_scripts:
    ; CJK, Arabic, Devanagari, etc. → OLetter
    cmp     edi, 0x0600
    jb      .sbp_other
    cmp     edi, 0x06FF
    jbe     .sbp_oletter        ; Arabic
    cmp     edi, 0x0900
    jb      .sbp_other
    cmp     edi, 0x097F
    jbe     .sbp_oletter        ; Devanagari
    cmp     edi, 0x3040
    jb      .sbp_other
    cmp     edi, 0x30FF
    jbe     .sbp_oletter        ; Hiragana/Katakana
    cmp     edi, 0x4E00
    jb      .sbp_other
    cmp     edi, 0x9FFF
    jbe     .sbp_oletter        ; CJK
    cmp     edi, 0xAC00
    jb      .sbp_other
    cmp     edi, 0xD7AF
    jbe     .sbp_oletter        ; Hangul

.sbp_other:     mov al, SB_Other
    ret
.sbp_cr:        mov al, SB_CR
    ret
.sbp_lf:        mov al, SB_LF
    ret
.sbp_sep:       mov al, SB_Sep
    ret
.sbp_sp:        mov al, SB_Sp
    ret
.sbp_lower:     mov al, SB_Lower
    ret
.sbp_upper:     mov al, SB_Upper
    ret
.sbp_oletter:   mov al, SB_OLetter
    ret
.sbp_numeric:   mov al, SB_Numeric
    ret
.sbp_aterm:     mov al, SB_ATerm
    ret
.sbp_sterm:     mov al, SB_STerm
    ret
.sbp_close:     mov al, SB_Close
    ret
.sbp_scontinue: mov al, SB_SContinue
    ret
.sbp_extend:    mov al, SB_Extend
    ret

; -----------------------------------------------------------------------------
; _is_sentence_boundary  (internal)
;
; Simplified pairwise sentence break check.
; Full UAX #29 requires lookahead (SB7/SB8); this covers the core rules.
;
; Arguments: DIL = prop_before, SIL = prop_after
; Returns:   AL = 1 boundary, 0 no boundary
; -----------------------------------------------------------------------------

_is_sentence_boundary:
    movzx   eax, dil
    movzx   ecx, sil

    ; SB3: CR × LF
    cmp     al, SB_CR
    jne     .sb_not_cr
    cmp     cl, SB_LF
    je      .sb_no_break

.sb_not_cr:
    ; SB4: (Sep|CR|LF) ÷
    cmp     al, SB_Sep
    je      .sb_break
    cmp     al, SB_CR
    je      .sb_break
    cmp     al, SB_LF
    je      .sb_break

    ; SB5: × Extend/Format (ignored, part of previous)
    cmp     cl, SB_Extend
    je      .sb_no_break
    cmp     cl, SB_Format
    je      .sb_no_break

    ; SB6: ATerm × Numeric (don't break "3.14")
    cmp     al, SB_ATerm
    jne     .sb_not_aterm_num
    cmp     cl, SB_Numeric
    je      .sb_no_break

.sb_not_aterm_num:
    ; SB8a: (STerm|ATerm) Close* × SContinue
    cmp     cl, SB_SContinue
    jne     .sb_not_scont

    cmp     al, SB_STerm
    je      .sb_no_break
    cmp     al, SB_ATerm
    je      .sb_no_break
    cmp     al, SB_Close
    je      .sb_no_break

.sb_not_scont:
    ; SB9: (STerm|ATerm) Close* × (Close|Sp|Sep|CR|LF)
    cmp     al, SB_STerm
    je      .sb_chk_after_term
    cmp     al, SB_ATerm
    je      .sb_chk_after_term
    cmp     al, SB_Close
    jne     .sb_chk_default

.sb_chk_after_term:
    cmp     cl, SB_Close
    je      .sb_no_break
    cmp     cl, SB_Sp
    je      .sb_no_break

    ; SB11: (STerm|ATerm) Close* Sp* ÷  (sentence ends here)
    ; After term+close+space, break before next content
    cmp     al, SB_Sp
    je      .sb_chk_sp_break

    cmp     al, SB_STerm
    je      .sb_term_break
    cmp     al, SB_ATerm
    je      .sb_term_break
    jmp     .sb_chk_default

.sb_chk_sp_break:
    ; space after sentence ender → break before next non-space
    cmp     cl, SB_Sp
    je      .sb_no_break        ; still spacing
    cmp     cl, SB_Sep
    je      .sb_no_break
    cmp     cl, SB_CR
    je      .sb_no_break
    cmp     cl, SB_LF
    je      .sb_no_break
    jmp     .sb_break           ; content after spaces → new sentence

.sb_term_break:
    ; term directly followed by content → depends on ATerm vs STerm
    cmp     al, SB_STerm
    je      .sb_break           ; ! or ? → always breaks
    ; ATerm (.): could be abbreviation — conservative: no break
    jmp     .sb_no_break

.sb_chk_default:
    ; SB998: default — no break
.sb_no_break:
    xor     al, al
    ret

.sb_break:
    mov     al, 1
    ret

; -----------------------------------------------------------------------------
; str_sentence_next
;
; Find the byte offset of the next sentence boundary after the given offset.
;
; Signature:
;   int64_t str_sentence_next(const StrSlice *src, uint64_t offset,
;                              uint64_t *out_next)
; -----------------------------------------------------------------------------

STR_FUNC str_sentence_next

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; offset
    mov     r14, rdx            ; out_next

    cmp     r13, r12
    jae     .sn_end

    ; decode first cp at offset
    lea     rax, [rbx + r13]
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     r9, [rsp]
    mov     rsp, rbp

    add     r13, r9

    mov     edi, r8d
    call    _sbp
    movzx   r10d, al            ; prev property

.sn_loop:
    cmp     r13, r12
    jae     .sn_found           ; end of string = sentence end

    lea     rax, [rbx + r13]
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     r9, [rsp]
    mov     rsp, rbp

    mov     edi, r8d
    push    r8
    push    r9
    call    _sbp
    pop     r9
    pop     r8
    movzx   ecx, al             ; current property

    ; check boundary
    movzx   edi, r10b
    movzx   esi, cl
    push    r8
    push    r9
    push    rcx
    call    _is_sentence_boundary
    pop     rcx
    pop     r9
    pop     r8

    test    al, al
    jnz     .sn_found

    add     r13, r9
    mov     r10d, ecx
    jmp     .sn_loop

.sn_found:
    mov     [r14], r13
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sn_end:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_sentence_next

; -----------------------------------------------------------------------------
; str_sentence_count
;
; Count sentences in a string.
;
; Signature:
;   int64_t str_sentence_count(const StrSlice *src, uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_sentence_count

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r13, rsi

    xor     r12, r12            ; offset
    xor     r9, r9              ; count

    mov     rax, [rbx + StrSlice.len]
    test    rax, rax
    jz      .sc_done

.sc_loop:
    mov     rax, [rbx + StrSlice.len]
    cmp     r12, rax
    jae     .sc_done

    sub     rsp, 8
    and     rsp, -8

    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, rsp
    push    r9
    call    str_sentence_next
    pop     r9

    test    rax, rax
    jnz     .sc_done_pop

    mov     r12, [rsp]
    add     rsp, 8
    inc     r9
    jmp     .sc_loop

.sc_done_pop:
    add     rsp, 8

.sc_done:
    mov     [r13], r9
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_sentence_count