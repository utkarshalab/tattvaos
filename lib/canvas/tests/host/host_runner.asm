; ============================================================================
; Host Test Runner — host_runner.asm
; Process entry for running one unit suite on a development machine.
; Assemble with -D HOST_SUITE=<suite symbol>; exit status = suite result.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

%ifndef HOST_SUITE
    %error "define HOST_SUITE, e.g. -D HOST_SUITE=test_webp_suite"
%endif

extern HOST_SUITE
extern ut_log_printf
extern ut_task_exit

section .text

global _start
_start:
    and rsp, -16
    call HOST_SUITE
    mov rbx, rax
    lea rdi, [rel result_fmt]
    lea rsi, [rel suite_name]
    mov rdx, rbx
    call ut_log_printf
    mov rdi, rbx
    cmp rdi, 255
    jbe .exit
    mov edi, 255
.exit:
    call ut_task_exit

section .rodata

%defstr HOST_SUITE_NAME HOST_SUITE
suite_name:     db HOST_SUITE_NAME, 0
result_fmt:     db "host: %s returned %d", 10, 0
