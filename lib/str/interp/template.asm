%ifndef GUARD_LIB_STR_INTERP_TEMPLATE_ASM
%define GUARD_LIB_STR_INTERP_TEMPLATE_ASM
; =============================================================================
; str/interp/template.asm
; Simple template substitution engine.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/cmp.asm   (str_eq)
;   core/copy.asm  (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; Template syntax:
;
;   {{name}}        — variable substitution
;   {{name|default}} — with fallback value if name not found
;   {# comment #}   — comment (stripped)
;   \{{             — literal {{
;
; Variable lookup uses a caller-supplied callback:
;   int64_t lookup(const StrSlice *name, StrSlice *out, void *ctx)
;   Returns STR_OK if found, STR_ERR_NOT_FOUND if missing.
;
; Functions:
;   str_template_render     — render a template into a buffer
;   str_template_render_buf — render into a StrBuf
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_template_render
;
; Render a template string, substituting {{var}} with looked-up values.
;
; Signature:
;   int64_t str_template_render(const StrSlice *tmpl,
;                                int64_t (*lookup)(const StrSlice *name,
;                                                   StrSlice *out,
;                                                   void *ctx),
;                                void *ctx,
;                                uint8_t *dst, uint64_t dst_cap,
;                                uint64_t *out_len)
;
; Arguments:
;   RDI  — template StrSlice
;   RSI  — lookup callback
;   RDX  — context for callback
;   RCX  — destination buffer
;   R8   — capacity
;   R9   — out_len
; -----------------------------------------------------------------------------

STR_FUNC str_template_render

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

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

    ; load dst and cap from stack
    mov     r11, [rsp + 8]      ; dst (after 3 pushes: r9=16,r8=8,rcx=0)
    ; Wait: pushes were rcx, r8, r9. Stack grows down.
    ; [rsp + 0] = r9 (out_len)
    ; [rsp + 8] = r8 (cap)
    ; [rsp + 16] = rcx (dst)
    mov     r11, [rsp + 16]     ; dst
    mov     r15, [rsp + 8]      ; cap

.tr_loop:
    cmp     r9, r12
    jae     .tr_done

    movzx   eax, byte [rbx + r9]

    ; check for escaped \{{
    cmp     al, 0x5C            ; backslash
    jne     .tr_check_open

    ; peek ahead for {{
    lea     rcx, [r9 + 1]
    cmp     rcx, r12
    jae     .tr_copy_byte

    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, '{'
    jne     .tr_copy_byte

    lea     rcx, [r9 + 2]
    cmp     rcx, r12
    jae     .tr_copy_byte

    movzx   ecx, byte [rbx + r9 + 2]
    cmp     cl, '{'
    jne     .tr_copy_byte

    ; \{{ → emit literal {
    ; skip backslash, emit first {, skip second {
    cmp     r10, r15
    jae     .tr_overflow
    mov     byte [r11 + r10], '{'
    inc     r10
    add     r9, 2               ; skip \{ (second { goes to .tr_copy_byte)
    inc     r9                  ; skip second {
    jmp     .tr_loop

.tr_check_open:
    ; check for {{
    cmp     al, '{'
    jne     .tr_check_comment

    lea     rcx, [r9 + 1]
    cmp     rcx, r12
    jae     .tr_copy_byte

    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, '{'
    jne     .tr_copy_byte

    ; found {{ — scan for }}
    add     r9, 2               ; skip {{

    mov     r8, r9              ; var_name_start

.tr_scan_close:
    cmp     r9, r12
    jae     .tr_unterminated

    movzx   eax, byte [rbx + r9]
    cmp     al, '}'
    jne     .tr_scan_next

    lea     rcx, [r9 + 1]
    cmp     rcx, r12
    jae     .tr_scan_next

    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, '}'
    je      .tr_found_close

.tr_scan_next:
    inc     r9
    jmp     .tr_scan_close

.tr_found_close:
    ; var name: rbx[r8 .. r9)
    ; check for | (default separator)
    mov     rdx, r9
    sub     rdx, r8             ; full name len (including possible |default)

    ; find '|' within var name
    push    r8
    push    r9
    push    r10

    xor     rcx, rcx
    mov     r9, r8              ; search start

.tr_find_pipe:
    cmp     rcx, rdx
    jae     .tr_no_pipe

    movzx   eax, byte [rbx + r8 + rcx]
    cmp     al, '|'
    je      .tr_has_pipe
    inc     rcx
    jmp     .tr_find_pipe

.tr_has_pipe:
    ; name = rbx[r8 .. r8+rcx), default = rbx[r8+rcx+1 .. r9)
    mov     r9, rcx             ; name_len = rcx
    jmp     .tr_lookup_var

.tr_no_pipe:
    mov     r9, rdx             ; name_len = full len

.tr_lookup_var:
    ; build name StrSlice on stack
    sub     rsp, STRSLICE_SIZE + STRSLICE_SIZE
    and     rsp, -16

    lea     rax, [rbx + r8]     ; use saved r8 (name start)
    mov     [rsp + StrSlice.ptr], rax
    mov     [rsp + StrSlice.len], r9

    ; call lookup(name_slice, out_slice, ctx)
    mov     rdi, rsp            ; name
    lea     rsi, [rsp + STRSLICE_SIZE]  ; out
    mov     rdx, r14            ; ctx

    push    r8
    push    r9
    call    r13                 ; lookup callback
    pop     r9
    pop     r8

    test    rax, rax
    jnz     .tr_not_found

    ; found — copy value to dst
    mov     rdi, [rsp + STRSLICE_SIZE + StrSlice.ptr]
    mov     rsi, [rsp + STRSLICE_SIZE + StrSlice.len]

    add     rsp, STRSLICE_SIZE * 2

    pop     r10                 ; restore dst index
    pop     r9                  ; restore close }}  start
    pop     r8                  ; restore var start

    ; copy value
    mov     rdx, r10
    add     rdx, rsi
    cmp     rdx, r15
    ja      .tr_overflow

    push    rsi
    mov     rdx, rsi            ; len
    mov     rsi, rdi            ; src
    mov     rdi, r11
    add     rdi, r10            ; dst
    call    str_copy_bytes
    pop     rsi

    add     r10, rsi
    add     r9, 2               ; skip }}
    jmp     .tr_loop

.tr_not_found:
    ; check if there was a default
    add     rsp, STRSLICE_SIZE * 2
    pop     r10
    pop     r9
    pop     r8

    ; for now: skip the tag (emit nothing)
    add     r9, 2               ; skip }}
    jmp     .tr_loop

.tr_unterminated:
    ; {{ without }} — emit literal {{
    cmp     r10 + 2, r15
    ja      .tr_overflow
    mov     byte [r11 + r10], '{'
    mov     byte [r11 + r10 + 1], '{'
    add     r10, 2
    jmp     .tr_loop

.tr_check_comment:
    ; check for {# comment #}
    cmp     al, '{'
    jne     .tr_copy_byte

    lea     rcx, [r9 + 1]
    cmp     rcx, r12
    jae     .tr_copy_byte

    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, '#'
    jne     .tr_copy_byte

    ; scan to #}
    add     r9, 2

.tr_comment_scan:
    cmp     r9, r12
    jae     .tr_loop

    movzx   eax, byte [rbx + r9]
    inc     r9
    cmp     al, '#'
    jne     .tr_comment_scan

    cmp     r9, r12
    jae     .tr_loop

    movzx   eax, byte [rbx + r9]
    cmp     al, '}'
    jne     .tr_comment_scan
    inc     r9
    jmp     .tr_loop

.tr_copy_byte:
    cmp     r10, r15
    jae     .tr_overflow
    mov     [r11 + r10], al
    inc     r9
    inc     r10
    jmp     .tr_loop

.tr_done:
    pop     rcx                 ; out_len
    pop     r8                  ; cap (discard)
    pop     r9                  ; dst (discard)

    test    rcx, rcx
    jz      .tr_ok
    mov     [rcx], r10

.tr_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tr_overflow:
    pop     rcx
    pop     r8
    pop     r9
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_template_render
%endif ; GUARD_LIB_STR_INTERP_TEMPLATE_ASM
