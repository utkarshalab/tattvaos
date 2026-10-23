; =============================================================================
; File     : apps/ish/src/util/strutil.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: String comparison, trim, case folding utilities.
; =============================================================================

%ifndef ISH_STRUTIL_ASM
%define ISH_STRUTIL_ASM

%include "lib/str/str.asm"

bits 64

section .text

; -----------------------------------------------------------------------------
; str_to_int — Convert string to integer
; Input:  rdi = string pointer
; Output: rax = integer value (0 on error)
; -----------------------------------------------------------------------------
global str_to_int
str_to_int:
    PROLOGUE_SAVE rbx, rcx

    xor     rax, rax                      ; result = 0
    xor     rbx, rbx                      ; sign = 1 (positive)

    mov     al, [rdi]
    cmp     al, '-'
    je      .str_to_int_negative
    cmp     al, '+'
    je      .str_to_int_skip_sign

.str_to_int_loop:
    mov     al, [rdi]
    inc     rdi
    sub     al, '0'
    cmp     al, 9
    ja      .str_to_int_done
    imul    rax, 10
    add     rax, rax                      ; rax *= 10
    jmp .str_to_int_loop

.str_to_int_negative:
    mov     rbx, -1
    inc     rdi
    jmp .str_to_int_loop

.str_to_int_skip_sign:
    inc     rdi
    jmp .str_to_int_loop

.str_to_int_done:
    imul    rax, rbx                      ; apply sign
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; str_trim — Trim whitespace from both ends of string
; Input:  rdi = string (modified in place)
; Output: rax = trimmed string pointer
; -----------------------------------------------------------------------------
global str_trim
str_trim:
    PROLOGUE_SAVE rbx, rcx

    mov     rbx, rdi                      ; save start

    ; Trim leading whitespace
.str_trim_lead:
    mov     al, [rdi]
    cmp     al, ' '
    je      .str_trim_lead_next
    cmp     al, 0x09
    je      .str_trim_lead_next
    jmp .str_trim_trail

.str_trim_lead_next:
    inc     rdi
    jmp .str_trim_lead

.str_trim_trail:
    ; Find end of string
    mov     rcx, rdi
.str_trim_find_end:
    mov     al, [rcx]
    test    al, al
    jz      .str_trim_end_found
    inc     rcx
    jmp .str_trim_find_end

.str_trim_end_found:
    dec     rcx                           ; back to last char

.str_trim_trail_loop:
    cmp     rcx, rdi
    jl      .str_trim_done
    mov     al, [rcx]
    cmp     al, ' '
    je      .str_trim_trail_null
    cmp     al, 0x09
    je      .str_trim_trail_null
    jmp .str_trim_done

.str_trim_trail_null:
    mov     byte [rcx], 0
    dec     rcx
    jmp .str_trim_trail_loop

.str_trim_done:
    mov     rax, rdi
    EPILOGUE_RESTORE rbx, rcx
    ret

%endif ; ISH_STRUTIL_ASM