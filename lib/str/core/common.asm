%ifndef GUARD_LIB_STR_CORE_COMMON_ASM
%define GUARD_LIB_STR_CORE_COMMON_ASM
; =============================================================================
; str/core/common.asm
; Common prefix and suffix length matching.
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
; str_common_prefix_len
;
; Returns the number of leading bytes that match between a and b.
;
; Signature:
;   uint64_t str_common_prefix_len(const StrSlice *a, const StrSlice *b)
; -----------------------------------------------------------------------------
STR_FUNC str_common_prefix_len
    guard_null rdi, 0
    guard_null rsi, 0

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    ; min_len = min(a.len, b.len)
    cmp     rax, rcx
    jbe     .min_ok
    mov     rax, rcx
.min_ok:
    test    rax, rax
    jz      .done_zero

    mov     r8, [rdi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.ptr]
    xor     rcx, rcx            ; index = 0

.loop:
    cmp     rcx, rax
    je      .done

    movzx   r10d, byte [r8 + rcx]
    movzx   r11d, byte [r9 + rcx]
    cmp     r10b, r11b
    jne     .done

    inc     rcx
    jmp     .loop

.done:
    mov     rax, rcx
    pop     rbp
    ret

.done_zero:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_common_prefix_len

; -----------------------------------------------------------------------------
; str_common_suffix_len
;
; Returns the number of trailing bytes that match between a and b.
;
; Signature:
;   uint64_t str_common_suffix_len(const StrSlice *a, const StrSlice *b)
; -----------------------------------------------------------------------------
STR_FUNC str_common_suffix_len
    guard_null rdi, 0
    guard_null rsi, 0

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    ; save length of both slices
    mov     r8, rax             ; a.len
    mov     r9, rcx             ; b.len

    ; min_len = min(a.len, b.len)
    cmp     rax, rcx
    jbe     .min_ok
    mov     rax, rcx
.min_ok:
    test    rax, rax
    jz      .done_zero

    mov     r10, [rdi + StrSlice.ptr]
    mov     r11, [rsi + StrSlice.ptr]
    xor     rcx, rcx            ; index = 0

.loop:
    cmp     rcx, rax
    je      .done

    ; compare from trailing offset: ptr + len - 1 - rcx
    mov     rdx, r8
    sub     rdx, 1
    sub     rdx, rcx
    movzx   r12d, byte [r10 + rdx]

    mov     rdx, r9
    sub     rdx, 1
    sub     rdx, rcx
    movzx   r13d, byte [r11 + rdx]

    cmp     r12b, r13b
    jne     .done

    inc     rcx
    jmp     .loop

.done:
    mov     rax, rcx
    pop     rbp
    ret

.done_zero:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_common_suffix_len

%endif ; GUARD_LIB_STR_CORE_COMMON_ASM
