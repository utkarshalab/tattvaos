; =============================================================================
; str/unicode/linebreak.asm
; Line break opportunity detection (UAX #14).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm                  (str_utf8_decode_unchecked)
;   unicode/tables/break_table.s     (line break property data)
;
; -----------------------------------------------------------------------------
; Line breaking determines where text can wrap to the next line.
; Used by: text layout engines, word wrap, terminal output, typesetting.
;
; Each position between characters is classified as:
;   MANDATORY  — must break here (after newline)
;   ALLOWED    — may break here (e.g. after space, hyphen)
;   PROHIBITED — must NOT break here (e.g. inside a word, before closing paren)
;
; Line_Break property values (subset of UAX #14's ~40 classes):
;   BK (mandatory break), CR, LF, NL, SP (space), ZW (zero-width space),
;   WJ (word joiner), GL (glue/non-breaking), BA (break after),
;   BB (break before), HY (hyphen), CM (combining), AL (alphabetic),
;   NU (numeric), OP (open punct), CL (close punct), QU (quotation),
;   IS (infix separator), SY (symbol), ID (ideographic), B2 (break both)
;
; Functions:
;   str_linebreak_next        — find next line break opportunity
;   str_linebreak_class       — get line break class for codepoint
;   str_linebreak_wrap        — compute wrap positions for a given width
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

; Line break classes (subset)
LB_XX   equ 0      ; unknown
LB_BK   equ 1      ; mandatory break
LB_CR   equ 2      ; carriage return
LB_LF   equ 3      ; line feed
LB_NL   equ 4      ; next line
LB_SP   equ 5      ; space
LB_ZW   equ 6      ; zero-width space
LB_WJ   equ 7      ; word joiner
LB_GL   equ 8      ; glue (non-breaking)
LB_BA   equ 9      ; break after
LB_BB   equ 10     ; break before
LB_HY   equ 11     ; hyphen
LB_CM   equ 12     ; combining mark
LB_AL   equ 13     ; alphabetic
LB_NU   equ 14     ; numeric
LB_OP   equ 15     ; open punctuation
LB_CL   equ 16     ; close punctuation
LB_QU   equ 17     ; quotation
LB_IS   equ 18     ; infix numeric separator
LB_SY   equ 19     ; symbol (slash)
LB_ID   equ 20     ; ideographic
LB_B2   equ 21     ; break opportunity before and after
LB_EX   equ 22     ; exclamation/interrogation

; Break action results
LB_BREAK_MANDATORY  equ 2
LB_BREAK_ALLOWED    equ 1
LB_BREAK_PROHIBITED equ 0

extern _ucd_lb_table        ; cp → line break class

section .text

; -----------------------------------------------------------------------------
; str_linebreak_class
;
; Get the line break class of a codepoint.
;
; Signature:
;   uint8_t str_linebreak_class(uint32_t cp)
;
; Arguments: EDI = codepoint
; Returns:   AL = LB_* class
; -----------------------------------------------------------------------------

STR_FUNC str_linebreak_class

    ; mandatory break chars
    cmp     edi, 0x0A
    je      .lbc_lf
    cmp     edi, 0x0D
    je      .lbc_cr
    cmp     edi, 0x0B
    je      .lbc_bk
    cmp     edi, 0x0C
    je      .lbc_bk
    cmp     edi, 0x85
    je      .lbc_nl
    cmp     edi, 0x2028
    je      .lbc_bk
    cmp     edi, 0x2029
    je      .lbc_bk

    ; space
    cmp     edi, 0x20
    je      .lbc_sp

    ; zero-width space
    cmp     edi, 0x200B
    je      .lbc_zw

    ; word joiner
    cmp     edi, 0x2060
    je      .lbc_wj
    cmp     edi, 0xFEFF
    je      .lbc_wj

    ; non-breaking space → glue
    cmp     edi, 0xA0
    je      .lbc_gl

    ; hyphen
    cmp     edi, '-'
    je      .lbc_hy

    ; ASCII letters → AL
    cmp     edi, 'A'
    jb      .lbc_chk_digit
    cmp     edi, 'Z'
    jbe     .lbc_al
    cmp     edi, 'a'
    jb      .lbc_chk_digit
    cmp     edi, 'z'
    jbe     .lbc_al

.lbc_chk_digit:
    cmp     edi, '0'
    jb      .lbc_chk_punct
    cmp     edi, '9'
    jbe     .lbc_nu

.lbc_chk_punct:
    ; open punctuation
    cmp     edi, '('
    je      .lbc_op
    cmp     edi, '['
    je      .lbc_op
    cmp     edi, '{'
    je      .lbc_op
    ; close punctuation
    cmp     edi, ')'
    je      .lbc_cl
    cmp     edi, ']'
    je      .lbc_cl
    cmp     edi, '}'
    je      .lbc_cl
    ; quotation
    cmp     edi, 0x22
    je      .lbc_qu
    cmp     edi, 0x27
    je      .lbc_qu
    ; infix separator
    cmp     edi, ','
    je      .lbc_is
    cmp     edi, '.'
    je      .lbc_is
    ; symbol (slash)
    cmp     edi, '/'
    je      .lbc_sy
    ; exclamation/question
    cmp     edi, '!'
    je      .lbc_ex
    cmp     edi, '?'
    je      .lbc_ex

    ; combining marks
    cmp     edi, 0x0300
    jb      .lbc_chk_ideo
    cmp     edi, 0x036F
    jbe     .lbc_cm

.lbc_chk_ideo:
    ; CJK ideographs → ID (each can break)
    cmp     edi, 0x4E00
    jb      .lbc_chk_latin
    cmp     edi, 0x9FFF
    jbe     .lbc_id
    ; Hiragana/Katakana
    cmp     edi, 0x3040
    jb      .lbc_chk_latin
    cmp     edi, 0x30FF
    jbe     .lbc_id

.lbc_chk_latin:
    ; Latin-1 accented letters → AL
    cmp     edi, 0xC0
    jb      .lbc_al             ; default printable → AL
    cmp     edi, 0x024F
    jbe     .lbc_al

    jmp     .lbc_al             ; default: alphabetic

.lbc_lf: mov al, LB_LF
    ret
.lbc_cr: mov al, LB_CR
    ret
.lbc_bk: mov al, LB_BK
    ret
.lbc_nl: mov al, LB_NL
    ret
.lbc_sp: mov al, LB_SP
    ret
.lbc_zw: mov al, LB_ZW
    ret
.lbc_wj: mov al, LB_WJ
    ret
.lbc_gl: mov al, LB_GL
    ret
.lbc_hy: mov al, LB_HY
    ret
.lbc_al: mov al, LB_AL
    ret
.lbc_nu: mov al, LB_NU
    ret
.lbc_op: mov al, LB_OP
    ret
.lbc_cl: mov al, LB_CL
    ret
.lbc_qu: mov al, LB_QU
    ret
.lbc_is: mov al, LB_IS
    ret
.lbc_sy: mov al, LB_SY
    ret
.lbc_id: mov al, LB_ID
    ret
.lbc_cm: mov al, LB_CM
    ret
.lbc_ex: mov al, LB_EX
    ret

STR_ENDFUNC str_linebreak_class

; -----------------------------------------------------------------------------
; _lb_pair_action  (internal)
;
; Determine the break action between two line break classes.
; Implements the UAX #14 pair table (key rules).
;
; Arguments: DIL = class_a (before), SIL = class_b (after)
; Returns:   AL = LB_BREAK_MANDATORY / ALLOWED / PROHIBITED
; -----------------------------------------------------------------------------

_lb_pair_action:
    movzx   eax, dil
    movzx   ecx, sil

    ; LB4: BK !  (mandatory break after)
    cmp     al, LB_BK
    je      .lb_mandatory
    cmp     al, LB_NL
    je      .lb_mandatory

    ; LB5: CR × LF, CR !, LF !, NL !
    cmp     al, LB_CR
    jne     .lb_not_cr
    cmp     cl, LB_LF
    je      .lb_prohibited      ; CR × LF
    jmp     .lb_mandatory       ; CR ! otherwise

.lb_not_cr:
    cmp     al, LB_LF
    je      .lb_mandatory

    ; LB6: × (BK|CR|LF|NL)  — don't break before mandatory break
    cmp     cl, LB_BK
    je      .lb_prohibited
    cmp     cl, LB_CR
    je      .lb_prohibited
    cmp     cl, LB_LF
    je      .lb_prohibited
    cmp     cl, LB_NL
    je      .lb_prohibited

    ; LB7: × SP, × ZW  (don't break before space or ZWSP)
    cmp     cl, LB_SP
    je      .lb_prohibited
    cmp     cl, LB_ZW
    je      .lb_prohibited

    ; LB8: ZW ÷  (break after zero-width space)
    cmp     al, LB_ZW
    je      .lb_allowed

    ; LB11: × WJ, WJ ×  (word joiner: no break either side)
    cmp     cl, LB_WJ
    je      .lb_prohibited
    cmp     al, LB_WJ
    je      .lb_prohibited

    ; LB12: GL ×  (glue: no break after)
    cmp     al, LB_GL
    je      .lb_prohibited

    ; LB13: × (CL|CP|EX|IS|SY)  — no break before these
    cmp     cl, LB_CL
    je      .lb_prohibited
    cmp     cl, LB_EX
    je      .lb_prohibited
    cmp     cl, LB_IS
    je      .lb_prohibited
    cmp     cl, LB_SY
    je      .lb_prohibited

    ; LB14: OP SP* ×  (no break after open punctuation)
    cmp     al, LB_OP
    je      .lb_prohibited

    ; LB18: SP ÷  (break after space)
    cmp     al, LB_SP
    je      .lb_allowed

    ; LB21: × BA, × HY, BB ×  (breaks around hyphens)
    cmp     al, LB_BB
    je      .lb_prohibited
    cmp     cl, LB_BA
    je      .lb_prohibited
    cmp     cl, LB_HY
    je      .lb_prohibited

    ; LB23: (AL|HL) × NU, NU × (AL|HL)  — no break between letters & numbers
    cmp     al, LB_AL
    jne     .lb_not_al_nu
    cmp     cl, LB_NU
    je      .lb_prohibited
.lb_not_al_nu:
    cmp     al, LB_NU
    jne     .lb_not_nu_al
    cmp     cl, LB_AL
    je      .lb_prohibited
.lb_not_nu_al:

    ; LB26/28: keep letters together (AL × AL)
    cmp     al, LB_AL
    jne     .lb_not_al_al
    cmp     cl, LB_AL
    je      .lb_prohibited
.lb_not_al_al:

    ; LB25: numeric sequences (NU × NU)
    cmp     al, LB_NU
    jne     .lb_not_nu_nu
    cmp     cl, LB_NU
    je      .lb_prohibited
.lb_not_nu_nu:

    ; CM attaches to previous (× CM)
    cmp     cl, LB_CM
    je      .lb_prohibited

    ; LB28a/30: ideographs can break (ID ÷ ID)
    cmp     al, LB_ID
    je      .lb_allowed

    ; LB31: default — allow break (ALL ÷ ALL)
.lb_allowed:
    mov     al, LB_BREAK_ALLOWED
    ret

.lb_mandatory:
    mov     al, LB_BREAK_MANDATORY
    ret

.lb_prohibited:
    mov     al, LB_BREAK_PROHIBITED
    ret

; -----------------------------------------------------------------------------
; str_linebreak_next
;
; Find the next line break opportunity after the given offset.
;
; Signature:
;   int64_t str_linebreak_next(const StrSlice *src, uint64_t offset,
;                               uint64_t *out_pos, uint8_t *out_mandatory)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — current byte offset
;   RDX  — pointer to uint64_t for break position
;   RCX  — pointer to uint8_t: 1 if mandatory, 0 if optional (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_ITER_END
; -----------------------------------------------------------------------------

STR_FUNC str_linebreak_next

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; offset
    mov     r14, rdx            ; out_pos
    mov     r15, rcx            ; out_mandatory

    cmp     r13, r12
    jae     .ln_end

    ; decode first cp
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
    call    str_linebreak_class
    movzx   r10d, al            ; prev class

.ln_loop:
    cmp     r13, r12
    jae     .ln_eof

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
    call    str_linebreak_class
    pop     r9
    pop     r8
    movzx   ecx, al             ; current class

    ; get break action
    movzx   edi, r10b
    movzx   esi, cl
    push    r8
    push    r9
    push    rcx
    call    _lb_pair_action
    pop     rcx
    pop     r9
    pop     r8

    cmp     al, LB_BREAK_PROHIBITED
    je      .ln_no_break

    ; break found (allowed or mandatory)
    mov     [r14], r13

    test    r15, r15
    jz      .ln_ok

    ; mandatory?
    cmp     al, LB_BREAK_MANDATORY
    sete    al
    mov     [r15], al

.ln_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ln_no_break:
    add     r13, r9
    mov     r10d, ecx
    jmp     .ln_loop

.ln_eof:
    ; end of string is always a break opportunity
    mov     [r14], r13
    test    r15, r15
    jz      .ln_ok2
    mov     byte [r15], 1       ; mandatory at end
.ln_ok2:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ln_end:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_linebreak_next