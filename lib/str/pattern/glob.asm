%ifndef GUARD_LIB_STR_PATTERN_GLOB_ASM
%define GUARD_LIB_STR_PATTERN_GLOB_ASM
; =============================================================================
; str/pattern/glob.asm
; Glob pattern matching: * ? [abc] [a-z] [^abc]
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Glob syntax:
;   *       — matches zero or more characters (not /)
;   **      — matches zero or more characters including /
;   ?       — matches exactly one character
;   [abc]   — matches any char in set
;   [a-z]   — matches char in range
;   [^abc]  — matches char NOT in set
;   \*      — literal *
;   \?      — literal ?
;   \[      — literal [
;
; Functions:
;   str_glob_match       — match string against pattern
;   str_glob_match_case  — case-sensitive variant (default)
;   str_glob_match_icase — case-insensitive variant
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_glob_match
;
; Match a string against a glob pattern.
;
; Signature:
;   int64_t str_glob_match(const StrSlice *pattern, const StrSlice *str)
;
; Returns:
;   RAX  = 1  match
;   RAX  = 0  no match
; -----------------------------------------------------------------------------

STR_FUNC str_glob_match

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; pattern ptr
    mov     r12, [rdi + StrSlice.len]   ; pattern len
    mov     r13, [rsi + StrSlice.ptr]   ; str ptr
    mov     r14, [rsi + StrSlice.len]   ; str len

    xor     r9, r9              ; pattern index
    xor     r10, r10            ; str index

    ; star_pat = -1 (no star encountered yet)
    ; star_str = -1
    mov     r11, -1             ; star_pat
    mov     r15, -1             ; star_str

.gm_loop:
    ; if string exhausted, check if remaining pattern is all *
    cmp     r10, r14
    jae     .gm_str_done

    cmp     r9, r12
    jae     .gm_no_match        ; pattern exhausted but string not

    movzx   eax, byte [rbx + r9]    ; pattern char
    movzx   ecx, byte [r13 + r10]   ; str char

    ; check backslash escape in pattern
    cmp     al, 0x5C
    je      .gm_escaped

    ; check special chars
    cmp     al, '*'
    je      .gm_star

    cmp     al, '?'
    je      .gm_question

    cmp     al, '['
    je      .gm_bracket

    ; literal match
    cmp     al, cl
    je      .gm_advance

    ; mismatch — try to backtrack to last *
    jmp     .gm_backtrack

.gm_advance:
    inc     r9
    inc     r10
    jmp     .gm_loop

.gm_escaped:
    ; \* \? \[ → literal char
    inc     r9
    cmp     r9, r12
    jae     .gm_no_match

    movzx   eax, byte [rbx + r9]
    cmp     al, cl
    jne     .gm_backtrack

    inc     r9
    inc     r10
    jmp     .gm_loop

.gm_backtrack:
    cmp     r11, -1
    je      .gm_no_match

    ; Check if single * (rbx[r11 + 1] != '*')
    mov     rax, r11
    inc     rax
    cmp     rax, r12
    jae     .gm_backtrack_single
    movzx   edx, byte [rbx + rax]
    cmp     dl, '*'
    je      .gm_backtrack_globstar

.gm_backtrack_single:
    cmp     r15, r14
    jae     .gm_backtrack_globstar
    movzx   edx, byte [r13 + r15]
    cmp     dl, '/'
    je      .gm_no_match        ; single * cannot cross '/'

.gm_backtrack_globstar:
    ; calculate correct pattern advance
    mov     rax, r11
    inc     rax
    cmp     rax, r12
    jae     .gm_bt_single_adv
    movzx   edx, byte [rbx + rax]
    cmp     dl, '*'
    je      .gm_bt_double_adv
.gm_bt_single_adv:
    mov     r9, r11
    inc     r9
    jmp     .gm_bt_continue
.gm_bt_double_adv:
    mov     r9, r11
    add     r9, 2
.gm_bt_continue:
    inc     r15
    mov     r10, r15
    jmp     .gm_loop

.gm_star:
    mov     r11, r9             ; star_pat
    mov     r15, r10            ; star_str
    
    ; check if globstar (**)
    lea     rax, [r9 + 1]
    cmp     rax, r12
    jae     .gm_single_star
    movzx   edx, byte [rbx + rax]
    cmp     dl, '*'
    jne     .gm_single_star

    add     r9, 2               ; advance past both *
    jmp     .gm_loop

.gm_single_star:
    inc     r9                  ; advance past single *
    jmp     .gm_loop

.gm_question:
    ; ? matches any single char (but not / unless **)
    ; simple version: matches any char
    inc     r9
    inc     r10
    jmp     .gm_loop

.gm_bracket:
    ; [set] matching
    inc     r9                  ; skip [

    ; check for negation
    xor     r8d, r8d            ; negate = 0
    cmp     r9, r12
    jae     .gm_no_match

    movzx   edx, byte [rbx + r9]
    cmp     dl, '^'
    jne     .gm_bracket_scan
    mov     r8d, 1
    inc     r9

.gm_bracket_scan:
    ; scan until ] or end
    xor     esi, esi            ; matched_in_set = 0

.gm_bracket_loop:
    cmp     r9, r12
    jae     .gm_no_match        ; unclosed [

    movzx   edx, byte [rbx + r9]
    cmp     dl, ']'
    je      .gm_bracket_done

    ; check for range a-z
    lea     rax, [r9 + 1]
    cmp     rax, r12
    jae     .gm_bracket_single

    movzx   eax, byte [rbx + r9 + 1]
    cmp     al, '-'
    jne     .gm_bracket_single

    lea     rax, [r9 + 2]
    cmp     rax, r12
    jae     .gm_bracket_single

    movzx   eax, byte [rbx + r9 + 2]
    cmp     al, ']'
    je      .gm_bracket_single  ; e.g. [a-] — treat - as literal

    ; range match: dl..al
    cmp     cl, dl
    jb      .gm_bracket_no_range
    cmp     cl, al
    ja      .gm_bracket_no_range
    mov     esi, 1              ; matched

.gm_bracket_no_range:
    add     r9, 3               ; skip a-z
    jmp     .gm_bracket_loop

.gm_bracket_single:
    cmp     cl, dl
    jne     .gm_bracket_no_single
    mov     esi, 1

.gm_bracket_no_single:
    inc     r9
    jmp     .gm_bracket_loop

.gm_bracket_done:
    inc     r9                  ; skip ]

    ; match if: (matched_in_set && !negate) || (!matched_in_set && negate)
    mov     eax, esi
    xor     eax, r8d            ; matched XOR negate
    test    eax, eax
    jz      .gm_bracket_backtrack

    ; matched: advance string index r10 by 1 and continue matching
    inc     r10
    jmp     .gm_loop

.gm_bracket_backtrack:
    cmp     r11, -1
    je      .gm_no_match
    mov     r9, r11
    inc     r9
    inc     r15
    mov     r10, r15
    jmp     .gm_loop

.gm_str_done:
    ; string exhausted — pattern must be exhausted or all *
.gm_pat_check:
    cmp     r9, r12
    jae     .gm_match

    movzx   eax, byte [rbx + r9]
    cmp     al, '*'
    jne     .gm_no_match
    inc     r9
    jmp     .gm_pat_check

.gm_match:
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.gm_no_match:
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

STR_ENDFUNC str_glob_match

; -----------------------------------------------------------------------------
; str_glob_match_icase
;
; Case-insensitive glob matching.
; Same as str_glob_match but folds both chars to lowercase before comparing.
; -----------------------------------------------------------------------------

STR_FUNC str_glob_match_icase

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, [rsi + StrSlice.ptr]
    mov     r14, [rsi + StrSlice.len]

    xor     r9, r9
    xor     r10, r10
    mov     r11, -1
    mov     r15, -1

.gmi_loop:
    cmp     r10, r14
    jae     .gmi_str_done

    cmp     r9, r12
    jae     .gmi_no_match

    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [r13 + r10]

    ; fold to lowercase
    cmp     al, 'A'
    jb      .gmi_fold_c
    cmp     al, 'Z'
    ja      .gmi_fold_c
    or      al, 0x20
.gmi_fold_c:
    cmp     cl, 'A'
    jb      .gmi_check_spec
    cmp     cl, 'Z'
    ja      .gmi_check_spec
    or      cl, 0x20

.gmi_check_spec:
    cmp     al, '*'
    je      .gmi_star
    cmp     al, '?'
    je      .gmi_question

    cmp     al, cl
    je      .gmi_advance_both

    jmp     .gmi_backtrack

.gmi_advance_both:
    inc     r9
    inc     r10
    jmp     .gmi_loop

.gmi_backtrack:
    cmp     r11, -1
    je      .gmi_no_match

    ; Check if single * (rbx[r11 + 1] != '*')
    mov     rax, r11
    inc     rax
    cmp     rax, r12
    jae     .gmi_backtrack_single
    movzx   edx, byte [rbx + rax]
    cmp     dl, '*'
    je      .gmi_backtrack_globstar

.gmi_backtrack_single:
    cmp     r15, r14
    jae     .gmi_backtrack_globstar
    movzx   edx, byte [r13 + r15]
    cmp     dl, '/'
    je      .gmi_no_match        ; single * cannot cross '/'

.gmi_backtrack_globstar:
    ; calculate correct pattern advance
    mov     rax, r11
    inc     rax
    cmp     rax, r12
    jae     .gmi_bt_single_adv
    movzx   edx, byte [rbx + rax]
    cmp     dl, '*'
    je      .gmi_bt_double_adv
.gmi_bt_single_adv:
    mov     r9, r11
    inc     r9
    jmp     .gmi_bt_continue
.gmi_bt_double_adv:
    mov     r9, r11
    add     r9, 2
.gmi_bt_continue:
    inc     r15
    mov     r10, r15
    jmp     .gmi_loop

.gmi_star:
    mov     r11, r9             ; star_pat
    mov     r15, r10            ; star_str
    
    ; check if globstar (**)
    lea     rax, [r9 + 1]
    cmp     rax, r12
    jae     .gmi_single_star
    movzx   edx, byte [rbx + rax]
    cmp     dl, '*'
    jne     .gmi_single_star

    add     r9, 2               ; advance past both *
    jmp     .gmi_loop

.gmi_single_star:
    inc     r9                  ; advance past single *
    jmp     .gmi_loop

.gmi_question:
    inc     r9
    inc     r10
    jmp     .gmi_loop

.gmi_str_done:
.gmi_pat_check:
    cmp     r9, r12
    jae     .gmi_match
    movzx   eax, byte [rbx + r9]
    cmp     al, '*'
    jne     .gmi_no_match
    inc     r9
    jmp     .gmi_pat_check

.gmi_match:
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.gmi_no_match:
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

STR_ENDFUNC str_glob_match_icase
%endif ; GUARD_LIB_STR_PATTERN_GLOB_ASM
