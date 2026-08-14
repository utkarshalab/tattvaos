%ifndef GUARD_LIB_STR_BUF_STRBUF_ASM
%define GUARD_LIB_STR_BUF_STRBUF_ASM
; =============================================================================
; str/buf/strbuf.asm
; UTF-8 string builder — StrBuf with string-aware push operations.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   buf/buf.asm       (str_buf_push, str_buf_push_byte, str_buf_as_slice)
;   utf8/encode.asm   (str_utf8_encode_unchecked, str_utf8_encode_buf_size)
;   convert/int.asm   (str_u64_to_str, str_i64_to_str)
;
; -----------------------------------------------------------------------------
; StrBuf is also the type used for string building.
; strbuf.asm adds UTF-8-aware push operations on top of the raw buf.asm.
;
; Functions:
;   str_buf_push_codepoint  — encode + append one codepoint
;   str_buf_push_str        — append null-terminated C string
;   str_buf_push_u64        — format + append uint64 as decimal
;   str_buf_push_i64        — format + append int64 as decimal
;   str_buf_push_hex        — format + append uint64 as hex
;   str_buf_push_char       — append ASCII char
;   str_buf_push_newline    — append '\n'
;   str_buf_push_cstr       — push null-terminated C string
;   str_buf_finish          — get result as StrSlice, validate UTF-8
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"









section .text

; -----------------------------------------------------------------------------
; str_buf_push_codepoint
;
; Encode a Unicode codepoint as UTF-8 and append to buffer.
;
; Signature:
;   int64_t str_buf_push_codepoint(StrBuf *buf, uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_codepoint

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12d, esi           ; codepoint

    ; get encoded size to reserve space
    mov     edi, r12d
    call    str_utf8_encode_buf_size
    test    rax, rax
    js      .bpc_err            ; invalid codepoint

    mov     r9, rax             ; encode size (1..4)

    ; reserve space
    mov     rdi, rbx
    mov     rax, [rbx + StrBuf.len]
    add     rax, r9
    mov     rsi, rax
    call    str_buf_reserve
    test    rax, rax
    jnz     .bpc_err

    ; encode directly into buffer
    mov     edi, r12d
    mov     rsi, [rbx + StrBuf.ptr]
    add     rsi, [rbx + StrBuf.len]
    call    str_utf8_encode_unchecked
    ; rax = bytes written

    add     [rbx + StrBuf.len], rax

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.bpc_err:
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_codepoint

; -----------------------------------------------------------------------------
; str_buf_push_cstr
;
; Append a null-terminated C string.
;
; Signature:
;   int64_t str_buf_push_cstr(StrBuf *buf, const char *cstr)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_cstr

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    ; compute length
    xor     ecx, ecx
.bpcstr_len:
    cmp     byte [r12 + rcx], 0
    je      .bpcstr_push
    inc     rcx
    jmp     .bpcstr_len

.bpcstr_push:
    ; push rcx bytes from r12
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, rcx
    call    str_buf_push

    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_cstr

; -----------------------------------------------------------------------------
; str_buf_push_u64
;
; Format uint64 as decimal string and append.
;
; Signature:
;   int64_t str_buf_push_u64(StrBuf *buf, uint64_t value)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_u64

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi            ; value

    ; format into temp stack buffer (max 20 chars for uint64)
    sub     rsp, 24
    and     rsp, -8

    mov     rdi, r12
    mov     rsi, rsp
    mov     rdx, 20
    lea     rcx, [rsp + 20]
    call    str_u64_to_str
    test    rax, rax
    jnz     .bu64_err

    mov     r9, [rsp + 20]      ; actual length

    ; push to buffer
    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, r9
    call    str_buf_push

    mov     rsp, rbp

    pop_regs r12, rbx
    pop     rbp
    ret

.bu64_err:
    mov     rsp, rbp
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_u64

; -----------------------------------------------------------------------------
; str_buf_push_i64
;
; Format int64 as decimal string and append.
;
; Signature:
;   int64_t str_buf_push_i64(StrBuf *buf, int64_t value)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_i64

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    sub     rsp, 28
    and     rsp, -8

    mov     rdi, r12
    mov     rsi, rsp
    mov     rdx, 24
    lea     rcx, [rsp + 24]
    call    str_i64_to_str
    test    rax, rax
    jnz     .bi64_err

    mov     r9, [rsp + 24]

    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, r9
    call    str_buf_push

    mov     rsp, rbp

    pop_regs r12, rbx
    pop     rbp
    ret

.bi64_err:
    mov     rsp, rbp
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_i64

; -----------------------------------------------------------------------------
; str_buf_push_hex
;
; Format uint64 as lowercase hex string and append.
;
; Signature:
;   int64_t str_buf_push_hex(StrBuf *buf, uint64_t value)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_hex

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    sub     rsp, 24
    and     rsp, -8

    mov     rdi, r12
    mov     rsi, rsp
    mov     rdx, 16
    lea     rcx, [rsp + 16]
    call    str_u64_to_hex
    test    rax, rax
    jnz     .bhex_err

    mov     r9, [rsp + 16]

    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, r9
    call    str_buf_push

    mov     rsp, rbp

    pop_regs r12, rbx
    pop     rbp
    ret

.bhex_err:
    mov     rsp, rbp
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_hex

; -----------------------------------------------------------------------------
; str_buf_push_char
;
; Append a single ASCII character.
;
; Signature:
;   int64_t str_buf_push_char(StrBuf *buf, uint8_t ch)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_char

    ; SIL = char byte
    pop     rbp
    jmp     str_buf_push_byte

STR_ENDFUNC str_buf_push_char

; -----------------------------------------------------------------------------
; str_buf_push_newline
;
; Append a LF newline character.
;
; Signature:
;   int64_t str_buf_push_newline(StrBuf *buf)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_newline

    guard_null rdi, STR_ERR_NULL

    mov     sil, 0x0A           ; LF

    pop     rbp
    jmp     str_buf_push_byte

STR_ENDFUNC str_buf_push_newline

; -----------------------------------------------------------------------------
; str_buf_push_repeat
;
; Append a byte repeated N times.
;
; Signature:
;   int64_t str_buf_push_repeat(StrBuf *buf, uint8_t byte, uint64_t n)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_repeat

    guard_null rdi, STR_ERR_NULL

    test    rdx, rdx
    jz      .bpr_ok

    push_regs rbx, r12, r13

    mov     rbx, rdi
    movzx   r12d, sil
    mov     r13, rdx

.bpr_loop:
    test    r13, r13
    jz      .bpr_done

    mov     rdi, rbx
    movzx   esi, r12b
    call    str_buf_push_byte
    test    rax, rax
    jnz     .bpr_err

    dec     r13
    jmp     .bpr_loop

.bpr_done:
    pop_regs r13, r12, rbx

.bpr_ok:
    xor     eax, eax
    pop     rbp
    ret

.bpr_err:
    pop_regs r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_repeat

; -----------------------------------------------------------------------------
; str_buf_finish
;
; Get the buffer contents as a StrSlice.
; Does NOT consume or free the buffer.
;
; Signature:
;   int64_t str_buf_finish(const StrBuf *buf, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_finish

    pop     rbp
    jmp     str_buf_as_slice

STR_ENDFUNC str_buf_finish
%endif ; GUARD_LIB_STR_BUF_STRBUF_ASM
