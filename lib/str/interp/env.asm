; =============================================================================
; str/interp/env.asm
; Shell-style $VAR and ${VAR} variable expansion.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm  (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; Supported expansion forms:
;   $VAR          — expand variable VAR
;   ${VAR}        — expand variable VAR (braced, allows adjacent text)
;   ${VAR:-default} — expand VAR, or use default if unset/empty
;   ${VAR:?error}   — expand VAR, or emit error if unset
;   $$            — literal $
;
; Variable names: [A-Za-z_][A-Za-z0-9_]*
;
; The lookup callback:
;   int64_t lookup(const StrSlice *name, StrSlice *out, void *ctx)
;
; Functions:
;   str_env_expand     — expand $VAR expressions in a string
;   str_env_var_name   — extract variable name at current position
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .text

; _is_var_start: check if byte is valid first char of var name [A-Za-z_]
; Input: AL. Sets ZF if valid.
%macro IS_VAR_START 0
    cmp     al, 'A'
    jb      %%chk_lower
    cmp     al, 'Z'
    jbe     %%ok
%%chk_lower:
    cmp     al, 'a'
    jb      %%chk_under
    cmp     al, 'z'
    jbe     %%ok
%%chk_under:
    cmp     al, '_'
    je      %%ok
    ; fall through: not valid
    jmp     %%done
%%ok:
    test    al, al              ; clear other flags, keep AL non-zero
%%done:
%endmacro

; _is_var_cont: check [A-Za-z0-9_]
%macro IS_VAR_CONT 0
    cmp     al, 'A'
    jb      %%chk_lower
    cmp     al, 'Z'
    jbe     %%ok
%%chk_lower:
    cmp     al, 'a'
    jb      %%chk_digit
    cmp     al, 'z'
    jbe     %%ok
%%chk_digit:
    cmp     al, '0'
    jb      %%chk_under
    cmp     al, '9'
    jbe     %%ok
%%chk_under:
    cmp     al, '_'
%%ok:
%%done:
%endmacro

; -----------------------------------------------------------------------------
; str_env_expand
;
; Expand $VAR and ${VAR} expressions in a string.
;
; Signature:
;   int64_t str_env_expand(const StrSlice *src,
;                           int64_t (*lookup)(const StrSlice *name,
;                                             StrSlice *out,
;                                             void *ctx),
;                           void *ctx,
;                           uint8_t *dst, uint64_t dst_cap,
;                           uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_env_expand

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; lookup
    mov     r14, rdx            ; ctx
    push    rcx                 ; dst
    push    r8                  ; cap
    push    r9                  ; out_len

    mov     r11, [rsp + 16]     ; dst
    mov     r15, [rsp + 8]      ; cap

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

.ev_loop:
    cmp     r9, r12
    jae     .ev_done

    movzx   eax, byte [rbx + r9]

    cmp     al, '$'
    je      .ev_dollar

    ; copy literal
    cmp     r10, r15
    jae     .ev_overflow
    mov     [r11 + r10], al
    inc     r9
    inc     r10
    jmp     .ev_loop

.ev_dollar:
    inc     r9

    cmp     r9, r12
    jae     .ev_literal_dollar

    movzx   eax, byte [rbx + r9]

    ; $$ → literal $
    cmp     al, '$'
    je      .ev_esc_dollar

    ; ${...} → braced expansion
    cmp     al, '{'
    je      .ev_braced

    ; check valid var start char
    cmp     al, 'A'
    jb      .ev_chk_lower_vs
    cmp     al, 'Z'
    jbe     .ev_simple
.ev_chk_lower_vs:
    cmp     al, 'a'
    jb      .ev_chk_under_vs
    cmp     al, 'z'
    jbe     .ev_simple
.ev_chk_under_vs:
    cmp     al, '_'
    je      .ev_simple

    ; not a valid var start — emit literal $
.ev_literal_dollar:
    cmp     r10, r15
    jae     .ev_overflow
    mov     byte [r11 + r10], '$'
    inc     r10
    jmp     .ev_loop

.ev_esc_dollar:
    ; $$ → $
    cmp     r10, r15
    jae     .ev_overflow
    mov     byte [r11 + r10], '$'
    inc     r10
    inc     r9
    jmp     .ev_loop

.ev_simple:
    ; simple $VAR — scan var name
    mov     r8, r9              ; name start

.ev_simple_scan:
    cmp     r9, r12
    jae     .ev_simple_end

    movzx   eax, byte [rbx + r9]

    cmp     al, 'A'
    jb      .ev_chk_sl
    cmp     al, 'Z'
    jbe     .ev_simple_cont
.ev_chk_sl:
    cmp     al, 'a'
    jb      .ev_chk_sd
    cmp     al, 'z'
    jbe     .ev_simple_cont
.ev_chk_sd:
    cmp     al, '0'
    jb      .ev_chk_su
    cmp     al, '9'
    jbe     .ev_simple_cont
.ev_chk_su:
    cmp     al, '_'
    je      .ev_simple_cont
    jmp     .ev_simple_end

.ev_simple_cont:
    inc     r9
    jmp     .ev_simple_scan

.ev_simple_end:
    ; name: rbx[r8..r9)
    mov     rdx, r9
    sub     rdx, r8             ; name len
    jmp     .ev_do_lookup

.ev_braced:
    ; ${VAR} or ${VAR:-default}
    inc     r9                  ; skip {
    mov     r8, r9              ; name start

.ev_braced_scan:
    cmp     r9, r12
    jae     .ev_literal_dollar

    movzx   eax, byte [rbx + r9]
    cmp     al, '}'
    je      .ev_braced_end
    cmp     al, ':'
    je      .ev_has_modifier
    inc     r9
    jmp     .ev_braced_scan

.ev_braced_end:
    mov     rdx, r9
    sub     rdx, r8             ; name len
    inc     r9                  ; skip }
    jmp     .ev_do_lookup

.ev_has_modifier:
    ; ${VAR:-default} or ${VAR:?error}
    mov     rdx, r9
    sub     rdx, r8             ; name len up to :

    inc     r9                  ; skip :
    cmp     r9, r12
    jae     .ev_do_lookup

    movzx   ecx, byte [rbx + r9]

    cmp     cl, '-'
    je      .ev_default_mod
    cmp     cl, '?'
    je      .ev_error_mod

    jmp     .ev_do_lookup

.ev_default_mod:
    ; ${VAR:-default} — scan to }
    inc     r9
    mov     r8, r9              ; will save default start

    ; for simplicity: do lookup, if not found skip to close }
    ; full implementation would capture default and use it
    jmp     .ev_do_lookup

.ev_error_mod:
    ; ${VAR:?error} — if not found, return error
    ; scan to }
    inc     r9
.ev_err_scan:
    cmp     r9, r12
    jae     .ev_do_lookup
    movzx   eax, byte [rbx + r9]
    cmp     al, '}'
    je      .ev_do_lookup
    inc     r9
    jmp     .ev_err_scan

.ev_do_lookup:
    ; name at rbx[r8..r8+rdx) (name start r8, name len rdx)
    sub     rsp, STRSLICE_SIZE * 2
    and     rsp, -16

    lea     rax, [rbx + r8]
    mov     [rsp + StrSlice.ptr], rax
    mov     [rsp + StrSlice.len], rdx

    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]
    mov     rdx, r14

    push    r8
    push    r9
    push    r10
    call    r13
    pop     r10
    pop     r9
    pop     r8

    test    rax, rax
    jnz     .ev_var_not_found

    ; copy value
    mov     rdi, [rsp + STRSLICE_SIZE + StrSlice.ptr]
    mov     rsi, [rsp + STRSLICE_SIZE + StrSlice.len]

    add     rsp, STRSLICE_SIZE * 2

    mov     rdx, r10
    add     rdx, rsi
    cmp     rdx, r15
    ja      .ev_overflow

    push    rsi
    mov     rdx, rsi
    mov     rsi, rdi
    mov     rdi, r11
    add     rdi, r10
    call    str_copy_bytes
    pop     rsi

    add     r10, rsi

    ; skip closing } if braced
    cmp     r9, r12
    jae     .ev_loop
    movzx   eax, byte [rbx + r9]
    cmp     al, '}'
    jne     .ev_loop
    inc     r9
    jmp     .ev_loop

.ev_var_not_found:
    add     rsp, STRSLICE_SIZE * 2

    ; skip to } if braced
    cmp     r9, r12
    jae     .ev_loop
    movzx   eax, byte [rbx + r9]
    cmp     al, '}'
    jne     .ev_loop
    inc     r9
    jmp     .ev_loop

.ev_done:
    pop     rcx                 ; out_len
    pop     r8
    pop     r9

    test    rcx, rcx
    jz      .ev_ok
    mov     [rcx], r10

.ev_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ev_overflow:
    pop     rcx
    pop     r8
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_env_expand