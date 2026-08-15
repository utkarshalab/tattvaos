; =============================================================================
; Tattva OS — lib/ulog/tests/run_tests.asm
; =============================================================================
; ulog diagnostic test runner, matching lib/time/tests/run_tests.asm's shape.
; Every sub-test returns 0 pass / -1 fail; this stops at the first failure
; so a milestone trail on serial shows exactly how far it got.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_RUN_TESTS_ASM
%define LIB_ULOG_TESTS_RUN_TESTS_ASM

[BITS 64]

%include "lib/ulog/tests/test_ring.asm"
%include "lib/ulog/tests/test_levels.asm"
%include "lib/ulog/tests/test_context.asm"
%include "lib/ulog/tests/test_ratelimit.asm"
%include "lib/ulog/tests/test_panic.asm"
%include "lib/ulog/tests/test_integrity.asm"
%include "lib/ulog/tests/test_sinks.asm"
%include "lib/ulog/tests/test_format.asm"
%include "lib/ulog/tests/test_drain.asm"

section .text

; -----------------------------------------------------------------------------
; ulog_run_unit_tests — Output: RAX = 0 all passed, -1 on the first failure
; -----------------------------------------------------------------------------
global ulog_run_unit_tests
ulog_run_unit_tests:
    mov rsi, .str_start
    call uart_print_str
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc

    call ulog_test_ring
    test rax, rax
    jnz .fail_at_ring

    call ulog_test_levels
    test rax, rax
    jnz .fail_at_levels

    call ulog_test_context
    test rax, rax
    jnz .fail_at_context

    call ulog_test_ratelimit
    test rax, rax
    jnz .fail_at_ratelimit

    call ulog_test_panic
    test rax, rax
    jnz .fail_at_panic

    call ulog_test_integrity
    test rax, rax
    jnz .fail_at_integrity

    call ulog_test_sinks
    test rax, rax
    jnz .fail_at_sinks

    call ulog_test_format
    test rax, rax
    jnz .fail_at_format

    call ulog_test_drain
    test rax, rax
    jnz .fail_at_drain

    mov rsi, .str_all_pass
    call uart_print_str
    xor rax, rax
    ret

.fail_at_ring:
    mov rsi, .str_fail_ring
    jmp .report
.fail_at_levels:
    mov rsi, .str_fail_levels
    jmp .report
.fail_at_context:
    mov rsi, .str_fail_context
    jmp .report
.fail_at_ratelimit:
    mov rsi, .str_fail_ratelimit
    jmp .report
.fail_at_panic:
    mov rsi, .str_fail_panic
    jmp .report
.fail_at_integrity:
    mov rsi, .str_fail_integrity
    jmp .report
.fail_at_sinks:
    mov rsi, .str_fail_sinks
    jmp .report
.fail_at_format:
    mov rsi, .str_fail_format
    jmp .report
.fail_at_drain:
    mov rsi, .str_fail_drain

.report:
    call uart_print_str
    mov rax, -1
    ret

section .rodata
.str_start:           db "TEST:ULOG:STARTING", 0
.str_all_pass:         db "TEST:ULOG:ALL_PASS", 0
.str_fail_ring:          db "TEST:ULOG:FAIL:ring", 0
.str_fail_levels:         db "TEST:ULOG:FAIL:levels", 0
.str_fail_context:        db "TEST:ULOG:FAIL:context", 0
.str_fail_ratelimit:       db "TEST:ULOG:FAIL:ratelimit", 0
.str_fail_panic:           db "TEST:ULOG:FAIL:panic", 0
.str_fail_integrity:        db "TEST:ULOG:FAIL:integrity", 0
.str_fail_sinks:             db "TEST:ULOG:FAIL:sinks", 0
.str_fail_format:             db "TEST:ULOG:FAIL:format", 0
.str_fail_drain:               db "TEST:ULOG:FAIL:drain", 0

%endif ; LIB_ULOG_TESTS_RUN_TESTS_ASM
