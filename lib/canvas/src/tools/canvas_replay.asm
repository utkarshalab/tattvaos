; ============================================================================
; canvas_replay — CLI Wrapper Around Deterministic Replay
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, replay_banner
    mov rsi, replay_banner_len
    call tv_log_write
    xor rax, rax
    call tv_task_exit

global canvas_replay_run
canvas_replay_run:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    xor r8d, r8d
    call replay_run_file
    ret

section .rodata
replay_banner: db "canvas-replay 0.1.0", 10, 0
replay_banner_len: equ $ - replay_banner

section .data
global canvas_replay_version
canvas_replay_version: dq 0x010000
