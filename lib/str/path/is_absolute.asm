; =============================================================================
; str/path/is_absolute.asm
; Path type predicates.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Functions:
;   str_path_is_absolute  — starts with /
;   str_path_is_relative  — does not start with /
;   str_path_is_root      — path is exactly "/"
;   str_path_has_trailing  — ends with /
;   str_path_depth        — count segments (number of / + 1 for relative)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

PATH_SEP    equ '/'

section .text

; -----------------------------------------------------------------------------
; str_path_is_absolute
; Returns: RAX = 1 absolute (starts with /), 0 relative
; -----------------------------------------------------------------------------

STR_FUNC str_path_is_absolute

    test    rdi, rdi
    jz      .pia_no

    mov     rsi, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .pia_no

    movzx   eax, byte [rsi]
    cmp     al, PATH_SEP
    sete    al
    movzx   eax, al
    pop     rbp
    ret

.pia_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_is_absolute

; -----------------------------------------------------------------------------
; str_path_is_relative
; Returns: RAX = 1 relative, 0 absolute
; -----------------------------------------------------------------------------

STR_FUNC str_path_is_relative

    call    str_path_is_absolute
    xor     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_path_is_relative

; -----------------------------------------------------------------------------
; str_path_is_root
; Returns: RAX = 1 if path is exactly "/", 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_path_is_root

    test    rdi, rdi
    jz      .pir_no

    mov     rcx, [rdi + StrSlice.len]
    cmp     rcx, 1
    jne     .pir_no

    mov     rsi, [rdi + StrSlice.ptr]
    movzx   eax, byte [rsi]
    cmp     al, PATH_SEP
    sete    al
    movzx   eax, al
    pop     rbp
    ret

.pir_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_is_root

; -----------------------------------------------------------------------------
; str_path_has_trailing
; Returns: RAX = 1 if path ends with /, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_path_has_trailing

    test    rdi, rdi
    jz      .pht_no

    mov     rsi, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .pht_no

    movzx   eax, byte [rsi + rcx - 1]
    cmp     al, PATH_SEP
    sete    al
    movzx   eax, al
    pop     rbp
    ret

.pht_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_has_trailing

; -----------------------------------------------------------------------------
; str_path_depth
;
; Count the number of path segments.
; "/home/raj/code" → 3
; "a/b/c" → 3
; "/" → 0 (root has no named segments)
; "" → 0
;
; Signature:
;   uint64_t str_path_depth(const StrSlice *path)
; -----------------------------------------------------------------------------

STR_FUNC str_path_depth

    test    rdi, rdi
    jz      .ppd_zero

    mov     rsi, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .ppd_zero

    xor     r8, r8              ; depth
    xor     r9d, r9d            ; in_segment flag
    xor     r10, r10            ; index

.ppd_loop:
    cmp     r10, rcx
    jae     .ppd_done

    movzx   eax, byte [rsi + r10]
    inc     r10

    cmp     al, PATH_SEP
    jne     .ppd_char

    ; separator: end of segment if we were in one
    test    r9d, r9d
    jz      .ppd_loop
    xor     r9d, r9d            ; no longer in segment
    jmp     .ppd_loop

.ppd_char:
    test    r9d, r9d
    jnz     .ppd_loop           ; already counting this segment

    mov     r9d, 1              ; entering a segment
    inc     r8                  ; count it
    jmp     .ppd_loop

.ppd_done:
    mov     rax, r8
    pop     rbp
    ret

.ppd_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_depth