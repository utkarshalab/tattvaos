; =============================================================================
; File     : apps/ish/src/parser/tokenizer.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Tokenize input line into argc/argv.
; =============================================================================

%ifndef ISH_TOKENIZER_ASM
%define ISH_TOKENIZER_ASM

%include "inc/ish.inc"
%include "lib/str/str.asm"

bits 64

section .bss
align 16
token_argc:     resd 1
token_argv:     resq ISH_MAX_ARGS * 8

section .text

; -----------------------------------------------------------------------------
; parser_tokenize — Split input line into tokens
; Input:  rdi = input line string
; Output: rax = argc (or -1 on error), sets token_argc/token_argv
; -----------------------------------------------------------------------------
global parser_tokenize
parser_tokenize:
    PROLOGUE_SAVE rbx, rcx, rdx, rsi

    mov     rbx, rdi                      ; rbx = input string
    mov     rcx, 0                        ; rcx = argc counter
    mov     rdx, token_argv               ; rdx = argv array

.skip_spaces:
    mov     al, [rbx]
    test    al, al
    jz      .tokenize_done
    cmp     al, ' '
    je      .skip_one_space
    cmp     al, 0x09                      ; tab
    je      .skip_one_space
    jmp .token_start

.skip_one_space:
    inc     rbx
    jmp .skip_spaces

.token_start:
    cmp     rcx, ISH_MAX_ARGS
    jge     .too_many_args

    ; Store pointer to token start
    mov     [rdx + rcx*8], rbx
    inc     rcx

.find_token_end:
    mov     al, [rbx]
    test    al, al
    jz      .tokenize_done
    cmp     al, ' '
    je      .null_terminate_token
    cmp     al, 0x09
    je      .null_terminate_token
    cmp     al, '"'
    je      .quoted_token
    inc     rbx
    jmp .find_token_end

.quoted_token:
    inc     rbx                           ; skip opening quote
.find_quote_end:
    mov     al, [rbx]
    test    al, al
    jz      .tokenize_done
    cmp     al, '"'
    je      .quote_closed
    inc     rbx
    jmp .find_quote_end

.quote_closed:
    inc     rbx                           ; skip closing quote
    mov     al, [rbx]
    cmp     al, ' '
    je      .null_terminate_after_quote
    cmp     al, 0x09
    je      .null_terminate_after_quote
    test    al, al
    jz      .tokenize_done
    jmp .find_token_end

.null_terminate_after_quote:
    mov     byte [rbx], 0
    inc     rbx
    jmp .skip_spaces

.null_terminate_token:
    mov     byte [rbx], 0
    inc     rbx
    jmp .skip_spaces

.tokenize_done:
    mov     eax, ecx                      ; return argc
    mov     [token_argc], ecx
    jmp .tokenize_done_ret

.too_many_args:
    mov     eax, -1

.tokenize_done_ret:
    EPILOGUE_RESTORE rbx, rcx, rdx, rsi
    ret

%endif ; ISH_TOKENIZER_ASM