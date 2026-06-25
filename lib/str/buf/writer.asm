; =============================================================================
; str/buf/writer.asm
; Streaming byte/codepoint writer into a StrBuf or fixed buffer.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   buf/buf.asm     (str_buf_push, str_buf_push_byte)
;   buf/strbuf.asm  (str_buf_push_codepoint, str_buf_push_u64)
;
; -----------------------------------------------------------------------------
; StrWriter provides a unified write interface that can target either:
;   a) A StrBuf (growable heap-backed)
;   b) A fixed-size byte buffer (stack or static)
;
; StrWriter layout (32 bytes):
;   target  dq   — pointer to StrBuf (mode=0) or byte buffer (mode=1)
;   ptr     dq   — current write position (mode=1 only)
;   end     dq   — one past end (mode=1 only)
;   mode    dq   — 0=dynamic(StrBuf), 1=fixed buffer
;
; When mode=dynamic, all writes go through str_buf_push.
; When mode=fixed, writes directly to the buffer, returns error on overflow.
;
; Functions:
;   str_writer_init_buf    — init for dynamic StrBuf target
;   str_writer_init_fixed  — init for fixed buffer
;   str_writer_write       — write bytes
;   str_writer_write_byte  — write one byte
;   str_writer_write_cp    — write one codepoint (UTF-8 encoded)
;   str_writer_write_u64   — write uint64 as decimal
;   str_writer_written     — bytes written so far
;   str_writer_as_slice    — get written content as StrSlice
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_buf_push
extern str_buf_push_byte
extern str_buf_push_codepoint
extern str_buf_push_u64
extern str_buf_as_slice
extern str_utf8_encode_unchecked

struc StrWriter
    .target resq 1
    .ptr    resq 1
    .end    resq 1
    .mode   resq 1
endstruc

STRWRITER_SIZE  equ 32
WRITER_MODE_DYN equ 0
WRITER_MODE_FIX equ 1

section .text

; -----------------------------------------------------------------------------
; str_writer_init_buf
;
; Initialize a writer targeting a StrBuf (dynamic, growable).
;
; Signature:
;   int64_t str_writer_init_buf(StrWriter *writer, StrBuf *buf)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_init_buf

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     [rdi + StrWriter.target], rsi
    mov     qword [rdi + StrWriter.ptr],  0
    mov     qword [rdi + StrWriter.end],  0
    mov     qword [rdi + StrWriter.mode], WRITER_MODE_DYN

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_writer_init_buf

; -----------------------------------------------------------------------------
; str_writer_init_fixed
;
; Initialize a writer targeting a fixed byte buffer.
;
; Signature:
;   int64_t str_writer_init_fixed(StrWriter *writer, uint8_t *buf,
;                                  uint64_t cap)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_init_fixed

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     [rdi + StrWriter.target], rsi
    mov     [rdi + StrWriter.ptr],    rsi

    mov     rax, rsi
    add     rax, rdx
    mov     [rdi + StrWriter.end], rax

    mov     qword [rdi + StrWriter.mode], WRITER_MODE_FIX

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_writer_init_fixed

; -----------------------------------------------------------------------------
; str_writer_write
;
; Write bytes to the writer.
;
; Signature:
;   int64_t str_writer_write(StrWriter *writer, const uint8_t *data,
;                             uint64_t len)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_write

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    test    rdx, rdx
    jz      .ww_ok

    mov     rax, [rdi + StrWriter.mode]
    test    rax, rax
    jnz     .ww_fixed

    ; dynamic mode: push to StrBuf
    mov     rdi, [rdi + StrWriter.target]
    pop     rbp
    jmp     str_buf_push

.ww_fixed:
    ; fixed mode: write directly
    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi            ; data
    mov     r13, rdx            ; len

    mov     rax, [rbx + StrWriter.ptr]
    mov     r9,  [rbx + StrWriter.end]

    ; check space
    mov     rcx, rax
    add     rcx, r13
    cmp     rcx, r9
    ja      .ww_fixed_overflow

    ; copy
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    ; inline copy
    push    r13
.ww_copy:
    test    r13, r13
    jz      .ww_copy_done
    movzx   eax, byte [rsi]
    mov     [rdi], al
    inc     rdi
    inc     rsi
    dec     r13
    jmp     .ww_copy
.ww_copy_done:
    pop     r13

    mov     rax, [rbx + StrWriter.ptr]
    add     rax, r13
    mov     [rbx + StrWriter.ptr], rax

    pop_regs r13, r12, rbx

.ww_ok:
    xor     eax, eax
    pop     rbp
    ret

.ww_fixed_overflow:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_writer_write

; -----------------------------------------------------------------------------
; str_writer_write_byte
;
; Write one byte.
;
; Signature:
;   int64_t str_writer_write_byte(StrWriter *writer, uint8_t byte)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_write_byte

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrWriter.mode]
    test    rax, rax
    jnz     .wwb_fixed

    ; dynamic
    mov     rdi, [rdi + StrWriter.target]
    pop     rbp
    jmp     str_buf_push_byte

.wwb_fixed:
    mov     rax, [rdi + StrWriter.ptr]
    cmp     rax, [rdi + StrWriter.end]
    jae     .wwb_overflow

    mov     [rax], sil
    inc     rax
    mov     [rdi + StrWriter.ptr], rax

    xor     eax, eax
    pop     rbp
    ret

.wwb_overflow:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_writer_write_byte

; -----------------------------------------------------------------------------
; str_writer_write_cp
;
; Encode and write one Unicode codepoint.
;
; Signature:
;   int64_t str_writer_write_cp(StrWriter *writer, uint32_t cp)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_write_cp

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrWriter.mode]
    test    rax, rax
    jnz     .wwcp_fixed

    ; dynamic
    mov     rdi, [rdi + StrWriter.target]
    pop     rbp
    jmp     str_buf_push_codepoint

.wwcp_fixed:
    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12d, esi           ; cp

    ; encode to stack
    sub     rsp, 8
    and     rsp, -8

    mov     edi, r12d
    mov     rsi, rsp
    call    str_utf8_encode_unchecked
    ; rax = bytes written

    ; check space
    mov     rcx, [rbx + StrWriter.ptr]
    mov     r9, rcx
    add     r9, rax
    cmp     r9, [rbx + StrWriter.end]
    ja      .wwcp_overflow

    ; write bytes
    xor     ecx, ecx
.wwcp_copy:
    cmp     rcx, rax
    jae     .wwcp_done
    movzx   edx, byte [rsp + rcx]
    mov     r8, [rbx + StrWriter.ptr]
    mov     [r8 + rcx], dl
    inc     rcx
    jmp     .wwcp_copy

.wwcp_done:
    mov     r8, [rbx + StrWriter.ptr]
    add     r8, rax
    mov     [rbx + StrWriter.ptr], r8

    mov     rsp, rbp
    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.wwcp_overflow:
    mov     rsp, rbp
    pop_regs r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_writer_write_cp

; -----------------------------------------------------------------------------
; str_writer_write_u64
;
; Write uint64 as decimal string.
; -----------------------------------------------------------------------------

STR_FUNC str_writer_write_u64

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrWriter.mode]
    test    rax, rax
    jnz     .wwu64_fixed

    ; dynamic
    mov     rdi, [rdi + StrWriter.target]
    pop     rbp
    jmp     str_buf_push_u64

.wwu64_fixed:
    ; format to stack, then write
    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi            ; value

    sub     rsp, 24
    and     rsp, -8

    ; format using inline decimal conversion
    mov     r9, r12
    xor     r10, r10            ; digit count

    test    r9, r9
    jnz     .wwu64_gen

    mov     byte [rsp], '0'
    mov     r10, 1
    jmp     .wwu64_reverse

.wwu64_gen:
    mov     rcx, ITOA_BUF_SIZE - 1   ; doesn't exist here — use fixed 20
    ; simplified:
    xor     rcx, rcx

.wwu64_digit:
    test    r9, r9
    jz      .wwu64_gen_done
    mov     rax, r9
    xor     edx, edx
    mov     r8d, 10
    div     r8
    add     dl, '0'
    mov     [rsp + rcx], dl
    mov     r9, rax
    inc     rcx
    jmp     .wwu64_digit

.wwu64_gen_done:
    ; rcx = digit count, digits in reverse order at rsp
    ; reverse
    mov     r10, rcx
    xor     rdx, rdx
    dec     rcx

.wwu64_rev:
    cmp     rdx, rcx
    jge     .wwu64_reverse

    mov     al, [rsp + rdx]
    mov     r8b, [rsp + rcx]
    mov     [rsp + rdx], r8b
    mov     [rsp + rcx], al
    inc     rdx
    dec     rcx
    jmp     .wwu64_rev

.wwu64_reverse:
    ; write r10 bytes from rsp to writer
    mov     rdi, rbx
    mov     rsi, rsp
    mov     rdx, r10
    call    str_writer_write

    mov     rsp, rbp
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_writer_write_u64

; -----------------------------------------------------------------------------
; str_writer_written
;
; Return bytes written so far.
;
; Signature:
;   uint64_t str_writer_written(const StrWriter *writer)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_written

    test    rdi, rdi
    jz      .wrtn_zero

    mov     rax, [rdi + StrWriter.mode]
    test    rax, rax
    jnz     .wrtn_fixed

    ; dynamic: get len from StrBuf
    mov     rdi, [rdi + StrWriter.target]
    test    rdi, rdi
    jz      .wrtn_zero
    mov     rax, [rdi + StrBuf.len]
    pop     rbp
    ret

.wrtn_fixed:
    mov     rax, [rdi + StrWriter.ptr]
    sub     rax, [rdi + StrWriter.target]
    pop     rbp
    ret

.wrtn_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_writer_written

; -----------------------------------------------------------------------------
; str_writer_as_slice
;
; Get written content as StrSlice.
;
; Signature:
;   int64_t str_writer_as_slice(const StrWriter *writer, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_writer_as_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrWriter.mode]
    test    rax, rax
    jnz     .was_fixed

    ; dynamic
    mov     rdi, [rdi + StrWriter.target]
    pop     rbp
    jmp     str_buf_as_slice

.was_fixed:
    mov     rax, [rdi + StrWriter.target]
    mov     [rsi + StrSlice.ptr], rax

    mov     rax, [rdi + StrWriter.ptr]
    sub     rax, [rdi + StrWriter.target]
    mov     [rsi + StrSlice.len], rax

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_writer_as_slice