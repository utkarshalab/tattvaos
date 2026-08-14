%ifndef GUARD_LIB_STR_PATTERN_WILDCARD_ASM
%define GUARD_LIB_STR_PATTERN_WILDCARD_ASM
; =============================================================================
; str/pattern/wildcard.asm
; Simple * wildcard matching (no ? or character classes).
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
; Wildcard patterns:
;   *       — matches any sequence of characters (including empty)
;   prefix* — starts-with prefix
;   *suffix — ends-with suffix
;   *mid*   — contains mid
;   a*b     — starts with a, ends with b
;
; This is a simpler, faster alternative to glob when ? and [] are not needed.
;
; Functions:
;   str_wildcard_match       — match with * patterns
;   str_wildcard_match_icase — case-insensitive variant
;   str_wildcard_split       — split pattern into segments by *
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_wildcard_match
;
; Match a string against a wildcard pattern (only * is special).
;
; Signature:
;   int64_t str_wildcard_match(const StrSlice *pattern, const StrSlice *str)
;
; Returns:
;   RAX  = 1  match
;   RAX  = 0  no match
; -----------------------------------------------------------------------------

STR_FUNC str_wildcard_match

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; pat
    mov     r12, [rdi + StrSlice.len]   ; pat_len
    mov     r13, [rsi + StrSlice.ptr]   ; str
    mov     r14, [rsi + StrSlice.len]   ; str_len

    ; split pattern on * and match each segment
    ; Algorithm: dp[0] = true
    ;   for each segment between *s:
    ;     find segment in remaining str

    xor     r9, r9              ; pat_idx
    xor     r10, r10            ; str_idx (position in str)
    mov     r11, -1             ; last_star_str = -1
    mov     r15, -1             ; last_star_pat = -1

.wm_loop:
    cmp     r10, r14
    jae     .wm_str_done

    cmp     r9, r12
    jae     .wm_fail_or_backtrack

    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [r13 + r10]

    cmp     al, '*'
    je      .wm_star

    cmp     al, cl
    je      .wm_match_char

    ; mismatch
.wm_fail_or_backtrack:
    cmp     r15, -1
    je      .wm_no_match

    mov     r9, r15
    inc     r9
    inc     r11
    mov     r10, r11
    jmp     .wm_loop

.wm_match_char:
    inc     r9
    inc     r10
    jmp     .wm_loop

.wm_star:
    mov     r15, r9             ; save star pat pos
    mov     r11, r10            ; save star str pos
    inc     r9
    jmp     .wm_loop

.wm_str_done:
    ; str exhausted — skip trailing *s in pattern
.wm_skip_stars:
    cmp     r9, r12
    jae     .wm_match

    movzx   eax, byte [rbx + r9]
    cmp     al, '*'
    jne     .wm_no_match
    inc     r9
    jmp     .wm_skip_stars

.wm_match:
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.wm_no_match:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_wildcard_match

; -----------------------------------------------------------------------------
; str_wildcard_match_icase — case-insensitive variant
; -----------------------------------------------------------------------------

STR_FUNC str_wildcard_match_icase

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

.wmi_loop:
    cmp     r10, r14
    jae     .wmi_str_done

    cmp     r9, r12
    jae     .wmi_backtrack

    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [r13 + r10]

    cmp     al, '*'
    je      .wmi_star

    ; fold both to lowercase
    cmp     al, 'A'
    jb      .wmi_fold_c
    cmp     al, 'Z'
    ja      .wmi_fold_c
    or      al, 0x20
.wmi_fold_c:
    cmp     cl, 'A'
    jb      .wmi_cmp
    cmp     cl, 'Z'
    ja      .wmi_cmp
    or      cl, 0x20

.wmi_cmp:
    cmp     al, cl
    je      .wmi_adv

.wmi_backtrack:
    cmp     r15, -1
    je      .wmi_no_match
    mov     r9, r15
    inc     r9
    inc     r11
    mov     r10, r11
    jmp     .wmi_loop

.wmi_adv:
    inc     r9
    inc     r10
    jmp     .wmi_loop

.wmi_star:
    mov     r15, r9
    mov     r11, r10
    inc     r9
    jmp     .wmi_loop

.wmi_str_done:
.wmi_skip:
    cmp     r9, r12
    jae     .wmi_match
    movzx   eax, byte [rbx + r9]
    cmp     al, '*'
    jne     .wmi_no_match
    inc     r9
    jmp     .wmi_skip

.wmi_match:
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.wmi_no_match:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_wildcard_match_icase
%endif ; GUARD_LIB_STR_PATTERN_WILDCARD_ASM
