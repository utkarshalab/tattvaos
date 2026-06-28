; =============================================================================
; str/convert/rot13.asm
; ROT13 and Caesar cipher functions.
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
; str_rot13
;
; ROT13 cipher on ASCII characters.
;
; Signature:
;   int64_t str_rot13(const StrSlice *src, uint8_t *dst,
;                     uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_rot13
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; Forward to str_caesar(src, 13, dst, cap, out_len)
    mov     r8, rcx             ; out_len
    mov     rcx, rdx            ; cap
    mov     rdx, rsi            ; dst
    mov     rsi, 13             ; shift = 13
    jmp     str_caesar
STR_ENDFUNC str_rot13

; -----------------------------------------------------------------------------
; str_caesar
;
; General Caesar cipher with arbitrary shift (0-25). Only shifts ASCII letters.
;
; Signature:
;   int64_t str_caesar(const StrSlice *src, int8_t shift, uint8_t *dst,
;                      uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — shift (int8_t)
;   RDX  — dst (uint8_t*)
;   RCX  — cap (uint64_t)
;   R8   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_caesar
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rdx                    ; dst
    mov     r14, rcx                    ; cap
    mov     r15, r8                     ; out_len

    ; check capacity
    cmp     r12, r14
    ja      .too_small

    ; Normalize shift: (shift % 26 + 26) % 26
    movsx   rax, sil            ; sign-extend shift
    mov     rcx, 26
    cdq                         ; RAX -> RDX:RAX
    idiv    rcx                 ; RDX = remainder (shift % 26)
    add     rdx, 26
    mov     rax, rdx
    xor     edx, edx
    div     rcx                 ; RDX = normalized shift (0..25)
    mov     rsi, rdx            ; rsi = shift

    xor     rcx, rcx            ; offset = 0

.loop:
    cmp     rcx, r12
    je      .done

    movzx   eax, byte [rbx + rcx]
    
    ; check if 'A'..'Z'
    cmp     al, 'A'
    jb      .check_lower
    cmp     al, 'Z'
    ja      .check_lower

    ; shift uppercase
    sub     al, 'A'
    add     rax, rsi
    ; modulo 26
    xor     edx, edx
    push    rcx
    mov     rcx, 26
    div     rcx
    pop     rcx
    mov     al, dl
    add     al, 'A'
    jmp     .write_char

.check_lower:
    ; check if 'a'..'z'
    cmp     al, 'a'
    jb      .write_char
    cmp     al, 'z'
    ja      .write_char

    ; shift lowercase
    sub     al, 'a'
    add     rax, rsi
    xor     edx, edx
    push    rcx
    mov     rcx, 26
    div     rcx
    pop     rcx
    mov     al, dl
    add     al, 'a'

.write_char:
    mov     [r13 + rcx], al
    inc     rcx
    jmp     .loop

.done:
    mov     [r15], r12          ; out_len = src.len
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_caesar
