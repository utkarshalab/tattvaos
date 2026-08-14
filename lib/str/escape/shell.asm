%ifndef GUARD_LIB_STR_ESCAPE_SHELL_ASM
%define GUARD_LIB_STR_ESCAPE_SHELL_ASM
; =============================================================================
; str/escape/shell.asm
; Shell argument escaping for POSIX sh and bash.
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
; Shell escaping strategies:
;
;   STRATEGY_SINGLE_QUOTE:
;     Wrap entire string in single quotes.
;     Single quotes within the string become: '\''
;     Safe for all characters except null bytes.
;     Example: it's a "test" → 'it'\''s a "test"'
;
;   STRATEGY_DOUBLE_QUOTE:
;     Wrap in double quotes, backslash-escape: $ ` " \ ! newline
;     Allows variable expansion inside (sometimes desired).
;
;   STRATEGY_MINIMAL:
;     Only escape chars that need it: space tab newline and shell metacharacters
;     !  "  #  $  &  '  (  )  *  ,  ;  <  =  >  ?  [  \  ]  ^  `  {  |  }  ~
;
; Functions:
;   str_shell_escape          — escape with single-quote strategy (safest)
;   str_shell_escape_dquote   — escape with double-quote strategy
;   str_shell_escape_minimal  — minimal escaping
;   str_shell_needs_escaping  — check if string needs any escaping
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_shell_escape
;
; Escape a string for safe use as a shell argument using single quotes.
; Output: 'content' with internal ' escaped as '\''
;
; Signature:
;   int64_t str_shell_escape(const StrSlice *src, uint8_t *dst,
;                             uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_shell_escape

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

    ; write opening single quote
    cmp     r10, r14
    jae     .se_overflow
    mov     byte [r13 + r10], 0x27
    inc     r10

.se_loop:
    cmp     r9, r12
    jae     .se_close

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, 0x27            ; single quote
    jne     .se_copy

    ; single quote escape: end current quote, insert \', reopen
    ; ' → '\''  (4 bytes: ', \, ', ')
    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .se_overflow

    mov     byte [r13 + r10],     0x27     ; close '
    mov     byte [r13 + r10 + 1], 0x5C     ; backslash
    mov     byte [r13 + r10 + 2], 0x27     ; escaped '
    mov     byte [r13 + r10 + 3], 0x27     ; reopen '
    add     r10, 4
    jmp     .se_loop

.se_copy:
    ; check for null byte — can't be safely represented in most shells
    test    al, al
    jz      .se_loop            ; silently skip null bytes

    cmp     r10, r14
    jae     .se_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .se_loop

.se_close:
    ; write closing single quote
    cmp     r10, r14
    jae     .se_overflow
    mov     byte [r13 + r10], 0x27
    inc     r10

    test    r15, r15
    jz      .se_ok
    mov     [r15], r10

.se_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.se_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_shell_escape

; -----------------------------------------------------------------------------
; str_shell_escape_dquote
;
; Escape for use inside double quotes.
; Escapes: $ ` " \ and newline with backslash.
;
; Signature:
;   int64_t str_shell_escape_dquote(const StrSlice *src, uint8_t *dst,
;                                    uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_shell_escape_dquote

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9
    xor     r10, r10

    ; opening double quote
    cmp     r10, r14
    jae     .sed_overflow
    mov     byte [r13 + r10], '"'
    inc     r10

.sed_loop:
    cmp     r9, r12
    jae     .sed_close

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; chars needing backslash escape inside double quotes
    cmp     al, '$'
    je      .sed_backslash
    cmp     al, '`'
    je      .sed_backslash
    cmp     al, '"'
    je      .sed_backslash
    cmp     al, 0x5C            ; backslash
    je      .sed_backslash
    cmp     al, 0x0A            ; LF
    je      .sed_backslash
    cmp     al, '!'
    je      .sed_backslash

    cmp     r10, r14
    jae     .sed_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .sed_loop

.sed_backslash:
    lea     rcx, [r10 + 2]
    cmp     rcx, r14
    ja      .sed_overflow
    mov     byte [r13 + r10], 0x5C
    mov     [r13 + r10 + 1], al
    add     r10, 2
    jmp     .sed_loop

.sed_close:
    cmp     r10, r14
    jae     .sed_overflow
    mov     byte [r13 + r10], '"'
    inc     r10

    test    r15, r15
    jz      .sed_ok
    mov     [r15], r10

.sed_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sed_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_shell_escape_dquote

; -----------------------------------------------------------------------------
; str_shell_escape_minimal
;
; Backslash-escape only the characters that need it without quoting.
; Suitable for argument lists where tokens are already separated.
;
; Escapes: space tab newline and all shell metacharacters.
;
; Signature:
;   int64_t str_shell_escape_minimal(const StrSlice *src, uint8_t *dst,
;                                     uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

section .rodata

; Shell metacharacters that need escaping in unquoted context
; Stored as null-terminated list
_shell_meta: db "!\"#$&'()*,;<=>?[\]^`{|}~ ", 0x09, 0x0A, 0x0D, 0

section .text

STR_FUNC str_shell_escape_minimal

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9
    xor     r10, r10

.sem_loop:
    cmp     r9, r12
    jae     .sem_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; check if this byte is in the metachar list
    lea     r11, [rel _shell_meta]
    xor     ecx, ecx

.sem_scan:
    movzx   edx, byte [r11 + rcx]
    test    dl, dl
    jz      .sem_copy           ; not a metachar

    cmp     dl, al
    je      .sem_escape
    inc     ecx
    jmp     .sem_scan

.sem_escape:
    lea     rcx, [r10 + 2]
    cmp     rcx, r14
    ja      .sem_overflow
    mov     byte [r13 + r10], 0x5C
    mov     [r13 + r10 + 1], al
    add     r10, 2
    jmp     .sem_loop

.sem_copy:
    cmp     r10, r14
    jae     .sem_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .sem_loop

.sem_done:
    test    r15, r15
    jz      .sem_ok
    mov     [r15], r10

.sem_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sem_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_shell_escape_minimal

; -----------------------------------------------------------------------------
; str_shell_needs_escaping
;
; Check if a string contains any characters that would need shell escaping.
; Useful as a fast-path check before allocating output buffers.
;
; Signature:
;   int64_t str_shell_needs_escaping(const StrSlice *src)
;
; Returns:
;   RAX  = 1  needs escaping
;   RAX  = 0  safe as-is (alphanumeric and - _ . / only)
; -----------------------------------------------------------------------------

STR_FUNC str_shell_needs_escaping

    test    rdi, rdi
    jz      .sne_no

    mov     rsi, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .sne_no

.sne_loop:
    test    rcx, rcx
    jz      .sne_no

    movzx   eax, byte [rsi]
    inc     rsi
    dec     ecx

    ; safe chars: A-Z a-z 0-9 - _ . /
    cmp     al, 'A'
    jb      .sne_chk_lower
    cmp     al, 'Z'
    jbe     .sne_next
.sne_chk_lower:
    cmp     al, 'a'
    jb      .sne_chk_digit
    cmp     al, 'z'
    jbe     .sne_next
.sne_chk_digit:
    cmp     al, '0'
    jb      .sne_chk_safe
    cmp     al, '9'
    jbe     .sne_next
.sne_chk_safe:
    cmp     al, '-'
    je      .sne_next
    cmp     al, '_'
    je      .sne_next
    cmp     al, '.'
    je      .sne_next
    cmp     al, '/'
    je      .sne_next

    ; needs escaping
    mov     eax, 1
    pop     rbp
    ret

.sne_next:
    jmp     .sne_loop

.sne_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_shell_needs_escaping
%endif ; GUARD_LIB_STR_ESCAPE_SHELL_ASM
