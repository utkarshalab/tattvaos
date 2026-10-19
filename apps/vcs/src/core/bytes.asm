; =============================================================================
; File     : src/core/bytes.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Byte operations — copy, compare, search, fill.
; =============================================================================

%ifndef VCS_CORE_BYTES_ASM
%define VCS_CORE_BYTES_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; bytes_copy — Copy n bytes from src to dst (non-overlapping)
; Input:  rdi = dst, rsi = src, rdx = n
; Output: rax = dst
; -----------------------------------------------------------------------------
global bytes_copy
bytes_copy:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rdx
    test    rcx, rcx
    jz      .done
.copy_loop:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .copy_loop
    mov     rax, rbx
    EPILOGUE_RESTORE rbx, rcx
    ret

.done:
    mov     rax, rbx
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; bytes_compare — Compare n bytes
; Input:  rdi = a, rsi = b, rdx = n
; Output: rax = 0 if equal, nonzero if different
; -----------------------------------------------------------------------------
global bytes_compare
bytes_compare:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rdx
    test    rcx, rcx
    jz      .equal
.cmp_loop:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .different
    inc     rdi
    inc     rsi
    dec     rcx
    jnz     .cmp_loop
.equal:
    xor     rax, rax
    jmp .done
.different:
    mov     rax, 1
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; bytes_fill — Fill n bytes with value
; Input:  rdi = dst, sil = byte value, rdx = n
; Output: rax = dst
; -----------------------------------------------------------------------------
global bytes_fill
bytes_fill:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rdx
    test    rcx, rcx
    jz      .done
.fill_loop:
    mov     [rdi], sil
    inc     rdi
    dec     rcx
    jnz     .fill_loop
    mov     rax, rbx
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

%endif ; VCS_CORE_BYTES_ASM