; =============================================================================
; str/buf/reader.asm
; Streaming byte/codepoint reader over a StrSlice.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; StrReader is a cursor over an existing StrSlice — no allocation.
; It tracks current position for sequential reading.
;
; StrReader layout (32 bytes):
;   ptr     dq  — current position in buffer
;   end     dq  — one past last byte
;   line    dq  — current line number (1-based, if tracked)
;   col     dq  — current column number (1-based, if tracked)
;
; Functions:
;   str_reader_init         — initialize from StrSlice
;   str_reader_read_byte    — read one byte
;   str_reader_peek_byte    — peek at next byte without advancing
;   str_reader_read_cp      — read one codepoint
;   str_reader_peek_cp      — peek at next codepoint
;   str_reader_read_line    — read until LF, return StrSlice
;   str_reader_skip         — skip N bytes
;   str_reader_remaining    — bytes left
;   str_reader_is_done      — check exhausted
;   str_reader_pos          — get current byte offset
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

struc StrReader
    .ptr    resq 1
    .end    resq 1
    .line   resq 1
    .col    resq 1
endstruc

STREADER_SIZE   equ 32

section .text

; -----------------------------------------------------------------------------
; str_reader_init
;
; Initialize a StrReader from a StrSlice.
;
; Signature:
;   int64_t str_reader_init(StrReader *reader, const StrSlice *slice)
; -----------------------------------------------------------------------------

STR_FUNC str_reader_init

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rsi + StrSlice.ptr]
    mov     [rdi + StrReader.ptr], rax

    mov     rcx, [rsi + StrSlice.len]
    add     rax, rcx
    mov     [rdi + StrReader.end], rax

    mov     qword [rdi + StrReader.line], 1
    mov     qword [rdi + StrReader.col],  1

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_reader_init

; -----------------------------------------------------------------------------
; str_reader_init_raw
;
; Initialize from raw ptr + len.
;
; Signature:
;   int64_t str_reader_init_raw(StrReader *reader, const uint8_t *ptr,
;                                uint64_t len)
; -----------------------------------------------------------------------------

STR_FUNC str_reader_init_raw

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     [rdi + StrReader.ptr], rsi

    mov     rax, rsi
    add     rax, rdx
    mov     [rdi + StrReader.end], rax

    mov     qword [rdi + StrReader.line], 1
    mov     qword [rdi + StrReader.col],  1

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_reader_init_raw

; -----------------------------------------------------------------------------
; str_reader_read_byte
;
; Read one byte, advance position.
;
; Signature:
;   int64_t str_reader_read_byte(StrReader *reader, uint8_t *out)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_ITER_END  reader exhausted
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_reader_read_byte

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrReader.ptr]
    cmp     rax, [rdi + StrReader.end]
    jae     .rb_end

    movzx   ecx, byte [rax]
    mov     [rsi], cl

    inc     rax
    mov     [rdi + StrReader.ptr], rax

    ; update line/col
    cmp     cl, 0x0A            ; LF
    jne     .rb_not_lf
    inc     qword [rdi + StrReader.line]
    mov     qword [rdi + StrReader.col], 1
    jmp     .rb_ok

.rb_not_lf:
    inc     qword [rdi + StrReader.col]

.rb_ok:
    xor     eax, eax
    pop     rbp
    ret

.rb_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_reader_read_byte

; -----------------------------------------------------------------------------
; str_reader_peek_byte
;
; Peek at next byte without advancing.
;
; Signature:
;   int64_t str_reader_peek_byte(const StrReader *reader, uint8_t *out)
; -----------------------------------------------------------------------------

STR_FUNC str_reader_peek_byte

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrReader.ptr]
    cmp     rax, [rdi + StrReader.end]
    jae     .pkb_end

    movzx   ecx, byte [rax]
    mov     [rsi], cl

    xor     eax, eax
    pop     rbp
    ret

.pkb_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_reader_peek_byte

; -----------------------------------------------------------------------------
; str_reader_read_cp
;
; Read one UTF-8 codepoint, advance position.
;
; Signature:
;   int64_t str_reader_read_cp(StrReader *reader, uint32_t *out_cp)
; -----------------------------------------------------------------------------

STR_FUNC str_reader_read_cp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrReader.ptr]
    cmp     rax, [rdi + StrReader.end]
    jae     .rcp_end

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     dword [r12], eax

    mov     rcx, [rsp]          ; advance
    add     [rbx + StrReader.ptr], rcx

    ; update col (simplified — counts codepoints not display width)
    add     [rbx + StrReader.col], rcx

    mov     rsp, rbp

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rcp_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_reader_read_cp

; -----------------------------------------------------------------------------
; str_reader_peek_cp
;
; Peek at next codepoint without advancing.
; -----------------------------------------------------------------------------

STR_FUNC str_reader_peek_cp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrReader.ptr]
    cmp     rax, [rdi + StrReader.end]
    jae     .pkcp_end

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rax
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked

    mov     dword [r12], eax    ; cp (advance NOT applied)

    mov     rsp, rbp
    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pkcp_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_reader_peek_cp

; -----------------------------------------------------------------------------
; str_reader_read_line
;
; Read bytes until LF or end of input.
; Returns a StrSlice into the source buffer (no copy).
; The LF is consumed but NOT included in the result.
;
; Signature:
;   int64_t str_reader_read_line(StrReader *reader, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_reader_read_line

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     r8, [rdi + StrReader.ptr]
    mov     r9, [rdi + StrReader.end]

    ; check exhausted
    cmp     r8, r9
    jae     .rl_end

    ; scan forward to LF or end
    mov     r10, r8             ; line start
    mov     r11, r8             ; scan ptr

.rl_scan:
    cmp     r11, r9
    jae     .rl_eof

    movzx   eax, byte [r11]

    cmp     al, 0x0A            ; LF
    je      .rl_found_lf

    cmp     al, 0x0D            ; CR
    je      .rl_found_cr

    inc     r11
    jmp     .rl_scan

.rl_found_cr:
    ; skip CR, check for LF
    mov     [rsi + StrSlice.ptr], r10
    mov     rax, r11
    sub     rax, r10
    mov     [rsi + StrSlice.len], rax

    inc     r11
    cmp     r11, r9
    jae     .rl_update_ptr

    movzx   eax, byte [r11]
    cmp     al, 0x0A
    jne     .rl_update_ptr
    inc     r11
    jmp     .rl_update_ptr

.rl_found_lf:
    mov     [rsi + StrSlice.ptr], r10
    mov     rax, r11
    sub     rax, r10
    mov     [rsi + StrSlice.len], rax
    inc     r11                 ; skip LF
    jmp     .rl_update_ptr

.rl_eof:
    mov     [rsi + StrSlice.ptr], r10
    mov     rax, r11
    sub     rax, r10
    mov     [rsi + StrSlice.len], rax

.rl_update_ptr:
    mov     [rdi + StrReader.ptr], r11
    inc     qword [rdi + StrReader.line]
    mov     qword [rdi + StrReader.col], 1

    xor     eax, eax
    pop     rbp
    ret

.rl_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_reader_read_line

; -----------------------------------------------------------------------------
; str_reader_skip
;
; Advance position by N bytes without reading.
;
; Signature:
;   int64_t str_reader_skip(StrReader *reader, uint64_t n)
; -----------------------------------------------------------------------------

STR_FUNC str_reader_skip

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrReader.ptr]
    add     rax, rsi

    ; clamp to end
    cmp     rax, [rdi + StrReader.end]
    jbe     .sk_ok
    mov     rax, [rdi + StrReader.end]

.sk_ok:
    mov     [rdi + StrReader.ptr], rax
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_reader_skip

; -----------------------------------------------------------------------------
; str_reader_remaining — bytes left to read
; str_reader_is_done   — check if exhausted
; str_reader_pos       — current byte offset from start
; -----------------------------------------------------------------------------

STR_FUNC str_reader_remaining

    test    rdi, rdi
    jz      .rr_zero

    mov     rax, [rdi + StrReader.end]
    sub     rax, [rdi + StrReader.ptr]
    pop     rbp
    ret

.rr_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_reader_remaining

STR_FUNC str_reader_is_done

    test    rdi, rdi
    jz      .rid_true

    mov     rax, [rdi + StrReader.ptr]
    cmp     rax, [rdi + StrReader.end]
    setae   al
    movzx   eax, al
    pop     rbp
    ret

.rid_true:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_reader_is_done