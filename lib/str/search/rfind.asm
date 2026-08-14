%ifndef GUARD_LIB_STR_SEARCH_RFIND_ASM
%define GUARD_LIB_STR_SEARCH_RFIND_ASM
; =============================================================================
; str/search/rfind.asm
; Reverse substring search functions.
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
; str_rfind
;
; Find the last occurrence of needle in haystack.
;
; Signature:
;   int64_t str_rfind(const StrSlice *haystack, const StrSlice *needle,
;                     uint64_t *out_pos)
;
; Arguments:
;   RDI  — haystack (StrSlice*)
;   RSI  — needle (StrSlice*)
;   RDX  — out_pos (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_rfind
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8              ; align stack

    mov     rbx, rdi            ; haystack
    mov     r12, rsi            ; needle
    mov     r13, rdx            ; out_pos

    mov     rax, [rbx + StrSlice.len]   ; h_len
    mov     r14, [r12 + StrSlice.len]   ; n_len

    ; if needle is empty, it matches at the very end
    test    r14, r14
    jz      .empty_needle

    ; if needle is longer than haystack, no match
    cmp     r14, rax
    ja      .not_found

    mov     r8,  [rbx + StrSlice.ptr]   ; h_ptr
    mov     r9,  [r12 + StrSlice.ptr]   ; n_ptr

    ; loop index: offset = h_len - n_len
    mov     r10, rax
    sub     r10, r14            ; start offset

.loop:
    ; compare needle at h_ptr + offset
    xor     rcx, rcx            ; compare index = 0

.compare_loop:
    cmp     rcx, r14
    je      .match_found

    lea     rax, [r10 + rcx]
    movzx   eax, byte [r8 + rax]
    movzx   edi, byte [r9 + rcx]
    cmp     al, dil
    jne     .mismatch

    inc     rcx
    jmp     .compare_loop

.mismatch:
    test    r10, r10
    jz      .not_found          ; reached offset 0, no match
    dec     r10                 ; offset--
    jmp     .loop

.match_found:
    mov     [r13], r10          ; write match offset
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.empty_needle:
    mov     [r13], rax          ; out_pos = h_len
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.not_found:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND
STR_ENDFUNC str_rfind

; -----------------------------------------------------------------------------
; str_rcontains
;
; Returns 1 if needle is found in haystack, 0 otherwise.
;
; Signature:
;   int64_t str_rcontains(const StrSlice *haystack, const StrSlice *needle)
; -----------------------------------------------------------------------------
STR_FUNC str_rcontains
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    sub     rsp, 16             ; space for out_pos at [rsp], keep 16-byte alignment
    mov     rdx, rsp            ; out_pos
    call    str_rfind
    test    rax, rax
    jnz     .not_found

    mov     eax, 1
    add     rsp, 16
    pop     rbp
    ret

.not_found:
    xor     eax, eax
    add     rsp, 16
    pop     rbp
    ret
STR_ENDFUNC str_rcontains

; -----------------------------------------------------------------------------
; str_last_index_of
;
; Returns index of last occurrence, or -1 if not found.
;
; Signature:
;   int64_t str_last_index_of(const StrSlice *haystack, const StrSlice *needle)
; -----------------------------------------------------------------------------
STR_FUNC str_last_index_of
    guard_null rdi, -1
    guard_null rsi, -1

    sub     rsp, 16             ; space for out_pos, align
    mov     rdx, rsp
    call    str_rfind
    test    rax, rax
    jnz     .not_found

    mov     rax, [rsp]          ; return position
    add     rsp, 16
    pop     rbp
    ret

.not_found:
    mov     rax, -1             ; return -1
    add     rsp, 16
    pop     rbp
    ret
STR_ENDFUNC str_last_index_of

%endif ; GUARD_LIB_STR_SEARCH_RFIND_ASM
