%ifndef GUARD_LIB_STR_CORE_INSERT_ASM
%define GUARD_LIB_STR_CORE_INSERT_ASM
; =============================================================================
; str/core/insert.asm
; String insertion functions.
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

section .text

; -----------------------------------------------------------------------------
; str_insert_at
;
; Insert `insert` at byte position `pos` in `src`.
; Result = src[0..pos] + insert + src[pos..]
;
; Signature:
;   int64_t str_insert_at(const StrSlice *src, uint64_t pos,
;                         const StrSlice *insert, uint8_t *dst,
;                         uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — pos (uint64_t)
;   RDX  — insert (StrSlice*)
;   RCX  — dst (uint8_t*)
;   R8   — cap (uint64_t)
;   R9   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_insert_at
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    cmp     rsi, rax            ; check pos > src.len
    ja      .invalid_arg

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8              ; align stack

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; pos
    mov     r13, rdx            ; insert
    mov     r14, rcx            ; dst
    mov     r15, r8             ; cap

    ; total_len = src.len + insert.len
    mov     rax, [rbx + StrSlice.len]
    add     rax, [r13 + StrSlice.len]
    jc      .overflow

    cmp     rax, r15            ; check capacity
    ja      .too_small

    mov     [r9], rax           ; write out_len early before we clobber it or lose pointers

    ; 1. Copy prefix: src[0..pos]
    test    r12, r12
    jz      .prefix_copied
    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r12
    call    str_copy_bytes
    test    rax, rax
    js      .err

.prefix_copied:
    ; 2. Copy insert
    mov     rdx, [r13 + StrSlice.len]
    test    rdx, rdx
    jz      .insert_copied
    mov     rdi, r14
    add     rdi, r12            ; dst + pos
    mov     rsi, [r13 + StrSlice.ptr]
    call    str_copy_bytes
    test    rax, rax
    js      .err

.insert_copied:
    ; 3. Copy suffix: src[pos..]
    mov     rdx, [rbx + StrSlice.len]
    sub     rdx, r12            ; suffix_len = src.len - pos
    test    rdx, rdx
    jz      .suffix_copied
    mov     rdi, r14
    add     rdi, r12
    add     rdi, [r13 + StrSlice.len] ; dst + pos + insert.len
    mov     rsi, [rbx + StrSlice.ptr]
    add     rsi, r12            ; src.ptr + pos
    call    str_copy_bytes
    test    rax, rax
    js      .err

.suffix_copied:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.invalid_arg:
    ret_err STR_ERR_INVALID

.overflow:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_OVERFLOW

.too_small:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_insert_at

%endif ; GUARD_LIB_STR_CORE_INSERT_ASM
