; ============================================================================
; bench_throughput — Max Commits/Sec (no present wait)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"
%include "inc/client_api.inc"

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_SHELL
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
    call ut_time_now_ns
    mov r15, rax
.loop:
    cmp r14d, 1000
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
    inc r14d
    jmp .loop
.report:
    call ut_time_now_ns
    sub rax, r15
    mov rsi, rax
    mov rdi, bench_fmt
    call ut_log_printf
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call ut_task_exit
.fail:
    mov rax, 1
    call ut_task_exit

section .rodata
bench_fmt: db "throughput: 1000 commits in %d ns", 10, 0

section .data
global bench_throughput_version
bench_throughput_version: dq 0x010000
