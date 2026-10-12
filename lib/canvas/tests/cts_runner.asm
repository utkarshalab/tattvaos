; ============================================================================
; CTS Runner — Executes All Conformance Suites Against a Live Server
; Built as Tattva image, reports results over serial
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

extern test_cts_core_suite
extern test_cts_surface_suite
extern test_cts_sync_suite
extern test_cts_present_suite
extern test_cts_output_suite
extern test_cts_input_suite
extern test_cts_shell_suite
extern test_cts_data_suite
extern test_cts_text_suite
extern test_cts_security_suite
extern test_cts_governance_suite

global cts_runner_init
cts_runner_init:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    mov rdi, LOG_TRACE
    call tv_log_set_level

    mov rdi, runner_banner
    mov rsi, runner_banner_len
    call tv_log_write

    xor rbx, rbx

    call test_cts_core_suite
    add rbx, rax

    call test_cts_surface_suite
    add rbx, rax

    call test_cts_sync_suite
    add rbx, rax

    call test_cts_present_suite
    add rbx, rax

    call test_cts_output_suite
    add rbx, rax

    call test_cts_input_suite
    add rbx, rax

    call test_cts_shell_suite
    add rbx, rax

    call test_cts_data_suite
    add rbx, rax

    call test_cts_text_suite
    add rbx, rax

    call test_cts_security_suite
    add rbx, rax

    call test_cts_governance_suite
    add rbx, rax

    mov rdi, runner_summary
    mov rsi, rbx
    call tv_log_printf

    mov rax, rbx
    call tv_task_exit

    UNREACHABLE

section .rodata

runner_banner:        db "Canvas CTS Runner", 10, "===================", 10, 0
runner_banner_len:    equ $ - runner_banner
runner_summary:       db "=== CTS COMPLETE: %d suite(s) failed ===", 10, 0
