; =============================================================================
; File     : apps/ish/src/util/argv.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: argc/argv helper utilities.
; =============================================================================

%ifndef ISH_ARGV_ASM
%define ISH_ARGV_ASM

%include "inc/ish.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; argv_get — Get argv[n]
; Input:  rdi = argv (char **), rsi = index n
; Output: rax = argv[n] string or 0 if out of bounds
; -----------------------------------------------------------------------------
global argv_get
argv_get:
    PROLOGUE_SAVE rbx

    mov     rbx, rdi                      ; rbx = argv base
    mov     rdx, rsi                      ; rdx = index
    cmp     rdx, 0
    jl      .argv_out_of_bounds
    mov     rax, [rbx + rdx*8]            ; rax = argv[n]
    jmp .argv_done

.argv_out_of_bounds:
    xor     rax, rax

.argv_done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; argv_count_nonempty — Count non-empty arguments
; Input:  rdi = argv (char **), rsi = argc
; Output: rax = count of non-empty strings
; -----------------------------------------------------------------------------
global argv_count_nonempty
argv_count_nonempty:
    PROLOGUE_SAVE rbx, rcx

    mov     rbx, rdi
    mov     rcx, rsi
    xor     rax, rax                      ; count = 0

.argv_loop:
    test    rcx, rcx
    jz      .argv_done

    mov     rdx, [rbx]
    test    rdx, rdx
    jz      .argv_next
    mov     rdi, rdx
    call    str_len
    test    rax, rax
    jz      .argv_next
    inc     rax                           ; count++

.argv_next:
    add     rbx, 8
    dec     rcx
    jmp .argv_loop

.argv_done:
    EPILOGUE_RESTORE rbx, rcx
    ret

%endif ; ISH_ARGV_ASM