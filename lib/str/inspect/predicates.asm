%ifndef GUARD_LIB_STR_INSPECT_PREDICATES_ASM
%define GUARD_LIB_STR_INSPECT_PREDICATES_ASM
; =============================================================================
; str/inspect/predicates.asm
; Whole-string predicate functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm   (str_utf8_decode_unchecked)
;   inspect/is_lower.asm (str_is_lower_cp)
;   inspect/is_upper.asm (str_is_upper_cp)
;   unicode/props.asm (str_cp_is_white_space, str_cp_is_id_start, str_cp_is_id_continue)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"






section .text

; -----------------------------------------------------------------------------
; str_is_all_ascii
;
; Returns 1 if all bytes in slice are < 0x80 (ASCII). Vacuously true if empty.
;
; Signature:
;   int64_t str_is_all_ascii(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_all_ascii
    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]
    xor     rdx, rdx            ; index = 0

.loop:
    cmp     rdx, rcx
    je      .yes

    movzx   r8d, byte [rax + rdx]
    cmp     r8b, 0x80
    jae     .no

    inc     rdx
    jmp     .loop

.yes:
    mov     eax, 1
    pop     rbp
    ret

.no:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_is_all_ascii

; -----------------------------------------------------------------------------
; str_is_all_upper
;
; Returns 1 if all letters in slice are uppercase, and at least one letter exists.
;
; Signature:
;   int64_t str_is_all_upper(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_all_upper
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 16             ; space for advance, align

    mov     rbx, [rdi + StrSlice.ptr]   ; current ptr
    mov     r12, [rdi + StrSlice.len]
    lea     r13, [rbx + r12]            ; end ptr
    xor     r14, r14            ; letter_count = 0

.loop:
    cmp     rbx, r13
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp            ; &advance
    call    str_utf8_decode_unchecked
    ; eax = cp

    ; advance rbx
    mov     rcx, [rsp]
    add     rbx, rcx

    ; check if lowercase
    mov     edi, eax
    push    rax
    call    str_is_lower_cp
    pop     rdx
    test    rax, rax
    jnz     .no                 ; if lowercase -> not all upper

    ; check if uppercase
    mov     edi, edx
    call    str_is_upper_cp
    test    rax, rax
    jz      .loop               ; if not uppercase (cased), ignore (non-letter)

    inc     r14                 ; letter_count++
    jmp     .loop

.done:
    test    r14, r14
    jz      .no                 ; no letters -> returns 0

    mov     eax, 1
    add     rsp, 16
    pop_regs r14, r13, r12, rbx
    ret

.no:
    xor     eax, eax
    add     rsp, 16
    pop_regs r14, r13, r12, rbx
    ret
STR_ENDFUNC str_is_all_upper

; -----------------------------------------------------------------------------
; str_is_all_lower
;
; Returns 1 if all letters in slice are lowercase, and at least one letter exists.
;
; Signature:
;   int64_t str_is_all_lower(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_all_lower
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 16

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    lea     r13, [rbx + r12]
    xor     r14, r14            ; letter_count = 0

.loop:
    cmp     rbx, r13
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked

    mov     rcx, [rsp]
    add     rbx, rcx

    mov     edi, eax
    push    rax
    call    str_is_upper_cp
    pop     rdx
    test    rax, rax
    jnz     .no                 ; if uppercase -> not all lower

    mov     edi, edx
    call    str_is_lower_cp
    test    rax, rax
    jz      .loop               ; ignore non-letters

    inc     r14
    jmp     .loop

.done:
    test    r14, r14
    jz      .no

    mov     eax, 1
    add     rsp, 16
    pop_regs r14, r13, r12, rbx
    ret

.no:
    xor     eax, eax
    add     rsp, 16
    pop_regs r14, r13, r12, rbx
    ret
STR_ENDFUNC str_is_all_lower

; -----------------------------------------------------------------------------
; str_is_all_digits
;
; Returns 1 if all bytes in slice are ASCII '0'-'9'. Empty returns 0.
;
; Signature:
;   int64_t str_is_all_digits(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_all_digits
    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .no

    xor     rdx, rdx

.loop:
    cmp     rdx, rcx
    je      .yes

    movzx   r8d, byte [rax + rdx]
    cmp     r8b, '0'
    jb      .no
    cmp     r8b, '9'
    ja      .no

    inc     rdx
    jmp     .loop

.yes:
    mov     eax, 1
    pop     rbp
    ret

.no:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_is_all_digits

; -----------------------------------------------------------------------------
; str_is_all_space
;
; Returns 1 if all codepoints in slice are Unicode whitespace. Empty returns 0.
;
; Signature:
;   int64_t str_is_all_space(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_all_space
    guard_null rdi, STR_ERR_NULL

    mov     r12, [rdi + StrSlice.len]
    test    r12, r12
    jz      .no_simple

    push_regs rbx, r12, r13
    sub     rsp, 16

    mov     rbx, [rdi + StrSlice.ptr]
    lea     r13, [rbx + r12]

.loop:
    cmp     rbx, r13
    jae     .yes

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked

    mov     rcx, [rsp]
    add     rbx, rcx

    mov     edi, eax
    call    str_cp_is_white_space
    test    rax, rax
    jz      .no

    jmp     .loop

.yes:
    mov     eax, 1
    add     rsp, 16
    pop_regs r13, r12, rbx
    ret

.no:
    xor     eax, eax
    add     rsp, 16
    pop_regs r13, r12, rbx
    ret

.no_simple:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_is_all_space

; -----------------------------------------------------------------------------
; str_is_identifier
;
; Returns 1 if slice is a valid Unicode identifier. Empty returns 0.
;
; Signature:
;   int64_t str_is_identifier(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_identifier
    guard_null rdi, STR_ERR_NULL

    mov     r12, [rdi + StrSlice.len]
    test    r12, r12
    jz      .no_simple

    push_regs rbx, r12, r13
    sub     rsp, 16

    mov     rbx, [rdi + StrSlice.ptr]
    lea     r13, [rbx + r12]

    ; 1. First codepoint must pass str_cp_is_id_start
    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    mov     edi, eax
    call    str_cp_is_id_start
    test    rax, rax
    jz      .no

.loop:
    cmp     rbx, r13
    jae     .yes

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    mov     edi, eax
    call    str_cp_is_id_continue
    test    rax, rax
    jz      .no

    jmp     .loop

.yes:
    mov     eax, 1
    add     rsp, 16
    pop_regs r13, r12, rbx
    ret

.no:
    xor     eax, eax
    add     rsp, 16
    pop_regs r13, r12, rbx
    ret

.no_simple:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_is_identifier

; -----------------------------------------------------------------------------
; str_is_printable_str
;
; Returns 1 if all codepoints are printable (no controls except space).
;
; Signature:
;   int64_t str_is_printable_str(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_printable_str
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13
    sub     rsp, 16

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    lea     r13, [rbx + r12]

.loop:
    cmp     rbx, r13
    jae     .yes

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    ; check if ASCII or Latin-1 control
    cmp     eax, 0x20
    jb      .no                 ; 0x00..0x1F are controls
    cmp     eax, 0x7F
    je      .no                 ; 0x7F is DEL
    cmp     eax, 0x80
    jb      .loop
    cmp     eax, 0x9F
    jbe     .no                 ; 0x80..0x9F are Latin-1 controls

    jmp     .loop

.yes:
    mov     eax, 1
    add     rsp, 16
    pop_regs r13, r12, rbx
    ret

.no:
    xor     eax, eax
    add     rsp, 16
    pop_regs r13, r12, rbx
    ret
STR_ENDFUNC str_is_printable_str

; -----------------------------------------------------------------------------
; str_is_palindrome
;
; Returns 1 if slice is a byte-level palindrome. Vacuously true if empty.
;
; Signature:
;   int64_t str_is_palindrome(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_palindrome
    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .yes

    xor     rdx, rdx            ; i = 0

.loop:
    mov     r8, rcx
    shr     r8, 1               ; r8 = len / 2
    cmp     rdx, r8
    jae     .yes

    mov     r9, rcx
    sub     r9, 1
    sub     r9, rdx             ; r9 = len - 1 - i

    movzx   r10d, byte [rax + rdx]
    movzx   r11d, byte [rax + r9]
    cmp     r10b, r11b
    jne     .no

    inc     rdx
    jmp     .loop

.yes:
    mov     eax, 1
    pop     rbp
    ret

.no:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_is_palindrome

%endif ; GUARD_LIB_STR_INSPECT_PREDICATES_ASM
