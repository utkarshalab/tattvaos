%ifndef GUARD_LIB_STR_FORMAT_WRAP_ASM
%define GUARD_LIB_STR_FORMAT_WRAP_ASM
; =============================================================================
; str/format/wrap.asm
; Word wrapping, indent, and dedent functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/lines.asm (str_lines_next)
;   core/copy.asm  (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


section .text

; -----------------------------------------------------------------------------
; str_indent
;
; Prefix every line with `indent`.
;
; Signature:
;   int64_t str_indent(const StrSlice *src, const StrSlice *indent,
;                      uint8_t *dst, uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — indent (StrSlice*)
;   RDX  — dst (uint8_t*)
;   RCX  — cap (uint64_t)
;   R8   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_indent
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 48             ; space for out_line [rsp..15], next_offset [rsp+16], dst_offset [rsp+24], out_len [rsp+32]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; indent
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     [rsp + 32], r8      ; save out_len ptr

    mov     qword [rsp + 24], 0 ; dst_offset = 0
    xor     rsi, rsi            ; offset = 0

.loop:
    mov     rdi, rbx
    mov     rdx, rsp            ; out_line (rsp)
    lea     rcx, [rsp + 16]     ; out_next_offset
    push    rsi
    call    str_lines_next
    pop     rsi
    test    rax, rax
    js      .loop_end

    ; write indent
    mov     rcx, [r12 + StrSlice.len]
    test    rcx, rcx
    jz      .write_line

    mov     rax, [rsp + 24]      ; dst_offset
    add     rax, rcx
    cmp     rax, r14
    ja      .too_small

    mov     rdi, r13
    add     rdi, [rsp + 24]
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rdx, rcx
    call    str_copy_bytes
    test    rax, rax
    js      .err
    add     [rsp + 24], rdx

.write_line:
    ; write line content
    mov     rcx, [rsp + StrSlice.len]
    test    rcx, rcx
    jz      .write_ending

    mov     rax, [rsp + 24]
    add     rax, rcx
    cmp     rax, r14
    ja      .too_small

    mov     rdi, r13
    add     rdi, [rsp + 24]
    mov     rsi, [rsp + StrSlice.ptr]
    mov     rdx, rcx
    call    str_copy_bytes
    test    rax, rax
    js      .err
    add     [rsp + 24], rdx

.write_ending:
    ; write exact line ending from original string
    ; ending starts at: src.ptr + offset + line.len
    ; ending length = next_offset - offset - line.len
    mov     rax, [rsp + 16]     ; next_offset
    ; retrieve offset (which we saved/passed as rsi)
    ; wait, we popped rsi, but we need to track what offset was at the start of this iteration.
    ; Let's retrieve it from next_offset or keep track of it.
    ; Actually, let's keep track of current offset in r15!
    ; Let's rewrite this section using r15 to store `offset`.
    jmp     .err
STR_ENDFUNC str_indent

; -----------------------------------------------------------------------------
; Clean implementation of str_indent
; -----------------------------------------------------------------------------

STR_FUNC str_indent
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 48             ; out_line [rsp], next_offset [rsp+16], dst_offset [rsp+24], out_len [rsp+32]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; indent
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     [rsp + 32], r8      ; out_len ptr

    mov     qword [rsp + 24], 0 ; dst_offset = 0
    xor     r15, r15            ; current_offset = 0

.ind_loop:
    mov     rdi, rbx
    mov     rsi, r15            ; offset
    mov     rdx, rsp            ; out_line
    lea     rcx, [rsp + 16]     ; out_next_offset
    call    str_lines_next
    test    rax, rax
    js      .ind_loop_end

    ; 1. Copy indent
    mov     rcx, [r12 + StrSlice.len]
    test    rcx, rcx
    jz      .ind_write_line

    mov     rax, [rsp + 24]
    add     rax, rcx
    cmp     rax, r14
    ja      .ind_too_small

    mov     rdi, r13
    add     rdi, [rsp + 24]
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rdx, rcx
    call    str_copy_bytes
    add     [rsp + 24], rdx

.ind_write_line:
    ; 2. Copy line
    mov     rcx, [rsp + StrSlice.len]
    test    rcx, rcx
    jz      .ind_write_ending

    mov     rax, [rsp + 24]
    add     rax, rcx
    cmp     rax, r14
    ja      .ind_too_small

    mov     rdi, r13
    add     rdi, [rsp + 24]
    mov     rsi, [rsp + StrSlice.ptr]
    mov     rdx, rcx
    call    str_copy_bytes
    add     [rsp + 24], rdx

.ind_write_ending:
    ; 3. Copy line ending
    mov     rax, [rsp + 16]     ; next_offset
    sub     rax, r15            ; next_offset - offset
    mov     rcx, [rsp + StrSlice.len]
    sub     rax, rcx            ; ending_len = next_offset - offset - line.len
    test    rax, rax
    jz      .ind_next

    mov     rdx, [rsp + 24]
    add     rdx, rax
    cmp     rdx, r14
    ja      .ind_too_small

    mov     rdi, r13
    add     rdi, [rsp + 24]
    mov     rsi, [rbx + StrSlice.ptr]
    add     rsi, r15
    add     rsi, [rsp + StrSlice.len] ; src.ptr + offset + line.len
    mov     rdx, rax
    call    str_copy_bytes
    add     [rsp + 24], rdx

.ind_next:
    mov     r15, [rsp + 16]     ; offset = next_offset
    jmp     .ind_loop

.ind_loop_end:
    cmp     rax, STR_ERR_ITER_END
    jne     .ind_err

    mov     rax, [rsp + 32]
    mov     rcx, [rsp + 24]
    mov     [rax], rcx
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.ind_too_small:
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.ind_err:
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_indent

; -----------------------------------------------------------------------------
; str_dedent
;
; Remove common leading whitespace prefix from every line.
;
; Signature:
;   int64_t str_dedent(const StrSlice *src, uint8_t *dst,
;                      uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_dedent
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 48             ; out_line [rsp], next_offset [rsp+16], dst_offset [rsp+24], out_len [rsp+32]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     [rsp + 32], rcx     ; save out_len ptr

    ; First pass: find minimum common indent
    mov     r14, -1             ; min_indent = -1 (infinity)
    xor     r15, r15            ; offset = 0

.pass1_loop:
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, rsp
    lea     rcx, [rsp + 16]
    call    str_lines_next
    test    rax, rax
    js      .pass1_done

    ; count leading space/tab on this line
    mov     r8, [rsp + StrSlice.ptr]
    mov     r9, [rsp + StrSlice.len]
    xor     rcx, rcx            ; count = 0

.count_loop:
    cmp     rcx, r9
    je      .line_is_whitespace
    movzx   eax, byte [r8 + rcx]
    cmp     al, ' '
    je      .inc_count
    cmp     al, 0x09            ; tab
    je      .inc_count
    jmp     .count_done

.inc_count:
    inc     rcx
    jmp     .count_loop

.line_is_whitespace:
    ; if line is entirely whitespace, ignore it for min_indent calculation
    jmp     .pass1_next

.count_done:
    ; rcx = leading whitespace count
    cmp     r14, -1
    je      .first_min
    cmp     rcx, r14
    jae     .pass1_next
.first_min:
    mov     r14, rcx

.pass1_next:
    mov     r15, [rsp + 16]     ; offset = next_offset
    jmp     .pass1_loop

.pass1_done:
    cmp     r14, -1
    jne     .has_min
    xor     r14, r14            ; no non-empty lines -> min_indent = 0
.has_min:

    ; Second pass: copy lines skipping min_indent spaces
    mov     qword [rsp + 24], 0 ; dst_offset = 0
    xor     r15, r15            ; offset = 0

.pass2_loop:
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, rsp
    lea     rcx, [rsp + 16]
    call    str_lines_next
    test    rax, rax
    js      .pass2_done

    mov     rsi, [rsp + StrSlice.ptr]
    mov     rdx, [rsp + StrSlice.len]

    ; check if we should skip min_indent
    cmp     rdx, r14
    jbe     .skip_all_content

    ; copy content starting at min_indent
    add     rsi, r14
    sub     rdx, r14

    mov     rax, [rsp + 24]
    add     rax, rdx
    cmp     rax, r13
    ja      .ded_too_small

    mov     rdi, r12
    add     rdi, [rsp + 24]
    call    str_copy_bytes
    add     [rsp + 24], rdx
    jmp     .write_ending

.skip_all_content:
    ; line is shorter than min_indent (only has whitespace) -> write nothing

.write_ending:
    ; copy line ending
    mov     rax, [rsp + 16]
    sub     rax, r15
    mov     rcx, [rsp + StrSlice.len]
    sub     rax, rcx            ; ending_len

    test    rax, rax
    jz      .pass2_next

    mov     rdx, [rsp + 24]
    add     rdx, rax
    cmp     rdx, r13
    ja      .ded_too_small

    mov     rdi, r12
    add     rdi, [rsp + 24]
    mov     rsi, [rbx + StrSlice.ptr]
    add     rsi, r15
    add     rsi, [rsp + StrSlice.len]
    mov     rdx, rax
    call    str_copy_bytes
    add     [rsp + 24], rdx

.pass2_next:
    mov     r15, [rsp + 16]
    jmp     .pass2_loop

.pass2_done:
    mov     rax, [rsp + 32]
    mov     rcx, [rsp + 24]
    mov     [rax], rcx
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.ded_too_small:
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_dedent

; -----------------------------------------------------------------------------
; str_word_wrap
;
; Wrap text to a maximum line length.
;
; Signature:
;   int64_t str_word_wrap(const StrSlice *src, uint64_t width,
;                         uint8_t *dst, uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_word_wrap
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; space for dst_offset [rsp], col [rsp+8], line_start [rsp+16], last_space_idx [rsp+24], out_len [rsp+32]

    mov     rbx, [rdi + StrSlice.ptr]   ; src_ptr
    mov     r12, [rdi + StrSlice.len]   ; src_len
    mov     r13, rdx                    ; dst
    mov     r14, rcx                    ; cap
    mov     [rsp + 32], r8              ; save out_len ptr

    ; default width to 1 if 0
    test    rsi, rsi
    jnz     .width_ok
    mov     rsi, 1
.width_ok:

    mov     qword [rsp], 0              ; dst_offset = 0
    mov     qword [rsp + 8], 0          ; col = 0
    mov     qword [rsp + 16], 0         ; line_start = 0
    mov     qword [rsp + 24], -1        ; last_space_idx = -1

    xor     rcx, rcx                    ; i = 0

.wrap_loop:
    cmp     rcx, r12
    jae     .wrap_done

    movzx   eax, byte [rbx + rcx]
    
    cmp     al, 0x0A                    ; \n
    je      .handle_lf

    cmp     al, ' '
    je      .handle_space

    ; normal character
    mov     rdx, [rsp + 8]              ; col
    cmp     rdx, rsi                    ; col >= width?
    jae     .wrap_needed

    inc     qword [rsp + 8]             ; col++
    inc     rcx
    jmp     .wrap_loop

.handle_space:
    mov     [rsp + 24], rcx             ; last_space_idx = i
    mov     rdx, [rsp + 8]
    cmp     rdx, rsi
    jae     .wrap_needed

    inc     qword [rsp + 8]
    inc     rcx
    jmp     .wrap_loop

.handle_lf:
    ; output line_start..i + '\n'
    mov     r8, [rsp + 16]              ; line_start
    mov     rdx, rcx
    sub     rdx, r8                     ; len = i - line_start
    test    rdx, rdx
    jz      .lf_only_write

    ; check cap
    mov     rax, [rsp]
    add     rax, rdx
    inc     rax                         ; space for \n
    cmp     rax, r14
    ja      .too_small

    mov     rdi, r13
    add     rdi, [rsp]
    lea     rsi, [rbx + r8]             ; src_ptr + line_start
    push    rcx
    push    rsi
    call    str_copy_bytes
    pop     rsi
    pop     rcx
    add     [rsp], rdx

.lf_only_write:
    mov     rax, [rsp]
    cmp     rax, r14
    jae     .too_small
    mov     byte [r13 + rax], 0x0A
    inc     qword [rsp]

    lea     rax, [rcx + 1]
    mov     [rsp + 16], rax             ; line_start = i + 1
    mov     qword [rsp + 8], 0          ; col = 0
    mov     qword [rsp + 24], -1        ; last_space_idx = -1
    inc     rcx
    jmp     .wrap_loop

.wrap_needed:
    ; we need to wrap at last_space_idx or break-word
    mov     rax, [rsp + 24]             ; last_space_idx
    cmp     rax, -1
    je      .break_word

    ; Wrap at space: output line_start..last_space_idx + '\n'
    mov     r8, [rsp + 16]              ; line_start
    mov     rdx, rax
    sub     rdx, r8                     ; len = last_space_idx - line_start

    mov     r9, [rsp]
    add     r9, rdx
    inc     r9
    cmp     r9, r14
    ja      .too_small

    mov     rdi, r13
    add     rdi, [rsp]
    lea     rsi, [rbx + r8]
    push    rax
    call    str_copy_bytes
    pop     rax
    add     [rsp], rdx

    ; write newline
    mov     r9, [rsp]
    mov     byte [r13 + r9], 0x0A
    inc     qword [rsp]

    ; skip trailing/leading spaces: line_start = last_space_idx + 1
    inc     rax
.skip_leading_spaces:
    cmp     rax, r12
    jae     .leading_spaces_done
    cmp     byte [rbx + rax], ' '
    jne     .leading_spaces_done
    inc     rax
    jmp     .skip_leading_spaces

.leading_spaces_done:
    mov     [rsp + 16], rax             ; line_start = advanced pos
    mov     rcx, rax                    ; backtrack i to line_start
    mov     qword [rsp + 8], 0
    mov     qword [rsp + 24], -1
    jmp     .wrap_loop

.break_word:
    ; break-word at current position i
    mov     r8, [rsp + 16]              ; line_start
    mov     rdx, rcx
    sub     rdx, r8                     ; len = i - line_start

    mov     r9, [rsp]
    add     r9, rdx
    inc     r9
    cmp     r9, r14
    ja      .too_small

    mov     rdi, r13
    add     rdi, [rsp]
    lea     rsi, [rbx + r8]
    push    rcx
    call    str_copy_bytes
    pop     rcx
    add     [rsp], rdx

    mov     r9, [rsp]
    mov     byte [r13 + r9], 0x0A
    inc     qword [rsp]

    mov     [rsp + 16], rcx             ; line_start = i
    mov     qword [rsp + 8], 0
    mov     qword [rsp + 24], -1
    jmp     .wrap_loop

.wrap_done:
    ; write remaining text from line_start to end
    mov     r8, [rsp + 16]
    cmp     r8, r12
    jae     .wrap_finalize

    mov     rdx, r12
    sub     rdx, r8                     ; remaining len

    mov     rax, [rsp]
    add     rax, rdx
    cmp     rax, r14
    ja      .too_small

    mov     rdi, r13
    add     rdi, [rsp]
    lea     rsi, [rbx + r8]
    call    str_copy_bytes
    add     [rsp], rdx

.wrap_finalize:
    mov     rax, [rsp + 32]             ; out_len
    mov     rcx, [rsp]                  ; dst_offset
    mov     [rax], rcx
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_word_wrap

%endif ; GUARD_LIB_STR_FORMAT_WRAP_ASM
