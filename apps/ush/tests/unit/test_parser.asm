; =============================================================================
; File     : apps/ush/tests/unit/test_parser.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Unit tests for the shell parser.
; =============================================================================

%ifndef USH_TEST_PARSER_ASM
%define USH_TEST_PARSER_ASM

%include "inc/ush.inc"
%include "lib/str/str.asm"

bits 64

section .text

; -----------------------------------------------------------------------------
; test_parser_run — Run all parser unit tests
; Output: rax = 0 if all passed, nonzero if failed
; -----------------------------------------------------------------------------
global test_parser_run
test_parser_run:
    PROLOGUE_SAVE rbx

    mov     rdi, msg_test_parser_start
    call    frontend_write_str

    call    test_tokenizer_basic
    test    rax, rax
    jnz     .test_failed

    call    test_tokenizer_quotes
    test    rax, rax
    jnz     .test_failed

    call    test_tokenizer_empty
    test    rax, rax
    jnz     .test_failed

    mov     rdi, msg_test_parser_passed
    call    frontend_write_str
    xor     rax, rax
    jmp .test_done

.test_failed:
    mov     rdi, msg_test_parser_failed
    call    frontend_write_str
    mov     eax, 1

.test_done:
    EPILOGUE_RESTORE rbx
    ret

section .bss
align 16
test_argv:    resq USH_MAX_ARGS * 8

section .text

; -----------------------------------------------------------------------------
; test_tokenizer_basic — Test basic tokenization
; -----------------------------------------------------------------------------
test_tokenizer_basic:
    PROLOGUE_SAVE rbx

    mov     rdi, .test_input
    call    parser_tokenize               ; fills token_argv
    cmp     eax, 3
    jne     .test_fail

    ; Check first token
    mov     rdi, [token_argv]
    mov     rsi, .expect_echo
    call    str_cmp
    test    rax, rax
    jnz     .test_fail

    ; Check second token
    mov     rdi, [token_argv + 8]
    mov     rsi, .expect_hello
    call    str_cmp
    test    rax, rax
    jnz     .test_fail

    ; Check third token
    mov     rdi, [token_argv + 16]
    mov     rsi, .expect_world
    call    str_cmp
    test    rax, rax
    jnz     .test_fail

    xor     rax, rax
    jmp .test_done

.test_fail:
    mov     rax, 1

.test_done:
    EPILOGUE_RESTORE rbx
    ret

section .data
align 16
.test_input:    db "echo hello world", 0
.expect_echo:   db "echo", 0
.expect_hello:  db "hello", 0
.expect_world:  db "world", 0

section .text

; -----------------------------------------------------------------------------
; test_tokenizer_quotes — Test quoted tokenization
; -----------------------------------------------------------------------------
test_tokenizer_quotes:
    PROLOGUE_SAVE rbx

    mov     rdi, .test_input_quoted
    call    parser_tokenize
    cmp     eax, 2
    jne     .test_fail_quotes

    mov     rdi, [token_argv]
    mov     rsi, .expect_quoted_hello
    call    str_cmp
    test    rax, rax
    jnz     .test_fail_quotes

    xor     rax, rax
    jmp .test_done_quotes

.test_fail_quotes:
    mov     rax, 1

.test_done_quotes:
    EPILOGUE_RESTORE rbx
    ret

section .data
align 16
.test_input_quoted: db 'echo "hello world"', 0
.expect_quoted_hello: db "hello world", 0

section .text

; -----------------------------------------------------------------------------
; test_tokenizer_empty — Test empty input
; -----------------------------------------------------------------------------
test_tokenizer_empty:
    PROLOGUE_SAVE rbx

    mov     rdi, .test_input_empty
    call    parser_tokenize
    cmp     eax, 0
    jne     .test_fail_empty

    xor     rax, rax
    jmp .test_done_empty

.test_fail_empty:
    mov     rax, 1

.test_done_empty:
    EPILOGUE_RESTORE rbx
    ret

section .data
align 16
.test_input_empty: db "", 0

section .rodata
align 16
msg_test_parser_start: db "Running parser tests...", 0x0A, 0
msg_test_parser_passed: db "Parser tests: PASSED", 0x0A, 0
msg_test_parser_failed: db "Parser tests: FAILED", 0x0A, 0

%endif ; USH_TEST_PARSER_ASM