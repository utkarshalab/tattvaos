%ifndef GUARD_LIB_STR_CORE_CHOMP_ASM
%define GUARD_LIB_STR_CORE_CHOMP_ASM
; =============================================================================
; str/core/chomp.asm
; String chomp, chop, and simplified line counting functions.
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
; str_chomp
;
; Strip exactly one trailing line ending (\n or \r\n) if present.
;
; Signature:
;   int64_t str_chomp(const StrSlice *src, StrSlice *out)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — out (StrSlice*)
; -----------------------------------------------------------------------------
STR_FUNC str_chomp
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .empty

    ; check last byte: ptr[len - 1]
    movzx   edx, byte [rax + rcx - 1]
    cmp     dl, 0x0A            ; \n
    jne     .no_chomp

    ; we have \n, check if preceded by \r
    cmp     rcx, 2
    jb      .lf_only

    movzx   edx, byte [rax + rcx - 2]
    cmp     dl, 0x0D            ; \r
    je      .crlf

.lf_only:
    dec     rcx                 ; strip \n
    jmp     .no_chomp

.crlf:
    sub     rcx, 2              ; strip \r\n

.no_chomp:
    mov     [rsi + StrSlice.ptr], rax
    mov     [rsi + StrSlice.len], rcx
    ret_ok

.empty:
    mov     qword [rsi + StrSlice.ptr], 0
    mov     qword [rsi + StrSlice.len], 0
    ret_ok
STR_ENDFUNC str_chomp

; -----------------------------------------------------------------------------
; str_chop
;
; Remove the last byte.
;
; Signature:
;   int64_t str_chop(const StrSlice *src, StrSlice *out)
; -----------------------------------------------------------------------------
STR_FUNC str_chop
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .empty

    dec     rcx                 ; remove last byte

.empty:
    mov     [rsi + StrSlice.ptr], rax
    mov     [rsi + StrSlice.len], rcx
    ret_ok
STR_ENDFUNC str_chop

; -----------------------------------------------------------------------------
; str_count_lines
;
; Count newlines (\n) in string. Adds 1 if non-empty and doesn't end in \n.
;
; Signature:
;   uint64_t str_count_lines(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_count_lines
    guard_null rdi, 0

    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .zero

    xor     r8, r8              ; index = 0
    xor     r9, r9              ; newline_count = 0

.loop:
    cmp     r8, rcx
    je      .loop_end

    movzx   r10d, byte [rax + r8]
    cmp     r10b, 0x0A          ; \n
    jne     .next
    inc     r9                  ; newline_count++

.next:
    inc     r8
    jmp     .loop

.loop_end:
    ; check if last byte is \n
    movzx   r10d, byte [rax + rcx - 1]
    cmp     r10b, 0x0A
    je      .ends_with_lf

    inc     r9                  ; add 1 if does not end with \n

.ends_with_lf:
    mov     rax, r9
    pop     rbp
    ret

.zero:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_count_lines

%endif ; GUARD_LIB_STR_CORE_CHOMP_ASM
