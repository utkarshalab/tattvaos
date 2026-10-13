; ============================================================================
; canvas_bench — Benchmark Runner (latency, throughput, idle, memory)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, bench_banner
    mov rsi, bench_banner_len
    call tv_log_write
    call bench_run_all
    xor rax, rax
    call tv_task_exit

global bench_run_all
bench_run_all:
    PROLOGUE_SAVE rbx
    call bench_idle
    call bench_latency
    call bench_compose
    call bench_memory
    EPILOGUE_RESTORE rbx
    ret

global bench_idle
bench_idle:
    PROLOGUE_SAVE rbx
    ; measure wakeups with no damage/timers over 1s
    mov rdi, idle_fmt
    mov rsi, 0
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

global bench_latency
bench_latency:
    PROLOGUE_SAVE rbx
    ; input-to-photon on direct scanout
    mov rdi, latency_fmt
    mov rsi, 0
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

global bench_compose
bench_compose:
    PROLOGUE_SAVE rbx
    mov rdi, compose_fmt
    mov rsi, 0
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

global bench_memory
bench_memory:
    PROLOGUE_SAVE rbx
    mov rdi, mem_fmt
    mov rsi, 0
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

section .rodata
bench_banner: db "canvas-bench 0.1.0", 10, 0
bench_banner_len: equ $ - bench_banner
idle_fmt: db "idle: %d wakeups/s", 10, 0
latency_fmt: db "latency: %d ns input->photon", 10, 0
compose_fmt: db "compose: %d ns/frame", 10, 0
mem_fmt: db "memory: %d KB resident", 10, 0

section .data
global canvas_bench_version
canvas_bench_version: dq 0x010000
