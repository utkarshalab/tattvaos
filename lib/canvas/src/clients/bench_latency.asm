; ============================================================================
; bench_latency / bench_throughput / stress_clients
; Latency: commit->present timing. Throughput: max commits/sec. Stress: churn.
; Built as separate images; behavior selected per file.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"
%include "inc/client_api.inc"

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT | CLIENT_CAP_SHELL
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, 800
    mov rdx, 600
    mov rcx, 0x41524742
    call canvas_buffer_create
    mov r13d, eax
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    xor r14d, r14d
    call tv_time_now_ns
    mov r15, rax
.loop:
    cmp r14d, 300
    jae .report
    mov rdi, rbx
    mov esi, r12d
    xor edx, edx
    xor ecx, ecx
    mov r8d, 800
    mov r9d, 600
    call canvas_surface_damage
    mov rdi, rbx
    mov esi, r12d
    xor edx, edx
    call canvas_surface_commit
    mov rdi, rbx
    mov esi, r12d
    mov rdx, 1000000000
    call canvas_present_wait
    inc r14d
    jmp .loop
.report:
    call tv_time_now_ns
    sub rax, r15
    ; rax = ns for 300 frames
    mov rsi, rax
    mov rdi, bench_fmt
    call tv_log_printf
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call tv_task_exit
.fail:
    mov rax, 1
    call tv_task_exit

section .rodata
bench_fmt: db "bench: 300 frames in %d ns", 10, 0

section .data
global bench_version
bench_version: dq 0x010000
