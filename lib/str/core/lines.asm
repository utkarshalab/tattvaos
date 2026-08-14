%ifndef GUARD_LIB_STR_CORE_LINES_ASM
%define GUARD_LIB_STR_CORE_LINES_ASM
; =============================================================================
; str/core/lines.asm
; Line splitting, counting, and retrieval.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_lines_next
;
; Find next line starting at offset. Line ends at \n, \r\n, or end of string.
;
; Signature:
;   int64_t str_lines_next(const StrSlice *src, uint64_t offset,
;                          StrSlice *out_line, uint64_t *out_next_offset)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — offset (byte position to start search)
;   RDX  — out_line (StrSlice* to receive the line)
;   RCX  — out_next_offset (uint64_t* to receive next start offset)
; -----------------------------------------------------------------------------
STR_FUNC str_lines_next
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    cmp     rsi, rax
    jae     .iter_end

    push_regs rbx, r12
    mov     rbx, [rdi + StrSlice.ptr]   ; src.ptr
    mov     r12, rax                    ; src.len

    lea     rax, [rbx + rsi]            ; scan_ptr = src.ptr + offset
    lea     r8, [rbx + r12]             ; end_ptr = src.ptr + src.len

.scan_loop:
    cmp     rax, r8
    je      .reach_end

    movzx   r10d, byte [rax]
    cmp     r10b, 0x0A                  ; \n
    je      .reach_lf

    cmp     r10b, 0x0D                  ; \r
    je      .reach_cr

    inc     rax
    jmp     .scan_loop

.reach_end:
    ; Line from offset to end of string
    mov     r10, rax
    lea     rsi, [rbx + rsi]            ; start_ptr = src.ptr + offset
    sub     r10, rsi                    ; len = end_ptr - start_ptr
    mov     [rdx + StrSlice.ptr], rsi
    mov     [rdx + StrSlice.len], r10
    mov     qword [rcx], r12            ; next_offset = src.len
    jmp     .ok

.reach_lf:
    ; Line ends at \n
    mov     r10, rax
    lea     rsi, [rbx + rsi]
    sub     r10, rsi                    ; line length
    mov     [rdx + StrSlice.ptr], rsi
    mov     [rdx + StrSlice.len], r10

    inc     rax                         ; skip \n
    sub     rax, rbx                    ; next_offset = scan_ptr - src.ptr
    mov     [rcx], rax
    jmp     .ok

.reach_cr:
    ; Line ends at \r
    mov     r10, rax
    lea     rsi, [rbx + rsi]
    sub     r10, rsi                    ; line length
    mov     [rdx + StrSlice.ptr], rsi
    mov     [rdx + StrSlice.len], r10

    ; check if followed by \n (CRLF)
    lea     r11, [rax + 1]
    cmp     r11, r8
    jae     .cr_only

    movzx   r9d, byte [r11]
    cmp     r9b, 0x0A                   ; is next char \n?
    je      .crlf

.cr_only:
    inc     rax                         ; skip \r
    sub     rax, rbx
    mov     [rcx], rax
    jmp     .ok

.crlf:
    add     rax, 2                      ; skip \r and \n
    sub     rax, rbx
    mov     [rcx], rax

.ok:
    pop_regs r12, rbx
    ret_ok

.iter_end:
    ret_err STR_ERR_ITER_END
STR_ENDFUNC str_lines_next

; -----------------------------------------------------------------------------
; str_lines_count
;
; Count number of lines in a StrSlice.
;
; Signature:
;   int64_t str_lines_count(const StrSlice *src, uint64_t *out_count)
; -----------------------------------------------------------------------------
STR_FUNC str_lines_count
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
    jz      .zero_lines

    push_regs rbx, r12, r13
    sub     rsp, 32             ; 32 bytes to store temp slice [rsp..15] and next_offset [rsp+16]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; out_count
    xor     r13, r13            ; count = 0
    xor     rsi, rsi            ; offset = 0

.loop:
    mov     rdi, rbx
    mov     rdx, rsp            ; out_line (rsp)
    lea     rcx, [rsp + 16]     ; out_next_offset (rsp+16)
    call    str_lines_next
    test    rax, rax
    js      .loop_end

    inc     r13                 ; count++
    mov     rsi, [rsp + 16]     ; offset = next_offset
    jmp     .loop

.loop_end:
    ; if we got STR_ERR_ITER_END, it is normal exit
    cmp     rax, STR_ERR_ITER_END
    jne     .err

    mov     [r12], r13
    add     rsp, 32
    pop_regs r13, r12, rbx
    ret_ok

.err:
    add     rsp, 32
    pop_regs r13, r12, rbx
    ret_err STR_ERR_INVALID

.zero_lines:
    mov     qword [rsi], 0
    ret_ok
STR_ENDFUNC str_lines_count

; -----------------------------------------------------------------------------
; str_nth_line
;
; Retrieve the Nth line of a StrSlice (0-indexed).
;
; Signature:
;   int64_t str_nth_line(const StrSlice *src, uint64_t n, StrSlice *out_line)
; -----------------------------------------------------------------------------
STR_FUNC str_nth_line
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 32             ; temp storage for next_offset [rsp+16]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; n
    mov     r13, rdx            ; out_line
    xor     r14, r14            ; current_index = 0
    xor     rsi, rsi            ; offset = 0

.loop:
    mov     rdi, rbx
    mov     rdx, r13            ; out_line directly
    lea     rcx, [rsp + 16]     ; out_next_offset
    call    str_lines_next
    test    rax, rax
    js      .loop_end

    cmp     r14, r12            ; is this index n?
    je      .found

    inc     r14
    mov     rsi, [rsp + 16]     ; offset = next_offset
    jmp     .loop

.loop_end:
    cmp     rax, STR_ERR_ITER_END
    je      .not_found
    jmp     .err

.found:
    add     rsp, 32
    pop_regs r14, r13, r12, rbx
    ret_ok

.not_found:
    add     rsp, 32
    pop_regs r14, r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND

.err:
    add     rsp, 32
    pop_regs r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_nth_line

%endif ; GUARD_LIB_STR_CORE_LINES_ASM
