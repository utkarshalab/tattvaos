; =============================================================================
; str/core/join.asm
; String join functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm   (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .text

; -----------------------------------------------------------------------------
; str_join
;
; Join an array of StrSlices with a separator.
;
; Signature:
;   int64_t str_join(const StrSlice *sep, const StrSlice *parts, uint64_t count,
;                    uint8_t *dst, uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — sep (StrSlice*, can be NULL or len=0)
;   RSI  — parts (StrSlice array)
;   RDX  — count (array length)
;   RCX  — dst buffer
;   R8   — cap
;   R9   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_join
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; align stack

    mov     rbx, rdi            ; sep
    mov     r12, rsi            ; parts
    mov     r13, rdx            ; count
    mov     r14, rcx            ; dst
    mov     r15, r8             ; cap
    mov     [rsp + 16], r9      ; save out_len ptr

    mov     qword [rsp + 8], 0  ; current_dst_offset = 0
    mov     qword [rsp + 0], 0  ; i = 0

    ; if count == 0, go to done
    test    r13, r13
    jz      .done

.loop:
    mov     rax, [rsp + 0]      ; i
    cmp     rax, r13
    je      .done

    ; if i > 0, write separator
    test    rax, rax
    jz      .write_part

    ; check if sep is valid and has length
    test    rbx, rbx
    jz      .write_part
    mov     rcx, [rbx + StrSlice.len]
    test    rcx, rcx
    jz      .write_part

    ; check separator capacity
    mov     rdi, [rsp + 8]      ; current_dst_offset
    add     rdi, rcx
    cmp     rdi, r15            ; cap
    ja      .too_small

    ; copy separator
    mov     rdi, r14
    add     rdi, [rsp + 8]      ; dst + current_dst_offset
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, rcx            ; sep.len
    call    str_copy_bytes
    test    rax, rax
    js      .err

    ; advance offset
    mov     rcx, [rbx + StrSlice.len]
    add     [rsp + 8], rcx

.write_part:
    ; parts[i] is at parts + i * 16 (STRSLICE_SIZE)
    mov     rax, [rsp + 0]      ; i
    shl     rax, 4              ; i * 16
    mov     rsi, r12
    add     rsi, rax            ; parts[i] address

    mov     rcx, [rsi + StrSlice.len]
    test    rcx, rcx
    jz      .part_written

    ; check part capacity
    mov     rdi, [rsp + 8]
    add     rdi, rcx
    cmp     rdi, r15
    ja      .too_small

    ; copy part
    mov     rdi, r14
    add     rdi, [rsp + 8]
    mov     rsi, [rsi + StrSlice.ptr]
    mov     rdx, rcx
    call    str_copy_bytes
    test    rax, rax
    js      .err

    ; advance offset
    add     [rsp + 8], rdx

.part_written:
    inc     qword [rsp + 0]     ; i++
    jmp     .loop

.done:
    ; write out_len
    mov     rax, [rsp + 16]
    mov     rcx, [rsp + 8]
    mov     [rax], rcx

    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_join
