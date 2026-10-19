; =============================================================================
; File     : src/core/strings.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: String primitives — len, copy, compare, find.
; =============================================================================

%ifndef VCS_CORE_STRINGS_ASM
%define VCS_CORE_STRINGS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; str_len — Length of null-terminated string
; Input:  rdi = string
; Output: rax = length (excluding null)
; -----------------------------------------------------------------------------
global str_len
str_len:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    xor     rax, rax
.len_loop:
    cmp     byte [rbx + rax], 0
    je      .done
    inc     rax
    jmp .len_loop
.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; str_copy — Copy null-terminated string (including null)
; Input:  rdi = dst, rsi = src
; Output: rax = dst
; -----------------------------------------------------------------------------
global str_copy
str_copy:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
.copy_loop:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .done
    inc     rdi
    inc     rsi
    jmp .copy_loop
.done:
    mov     rax, rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; str_compare — Compare two null-terminated strings
; Input:  rdi = a, rsi = b
; Output: rax = 0 if equal, nonzero if different
; -----------------------------------------------------------------------------
global str_compare
str_compare:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
.cmp_loop:
    mov     al, [rdi]
    mov     dl, [rsi]
    cmp     al, dl
    jne     .different
    test    al, al
    jz      .equal
    inc     rdi
    inc     rsi
    jmp .cmp_loop
.equal:
    xor     rax, rax
    jmp .done
.different:
    mov     rax, 1
.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; str_find_char — Find first occurrence of byte in string
; Input:  rdi = string, sil = byte
; Output: rax = pointer to byte or 0 if not found
; -----------------------------------------------------------------------------
global str_find_char
str_find_char:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
.find_loop:
    mov     al, [rbx]
    test    al, al
    jz      .not_found
    cmp     al, sil
    je      .found
    inc     rbx
    jmp .find_loop
.found:
    mov     rax, rbx
    jmp .done
.not_found:
    xor     rax, rax
.done:
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_CORE_STRINGS_ASM