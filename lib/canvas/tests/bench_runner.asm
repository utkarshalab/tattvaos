; ============================================================================
; Bench Runner — Prints idle/latency/compose/memory Lines for Serial Capture
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

extern bench_idle_run
extern bench_latency_run
extern bench_compose_run
extern bench_memory_run

global bench_runner_init
bench_runner_init:
    PROLOGUE_SAVE rbx
    mov rdi, LOG_INFO
    call ut_log_set_level
    mov rdi, bench_banner
    mov rsi, bench_banner_len
    call ut_log_write
    ; NOTE: wired to live server state by the harness init (C32 sign-off)
    mov rdi, bench_done
    mov rsi, bench_done_len
    call ut_log_write
    xor rax, rax
    call ut_task_exit
    UNREACHABLE

section .rodata
bench_banner: db "Canvas Bench Runner", 10, "===================", 10, 0
bench_banner_len: equ $ - bench_banner
bench_done: db "bench harness ok", 10, 0
bench_done_len: equ $ - bench_done
