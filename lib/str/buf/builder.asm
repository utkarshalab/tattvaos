; =============================================================================
; str/buf/builder.asm
; Zero-allocation fixed-capacity string builder.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes
extern str_utf8_encode_unchecked
extern str_utf8_encode_buf_size

struc StrBuilder
    .ptr  resq 1
    .len  resq 1
    .cap  resq 1
endstruc

section .text

; -----------------------------------------------------------------------------
; str_builder_init
;
; Initialize builder with a pre-allocated fixed buffer.
;
; Signature:
;   int64_t str_builder_init(StrBuilder *builder, uint8_t *buf, uint64_t cap)
; -----------------------------------------------------------------------------
STR_FUNC str_builder_init
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     [rdi + StrBuilder.ptr], rsi
    mov     qword [rdi + StrBuilder.len], 0
    mov     [rdi + StrBuilder.cap], rdx

    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_builder_init

; -----------------------------------------------------------------------------
; str_builder_append
;
; Append a StrSlice to the builder. Returns STR_ERR_BUF_TOO_SMALL on overflow.
;
; Signature:
;   int64_t str_builder_append(StrBuilder *builder, const StrSlice *slice)
; -----------------------------------------------------------------------------
STR_FUNC str_builder_append
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12, rsi

    mov     rcx, [r12 + StrSlice.len]
    test    rcx, rcx
    jz      .append_ok

    mov     rax, [rbx + StrBuilder.len]
    add     rax, rcx
    cmp     rax, [rbx + StrBuilder.cap]
    ja      .append_overflow

    ; copy bytes
    mov     rdi, [rbx + StrBuilder.ptr]
    add     rdi, [rbx + StrBuilder.len]
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rdx, rcx
    call    str_copy_bytes

    add     [rbx + StrBuilder.len], rcx

.append_ok:
    xor     eax, eax
    pop_regs r12, rbx
    pop     rbp
    ret

.append_overflow:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop_regs r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_builder_append

; -----------------------------------------------------------------------------
; str_builder_append_char
;
; Encode and append a single Unicode codepoint.
;
; Signature:
;   int64_t str_builder_append_char(StrBuilder *builder, uint32_t cp)
; -----------------------------------------------------------------------------
STR_FUNC str_builder_append_char
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12
    mov     rbx, rdi
    mov     r12d, esi

    ; get encoded size
    mov     edi, r12d
    call    str_utf8_encode_buf_size
    test    rax, rax
    js      .append_char_err

    mov     rcx, rax            ; size
    mov     rdx, [rbx + StrBuilder.len]
    add     rdx, rcx
    cmp     rdx, [rbx + StrBuilder.cap]
    ja      .append_char_overflow

    ; encode
    mov     edi, r12d
    mov     rsi, [rbx + StrBuilder.ptr]
    add     rsi, [rbx + StrBuilder.len]
    call    str_utf8_encode_unchecked

    add     [rbx + StrBuilder.len], rax

    xor     eax, eax
    pop_regs r12, rbx
    pop     rbp
    ret

.append_char_overflow:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop_regs r12, rbx
    pop     rbp
    ret

.append_char_err:
    mov     rax, STR_ERR_INVALID
    pop_regs r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_builder_append_char

; -----------------------------------------------------------------------------
; str_builder_clear
;
; Reset the builder length to 0.
;
; Signature:
;   int64_t str_builder_clear(StrBuilder *builder)
; -----------------------------------------------------------------------------
STR_FUNC str_builder_clear
    guard_null rdi, STR_ERR_NULL
    mov     qword [rdi + StrBuilder.len], 0
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_builder_clear

; -----------------------------------------------------------------------------
; str_builder_build
;
; Returns the completed string as a StrSlice output structure.
;
; Signature:
;   int64_t str_builder_build(const StrBuilder *builder, StrSlice *out)
; -----------------------------------------------------------------------------
STR_FUNC str_builder_build
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrBuilder.ptr]
    mov     rcx, [rdi + StrBuilder.len]
    mov     [rsi + StrSlice.ptr], rax
    mov     [rsi + StrSlice.len], rcx

    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_builder_build
