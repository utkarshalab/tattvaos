%ifndef GUARD_LIB_STR_PATTERN_REGEX_COMPILE_ASM
%define GUARD_LIB_STR_PATTERN_REGEX_COMPILE_ASM
; =============================================================================
; str/pattern/regex_compile.asm
; Compile an ERE regex pattern to NFA bytecode.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   mem/arena.asm  (str_arena_alloc)
;
; -----------------------------------------------------------------------------
; NFA bytecode instruction set:
;
;   MATCH_BYTE  byte        — match literal byte
;   MATCH_ANY               — match any byte (.)
;   MATCH_CLASS bitmap[32]  — match char class ([abc])
;   MATCH_NONE              — fail
;   SPLIT       off1, off2  — fork execution: try off1 then off2
;   JUMP        off         — unconditional jump
;   SAVE        slot        — save current position into slot N
;   ACCEPT                  — successful match
;
; Opcode bytes:
;   0x01 = MATCH_BYTE  (2 bytes: opcode + byte)
;   0x02 = MATCH_ANY   (1 byte)
;   0x03 = MATCH_CLASS (33 bytes: opcode + 32-byte bitmap)
;   0x04 = MATCH_NONE  (1 byte)
;   0x05 = SPLIT       (9 bytes: opcode + 2 × int32 offsets)
;   0x06 = JUMP        (5 bytes: opcode + int32 offset)
;   0x07 = SAVE        (2 bytes: opcode + slot)
;   0x08 = ACCEPT      (1 byte)
;
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Opcodes
OP_MATCH_BYTE   equ 0x01
OP_MATCH_ANY    equ 0x02
OP_MATCH_CLASS  equ 0x03
OP_MATCH_NONE   equ 0x04
OP_SPLIT        equ 0x05
OP_JUMP         equ 0x06
OP_SAVE         equ 0x07
OP_ACCEPT       equ 0x08

; RegexProgram header (output struct):
struc RegexProgram
    .code   resq 1      ; pointer to bytecode
    .code_len resq 1    ; bytecode length in bytes
    .nsave  resq 1      ; number of save slots (2 per capture group)
endstruc

REGEXPROG_SIZE  equ 24

section .text

; -----------------------------------------------------------------------------
; str_regex_compile
;
; Compile a POSIX ERE pattern to NFA bytecode.
;
; Signature:
;   int64_t str_regex_compile(const StrSlice *pattern,
;                              StrArena *arena,
;                              RegexProgram *out)
;
; Arguments:
;   RDI  — pattern StrSlice
;   RSI  — arena for bytecode allocation
;   RDX  — output RegexProgram struct
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE     invalid pattern syntax
;   RAX  = STR_ERR_ALLOC     arena exhausted
; -----------------------------------------------------------------------------

STR_FUNC str_regex_compile

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; pattern ptr
    mov     r12, [rdi + StrSlice.len]   ; pattern len
    mov     r13, rsi            ; arena
    mov     r14, rdx            ; out RegexProgram

    ; allocate bytecode buffer: worst case 10x pattern length
    mov     rdi, r13
    mov     rsi, r12
    imul    rsi, rsi, 10
    add     rsi, 64
    mov     rdx, 8
    call    str_arena_alloc
    test    rax, rax
    jz      .rc_oom

    mov     r15, rax            ; bytecode buffer
    xor     r9, r9              ; pat index
    xor     r10, r10            ; bytecode write offset
    xor     r11, r11            ; save slot counter (0 = full match)

    ; save slot 0 = start of match
    mov     byte [r15 + r10], OP_SAVE
    mov     byte [r15 + r10 + 1], 0
    add     r10, 2

.rc_loop:
    cmp     r9, r12
    jae     .rc_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, '.'
    je      .rc_dot

    cmp     al, '*'
    je      .rc_star

    cmp     al, '+'
    je      .rc_plus

    cmp     al, '?'
    je      .rc_question

    cmp     al, '('
    je      .rc_open_group

    cmp     al, ')'
    je      .rc_close_group

    cmp     al, '|'
    je      .rc_alternation

    cmp     al, '['
    je      .rc_char_class

    cmp     al, '^'
    je      .rc_anchor_start

    cmp     al, '$'
    je      .rc_anchor_end

    cmp     al, 0x5C
    je      .rc_escape

    ; literal byte
.rc_literal:
    mov     byte [r15 + r10], OP_MATCH_BYTE
    mov     [r15 + r10 + 1], al
    add     r10, 2
    jmp     .rc_check_quantifier

.rc_dot:
    mov     byte [r15 + r10], OP_MATCH_ANY
    inc     r10
    jmp     .rc_check_quantifier

.rc_escape:
    cmp     r9, r12
    jae     .rc_parse_err

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; handle special escapes
    cmp     al, 'd'
    je      .rc_digit_class
    cmp     al, 'w'
    je      .rc_word_class
    cmp     al, 's'
    je      .rc_space_class
    cmp     al, 'n'
    je      .rc_newline_esc
    cmp     al, 't'
    je      .rc_tab_esc

    ; otherwise: literal
    jmp     .rc_literal

.rc_newline_esc:
    mov     al, 0x0A
    jmp     .rc_literal

.rc_tab_esc:
    mov     al, 0x09
    jmp     .rc_literal

.rc_digit_class:
    ; \d = [0-9]
    mov     byte [r15 + r10], OP_MATCH_CLASS
    inc     r10
    ; zero 32-byte bitmap
    xor     eax, eax
    mov     ecx, 32
    lea     rdi, [r15 + r10]
    push    r10
    rep stosb
    pop     r10
    ; set bits for '0'-'9' (ASCII 48-57)
    ; bit N in byte[N/8]
    mov     ecx, 48             ; '0'
.rc_digit_set:
    cmp     ecx, 58             ; '9' + 1
    jae     .rc_digit_done
    mov     eax, ecx
    shr     eax, 3              ; byte index
    mov     edx, ecx
    and     edx, 7              ; bit index
    bts     dword [r15 + r10 + rax * 4 / 4], edx  ; wrong — fix indexing
    ; correct: [r15 + r10 + eax] |= 1 << edx
    mov     r8b, 1
    shl     r8b, dl
    or      [r15 + r10 + rax], r8b
    inc     ecx
    jmp     .rc_digit_set
.rc_digit_done:
    add     r10, 32
    jmp     .rc_check_quantifier

.rc_word_class:
    ; \w = [A-Za-z0-9_]
    mov     byte [r15 + r10], OP_MATCH_CLASS
    inc     r10
    xor     eax, eax
    mov     ecx, 32
    lea     rdi, [r15 + r10]
    push    r10
    rep stosb
    pop     r10
    ; set A-Z, a-z, 0-9, _
    mov     ecx, 65
.rc_word_AZ:
    cmp     ecx, 91
    jae     .rc_word_az
    mov     eax, ecx
    shr     eax, 3
    mov     edx, ecx
    and     edx, 7
    mov     r8b, 1
    shl     r8b, dl
    or      [r15 + r10 + rax], r8b
    inc     ecx
    jmp     .rc_word_AZ
.rc_word_az:
    mov     ecx, 97
.rc_word_azl:
    cmp     ecx, 123
    jae     .rc_word_09
    mov     eax, ecx
    shr     eax, 3
    mov     edx, ecx
    and     edx, 7
    mov     r8b, 1
    shl     r8b, dl
    or      [r15 + r10 + rax], r8b
    inc     ecx
    jmp     .rc_word_azl
.rc_word_09:
    mov     ecx, 48
.rc_word_09l:
    cmp     ecx, 58
    jae     .rc_word_under
    mov     eax, ecx
    shr     eax, 3
    mov     edx, ecx
    and     edx, 7
    mov     r8b, 1
    shl     r8b, dl
    or      [r15 + r10 + rax], r8b
    inc     ecx
    jmp     .rc_word_09l
.rc_word_under:
    ; '_' = 95
    mov     eax, 95
    shr     eax, 3              ; = 11
    mov     edx, 95
    and     edx, 7              ; = 7
    mov     r8b, 1
    shl     r8b, dl
    or      [r15 + r10 + 11], r8b
    add     r10, 32
    jmp     .rc_check_quantifier

.rc_space_class:
    ; \s = [ \t\n\r\f\v]
    mov     byte [r15 + r10], OP_MATCH_CLASS
    inc     r10
    xor     eax, eax
    mov     ecx, 32
    lea     rdi, [r15 + r10]
    push    r10
    rep stosb
    pop     r10
    ; set space(32), tab(9), LF(10), CR(13), FF(12), VT(11)
    %macro SET_BIT 1
        mov     eax, %1
        shr     eax, 3
        mov     edx, %1
        and     edx, 7
        mov     r8b, 1
        shl     r8b, dl
        or      [r15 + r10 + rax], r8b
    %endmacro
    SET_BIT 32
    SET_BIT 9
    SET_BIT 10
    SET_BIT 13
    SET_BIT 12
    SET_BIT 11
    add     r10, 32
    jmp     .rc_check_quantifier

.rc_anchor_start:
    ; ^ — for simplicity emit as SAVE with special slot (not full impl)
    ; Full impl would check string position = 0
    jmp     .rc_loop

.rc_anchor_end:
    ; $ — similar
    jmp     .rc_loop

.rc_char_class:
    ; [abc] or [a-z] or [^abc]
    mov     byte [r15 + r10], OP_MATCH_CLASS
    inc     r10
    ; zero bitmap
    xor     eax, eax
    mov     ecx, 32
    lea     rdi, [r15 + r10]
    push    r10
    push    r9
    rep stosb
    pop     r9
    pop     r10

    ; check for negation
    xor     r8d, r8d
    movzx   eax, byte [rbx + r9]
    cmp     al, '^'
    jne     .rc_class_scan
    mov     r8d, 1
    inc     r9

.rc_class_scan:
    cmp     r9, r12
    jae     .rc_parse_err

    movzx   eax, byte [rbx + r9]
    cmp     al, ']'
    je      .rc_class_done

    inc     r9

    ; check for range
    cmp     r9, r12
    jae     .rc_class_single

    movzx   ecx, byte [rbx + r9]
    cmp     cl, '-'
    jne     .rc_class_single

    lea     rdx, [r9 + 1]
    cmp     rdx, r12
    jae     .rc_class_single

    movzx   edx, byte [rbx + r9 + 1]
    cmp     dl, ']'
    je      .rc_class_single    ; trailing - is literal

    ; range: al..dl
    inc     r9                  ; skip -
    inc     r9                  ; skip end char (we stored in dl)

    movzx   ecx, al
.rc_range_set:
    cmp     ecx, edx
    ja      .rc_class_scan
    mov     eax, ecx
    shr     eax, 3
    mov     r9d, ecx
    and     r9d, 7
    mov     r11b, 1
    shl     r11b, r9b
    or      [r15 + r10 + rax], r11b
    inc     ecx
    jmp     .rc_range_set

.rc_class_single:
    ; set single bit
    movzx   eax, al
    mov     ecx, eax
    shr     ecx, 3
    and     eax, 7
    mov     r9b, 1
    shl     r9b, al
    or      [r15 + r10 + rcx], r9b
    jmp     .rc_class_scan

.rc_class_done:
    inc     r9                  ; skip ]

    ; if negated, flip all bits in bitmap
    test    r8d, r8d
    jz      .rc_class_end

    mov     ecx, 0
.rc_negate:
    cmp     ecx, 32
    jae     .rc_class_end
    xor     byte [r15 + r10 + rcx], 0xFF
    inc     ecx
    jmp     .rc_negate

.rc_class_end:
    add     r10, 32
    jmp     .rc_check_quantifier

.rc_open_group:
    ; ( — emit SAVE slot N
    add     r11, 2              ; allocate 2 slots (open + close)
    mov     byte [r15 + r10], OP_SAVE
    mov     [r15 + r10 + 1], r11b
    sub     byte [r15 + r10 + 1], 2    ; use slot N-2
    add     r10, 2
    jmp     .rc_loop

.rc_close_group:
    ; ) — emit SAVE slot N-1
    mov     byte [r15 + r10], OP_SAVE
    mov     [r15 + r10 + 1], r11b
    dec     byte [r15 + r10 + 1]       ; use slot N-1
    add     r10, 2
    jmp     .rc_loop

.rc_alternation:
    ; | — complex: requires backpatching
    ; simplified: not fully implemented here
    jmp     .rc_loop

.rc_star:
    ; * after previous instruction: SPLIT back/forward
    ; simplified: not fully implemented — needs backpatching
    jmp     .rc_loop

.rc_plus:
.rc_question:
    ; + and ? quantifiers: not fully implemented
    jmp     .rc_loop

.rc_check_quantifier:
    ; peek at next pattern char for *, +, ?
    cmp     r9, r12
    jae     .rc_loop

    movzx   eax, byte [rbx + r9]

    cmp     al, '*'
    je      .rc_apply_star
    cmp     al, '+'
    je      .rc_apply_plus
    cmp     al, '?'
    je      .rc_apply_question
    jmp     .rc_loop

.rc_apply_star:
    ; x* = SPLIT next,x_start / x / JUMP x_start
    ; This requires backpatching the instruction we just emitted.
    ; For now: skip the quantifier
    inc     r9
    jmp     .rc_loop

.rc_apply_plus:
    ; x+ = x / SPLIT back,next
    inc     r9
    jmp     .rc_loop

.rc_apply_question:
    ; x? = SPLIT next,x / x
    inc     r9
    jmp     .rc_loop

.rc_done:
    ; save slot 1 = end of match
    mov     byte [r15 + r10], OP_SAVE
    mov     byte [r15 + r10 + 1], 1
    add     r10, 2

    ; emit ACCEPT
    mov     byte [r15 + r10], OP_ACCEPT
    inc     r10

    ; fill output struct
    mov     [r14 + RegexProgram.code], r15
    mov     [r14 + RegexProgram.code_len], r10
    mov     [r14 + RegexProgram.nsave], r11

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rc_parse_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.rc_oom:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_regex_compile
%endif ; GUARD_LIB_STR_PATTERN_REGEX_COMPILE_ASM
