%ifndef GUARD_LIB_STR_CORE_STRIP_AFFIX_ASM
%define GUARD_LIB_STR_CORE_STRIP_AFFIX_ASM
; =============================================================================
; str/core/strip_affix.asm
; Prefix and suffix stripping views.
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
; str_strip_prefix
;
; If `src` starts with `prefix`, `out` receives a view skipping `prefix`.
; Otherwise `out` receives the original `src` view.
;
; Signature:
;   int64_t str_strip_prefix(const StrSlice *src, const StrSlice *prefix,
;                            StrSlice *out)
;
; Returns:
;   RAX = 1   prefix found and stripped
;   RAX = 0   prefix not found
; -----------------------------------------------------------------------------
STR_FUNC str_strip_prefix
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    ; if src.len < prefix.len, no match
    cmp     rax, rcx
    jb      .no_match

    ; compare prefix
    test    rcx, rcx
    jz      .match              ; empty prefix always matches

    mov     r8, [rdi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.ptr]
    xor     r10, r10            ; index = 0

.loop:
    cmp     r10, rcx
    je      .match

    movzx   r11d, byte [r8 + r10]
    movzx   r10d, byte [r9 + r10] ; wait, using r10d clobbers index r10!
    ; Fix: use different registers!
    inc     r10                 ; wait, index is r10, let's keep it safe.
    ; Let's write this loop correctly.

.no_match:
    ; copy original src to out
    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]
    mov     [rdx + StrSlice.ptr], rax
    mov     [rdx + StrSlice.len], rcx
    xor     eax, eax            ; RAX = 0
    pop     rbp
    ret

; Let's write the correct function structure without clobbering indexes.
STR_ENDFUNC str_strip_prefix

; -----------------------------------------------------------------------------
; Actual clean implementations of str_strip_prefix and str_strip_suffix
; -----------------------------------------------------------------------------

STR_FUNC str_strip_prefix
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    cmp     rax, rcx
    jb      .no_match

    test    rcx, rcx
    jz      .match

    mov     r8, [rdi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.ptr]
    xor     r10, r10            ; index = 0

.compare_loop:
    cmp     r10, rcx
    je      .match

    movzx   r11d, byte [r8 + r10]
    movzx   eax,  byte [r9 + r10]
    cmp     r11b, al
    jne     .no_match

    inc     r10
    jmp     .compare_loop

.match:
    ; out = src[prefix.len..]
    mov     rax, [rdi + StrSlice.ptr]
    add     rax, rcx            ; src.ptr + prefix.len
    mov     [rdx + StrSlice.ptr], rax
    mov     rax, [rdi + StrSlice.len]
    sub     rax, rcx            ; src.len - prefix.len
    mov     [rdx + StrSlice.len], rax
    mov     eax, 1              ; RAX = 1 (predicate true)
    pop     rbp
    ret

.no_match:
    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]
    mov     [rdx + StrSlice.ptr], rax
    mov     [rdx + StrSlice.len], rcx
    xor     eax, eax            ; RAX = 0 (predicate false)
    pop     rbp
    ret
STR_ENDFUNC str_strip_prefix

; -----------------------------------------------------------------------------
; str_strip_suffix
;
; If `src` ends with `suffix`, `out` receives a view skipping `suffix`.
; Otherwise `out` receives the original `src` view.
;
; Signature:
;   int64_t str_strip_suffix(const StrSlice *src, const StrSlice *suffix,
;                            StrSlice *out)
;
; Returns:
;   RAX = 1   suffix found and stripped
;   RAX = 0   suffix not found
; -----------------------------------------------------------------------------
STR_FUNC str_strip_suffix
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    cmp     rax, rcx
    jb      .no_match

    test    rcx, rcx
    jz      .match

    mov     r8, [rdi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.ptr]
    
    ; start index in src = src.len - suffix.len
    mov     rdi, rax
    sub     rdi, rcx            ; rdi = start offset in src
    xor     r10, r10            ; suffix index = 0

.compare_loop:
    cmp     r10, rcx
    je      .match

    lea     rax, [rdi + r10]
    movzx   r11d, byte [r8 + rax]
    movzx   eax,  byte [r9 + r10]
    cmp     r11b, al
    jne     .no_match

    inc     r10
    jmp     .compare_loop

.match:
    ; out = src[0..src.len - suffix.len]
    ; RDI already contains (src.len - suffix.len)
    ; Restore original RDI pointer since we clobbered it as arg, wait!
    ; Ah, RDI was clobbered because it was an input register, but we need to write to RDX!
    ; Let's retrieve src pointer from stack or just reload it.
    ; But wait! We did "guard_null rdi, STR_ERR_NULL", RDI was not preserved.
    ; Actually, RDX is the 3rd argument (out). It is preserved!
    ; But we need RDI's original value (the address of the StrSlice src) to reload src.ptr.
    ; Since RDI was clobbered in the suffix start calculation, we cannot reload from RDI.
    ; Fix: Save RDI in a scratch register or avoid clobbering it.
    ; Let's redesign str_strip_suffix cleanly.
    jmp     .no_match
STR_ENDFUNC str_strip_suffix

; -----------------------------------------------------------------------------
; Correctly designed str_strip_suffix
; -----------------------------------------------------------------------------

STR_FUNC str_strip_suffix
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    mov     rcx, [rsi + StrSlice.len]

    cmp     rax, rcx
    jb      .suffix_no_match

    test    rcx, rcx
    jz      .suffix_match

    mov     r8, [rdi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.ptr]
    
    mov     r10, rax
    sub     r10, rcx            ; r10 = start offset in src
    xor     r11, r11            ; suffix index = 0

.suffix_compare_loop:
    cmp     r11, rcx
    je      .suffix_match

    lea     r12, [r10 + r11]
    movzx   r12d, byte [r8 + r12]
    movzx   eax,  byte [r9 + r11]
    cmp     r12b, al
    jne     .suffix_no_match

    inc     r11
    jmp     .suffix_compare_loop

.suffix_match:
    ; out = src[0..src.len - suffix.len]
    ; RAX still contains src.len, RCX is suffix.len
    mov     rsi, [rdi + StrSlice.ptr]
    mov     [rdx + StrSlice.ptr], rsi
    mov     rax, [rdi + StrSlice.len]
    sub     rax, rcx            ; src.len - suffix.len
    mov     [rdx + StrSlice.len], rax
    mov     eax, 1              ; RAX = 1
    pop     rbp
    ret

.suffix_no_match:
    mov     rsi, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]
    mov     [rdx + StrSlice.ptr], rsi
    mov     [rdx + StrSlice.len], rcx
    xor     eax, eax            ; RAX = 0
    pop     rbp
    ret
STR_ENDFUNC str_strip_suffix

%endif ; GUARD_LIB_STR_CORE_STRIP_AFFIX_ASM
