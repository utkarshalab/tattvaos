; =============================================================================
; str/search/find_any.asm
; Substring match sets searching (strpbrk-like).
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
; str_find_any_of
;
; Find first byte in src that appears in chars set.
;
; Signature:
;   int64_t str_find_any_of(const StrSlice *src, const StrSlice *chars,
;                           uint64_t *out_pos)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — chars (StrSlice*)
;   RDX  — out_pos (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_find_any_of
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; 32 bytes bitmap + 8 bytes padding (align stack)

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rdx                    ; out_pos

    ; Zero 32-byte bitmap
    xor     eax, eax
    mov     [rsp], rax
    mov     [rsp + 8], rax
    mov     [rsp + 16], rax
    mov     [rsp + 24], rax

    ; Populate bitmap from chars
    mov     r8, [rsi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.len]
    xor     rcx, rcx

.pop_loop:
    cmp     rcx, r9
    je      .pop_done
    movzx   eax, byte [r8 + rcx]
    bts     [rsp], eax
    inc     rcx
    jmp     .pop_loop

.pop_done:
    xor     rcx, rcx                    ; offset = 0

.scan_loop:
    cmp     rcx, r12
    je      .not_found

    movzx   eax, byte [rbx + rcx]
    bt      [rsp], eax
    jc      .found

    inc     rcx
    jmp     .scan_loop

.found:
    mov     [r13], rcx
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.not_found:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND
STR_ENDFUNC str_find_any_of

; -----------------------------------------------------------------------------
; str_find_none_of
;
; Find first byte in src that does NOT appear in chars set.
;
; Signature:
;   int64_t str_find_none_of(const StrSlice *src, const StrSlice *chars,
;                            uint64_t *out_pos)
; -----------------------------------------------------------------------------
STR_FUNC str_find_none_of
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rdx                    ; out_pos

    ; Zero bitmap
    xor     eax, eax
    mov     [rsp], rax
    mov     [rsp + 8], rax
    mov     [rsp + 16], rax
    mov     [rsp + 24], rax

    ; Populate bitmap
    mov     r8, [rsi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.len]
    xor     rcx, rcx

.pop_loop:
    cmp     rcx, r9
    je      .pop_done
    movzx   eax, byte [r8 + rcx]
    bts     [rsp], eax
    inc     rcx
    jmp     .pop_loop

.pop_done:
    xor     rcx, rcx

.scan_loop:
    cmp     rcx, r12
    je      .not_found

    movzx   eax, byte [rbx + rcx]
    bt      [rsp], eax
    jnc     .found                      ; jump if NOT in set (carry is 0)

    inc     rcx
    jmp     .scan_loop

.found:
    mov     [r13], rcx
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.not_found:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND
STR_ENDFUNC str_find_none_of
