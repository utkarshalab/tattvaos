%ifndef GUARD_LIB_STR_CORE_REMOVE_ASM
%define GUARD_LIB_STR_CORE_REMOVE_ASM
; =============================================================================
; str/core/remove.asm
; String character and range removal functions.
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
; str_remove_range
;
; Remove bytes [start..end) from src.
;
; Signature:
;   int64_t str_remove_range(const StrSlice *src, uint64_t start, uint64_t end,
;                            uint8_t *dst, uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — start (uint64_t)
;   RDX  — end (uint64_t)
;   RCX  — dst (uint8_t*)
;   R8   — cap (uint64_t)
;   R9   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_remove_range
    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    cmp     rsi, rdx            ; start > end
    ja      .invalid_arg
    cmp     rdx, rax            ; end > src.len
    ja      .invalid_arg

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8              ; align stack

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; start
    mov     r13, rdx            ; end
    mov     r14, rcx            ; dst
    mov     r15, r8             ; cap

    ; total_len = start + (src.len - end)
    mov     rax, [rbx + StrSlice.len]
    sub     rax, r13
    add     rax, r12

    cmp     rax, r15            ; cap check
    ja      .too_small

    mov     [r9], rax           ; write out_len

    ; 1. Copy prefix: src[0..start]
    test    r12, r12
    jz      .prefix_copied
    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, r12
    call    str_copy_bytes
    test    rax, rax
    js      .err

.prefix_copied:
    ; 2. Copy suffix: src[end..]
    mov     rdx, [rbx + StrSlice.len]
    sub     rdx, r13            ; suffix_len = src.len - end
    test    rdx, rdx
    jz      .suffix_copied
    mov     rdi, r14
    add     rdi, r12            ; dst + start
    mov     rsi, [rbx + StrSlice.ptr]
    add     rsi, r13            ; src.ptr + end
    call    str_copy_bytes
    test    rax, rax
    js      .err

.suffix_copied:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.invalid_arg:
    ret_err STR_ERR_INVALID

.too_small:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_remove_range

; -----------------------------------------------------------------------------
; str_remove_char
;
; Remove all occurrences of byte `ch`.
;
; Signature:
;   int64_t str_remove_char(const StrSlice *src, uint8_t ch, uint8_t *dst,
;                           uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — ch (uint8_t)
;   RDX  — dst (uint8_t*)
;   RCX  — cap (uint64_t)
;   R8   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_remove_char
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rdx                    ; dst
    mov     r14, rcx                    ; cap
    mov     r15, r8                     ; out_len

    xor     r10, r10                    ; dst_offset = 0
    xor     rcx, rcx                    ; src_offset = 0

.loop:
    cmp     rcx, r12
    je      .done

    movzx   eax, byte [rbx + rcx]
    cmp     al, sil
    je      .skip_char

    cmp     r10, r14
    jae     .too_small
    mov     [r13 + r10], al
    inc     r10

.skip_char:
    inc     rcx
    jmp     .loop

.done:
    mov     [r15], r10
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_remove_char

; -----------------------------------------------------------------------------
; str_remove_chars
;
; Remove all bytes that appear in `chars` set.
;
; Signature:
;   int64_t str_remove_chars(const StrSlice *src, const StrSlice *chars,
;                            uint8_t *dst, uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — chars (StrSlice*)
;   RDX  — dst (uint8_t*)
;   RCX  — cap (uint64_t)
;   R8   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_remove_chars
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; 32 bytes bitmap + 8 bytes padding = 40 (keeps 16-byte alignment)

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rdx                    ; dst
    mov     r14, rcx                    ; cap
    mov     r15, r8                     ; out_len

    ; Zero 32-byte bitmap
    xor     eax, eax
    mov     [rsp], rax
    mov     [rsp + 8], rax
    mov     [rsp + 16], rax
    mov     [rsp + 24], rax

    ; Populate bitmap
    mov     r8, [rsi + StrSlice.ptr]    ; chars.ptr
    mov     r9, [rsi + StrSlice.len]    ; chars.len
    xor     rcx, rcx

.pop_loop:
    cmp     rcx, r9
    je      .pop_done
    movzx   eax, byte [r8 + rcx]
    bts     [rsp], eax                  ; set bit in 256-bit map
    inc     rcx
    jmp     .pop_loop

.pop_done:
    xor     r10, r10                    ; dst_offset = 0
    xor     rcx, rcx                    ; src_offset = 0

.filter_loop:
    cmp     rcx, r12
    je      .done

    movzx   eax, byte [rbx + rcx]
    bt      [rsp], eax
    jc      .skip_char

    cmp     r10, r14
    jae     .too_small
    mov     [r13 + r10], al
    inc     r10

.skip_char:
    inc     rcx
    jmp     .filter_loop

.done:
    mov     [r15], r10
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_remove_chars

%endif ; GUARD_LIB_STR_CORE_REMOVE_ASM
