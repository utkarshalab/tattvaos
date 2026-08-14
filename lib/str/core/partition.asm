%ifndef GUARD_LIB_STR_CORE_PARTITION_ASM
%define GUARD_LIB_STR_CORE_PARTITION_ASM
; =============================================================================
; str/core/partition.asm
; String partitioning views.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   search/find.asm (str_find)
;   search/rfind.asm (str_rfind)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


section .text

; -----------------------------------------------------------------------------
; str_partition
;
; Split a string at the FIRST occurrence of a separator.
; Outputs are StrSlice views into the original string.
;
; Signature:
;   int64_t str_partition(const StrSlice *src, const StrSlice *sep,
;                         StrSlice *out_before, StrSlice *out_sep,
;                         StrSlice *out_after)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — sep (StrSlice*)
;   RDX  — out_before (StrSlice*)
;   RCX  — out_sep (StrSlice*)
;   R8   — out_after (StrSlice*)
; -----------------------------------------------------------------------------
STR_FUNC str_partition
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8              ; align stack

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; sep
    mov     r13, rdx            ; out_before
    mov     r14, rcx            ; out_sep
    mov     r15, r8             ; out_after

    ; Find first match
    mov     rdi, rbx
    mov     rsi, r12
    call    str_find
    test    rax, rax
    js      .not_found          ; negative RAX includes STR_ERR_NOT_FOUND and other errors

    ; Found match at index in RAX
    mov     r8, rax             ; index

    ; out_before = src[0..index]
    mov     rsi, [rbx + StrSlice.ptr]
    mov     [r13 + StrSlice.ptr], rsi
    mov     [r13 + StrSlice.len], r8

    ; out_sep = src[index..index+sep.len]
    mov     rcx, [r12 + StrSlice.len]
    lea     rsi, [rsi + r8]     ; src.ptr + index
    mov     [r14 + StrSlice.ptr], rsi
    mov     [r14 + StrSlice.len], rcx

    ; out_after = src[index+sep.len..]
    add     rsi, rcx            ; src.ptr + index + sep.len
    mov     [r15 + StrSlice.ptr], rsi
    mov     rdi, [rbx + StrSlice.len]
    sub     rdi, r8
    sub     rdi, rcx            ; src.len - index - sep.len
    mov     [r15 + StrSlice.len], rdi

    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.not_found:
    ; out_before = src
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]
    mov     [r13 + StrSlice.ptr], rsi
    mov     [r13 + StrSlice.len], rcx

    ; out_sep = empty
    mov     qword [r14 + StrSlice.ptr], 0
    mov     qword [r14 + StrSlice.len], 0

    ; out_after = empty
    mov     qword [r15 + StrSlice.ptr], 0
    mov     qword [r15 + StrSlice.len], 0

    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok
STR_ENDFUNC str_partition

; -----------------------------------------------------------------------------
; str_rpartition
;
; Split a string at the LAST occurrence of a separator.
;
; Signature:
;   int64_t str_rpartition(const StrSlice *src, const StrSlice *sep,
;                          StrSlice *out_before, StrSlice *out_sep,
;                          StrSlice *out_after)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — sep (StrSlice*)
;   RDX  — out_before (StrSlice*)
;   RCX  — out_sep (StrSlice*)
;   R8   — out_after (StrSlice*)
; -----------------------------------------------------------------------------
STR_FUNC str_rpartition
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; align stack, allocate 8 bytes for pos at [rsp]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; sep
    mov     r13, rdx            ; out_before
    mov     r14, rcx            ; out_sep
    mov     r15, r8             ; out_after

    ; Find last match
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, rsp            ; out_pos pointer
    call    str_rfind
    test    rax, rax
    js      .not_found

    ; Found match at index [rsp]
    mov     r8, [rsp]           ; index

    ; out_before = src[0..index]
    mov     rsi, [rbx + StrSlice.ptr]
    mov     [r13 + StrSlice.ptr], rsi
    mov     [r13 + StrSlice.len], r8

    ; out_sep = src[index..index+sep.len]
    mov     rcx, [r12 + StrSlice.len]
    lea     rsi, [rsi + r8]     ; src.ptr + index
    mov     [r14 + StrSlice.ptr], rsi
    mov     [r14 + StrSlice.len], rcx

    ; out_after = src[index+sep.len..]
    add     rsi, rcx            ; src.ptr + index + sep.len
    mov     [r15 + StrSlice.ptr], rsi
    mov     rdi, [rbx + StrSlice.len]
    sub     rdi, r8
    sub     rdi, rcx            ; src.len - index - sep.len
    mov     [r15 + StrSlice.len], rdi

    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.not_found:
    ; out_before = src
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]
    mov     [r13 + StrSlice.ptr], rsi
    mov     [r13 + StrSlice.len], rcx

    ; out_sep = empty
    mov     qword [r14 + StrSlice.ptr], 0
    mov     qword [r14 + StrSlice.len], 0

    ; out_after = empty
    mov     qword [r15 + StrSlice.ptr], 0
    mov     qword [r15 + StrSlice.len], 0

    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok
STR_ENDFUNC str_rpartition

%endif ; GUARD_LIB_STR_CORE_PARTITION_ASM
