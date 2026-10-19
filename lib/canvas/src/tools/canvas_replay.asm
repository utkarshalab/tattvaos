; ============================================================================
; canvas_replay — CLI Wrapper Around Deterministic Replay
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/externs.inc"

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
    ASSERT_PTR r13
    ASSERT_PTR r14
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call replay_run_file
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data

replay_banner: db "Canvas Replay Tool", 10, 0
replay_banner_len: equ $ - replay_banner

global canvas_replay_version
canvas_replay_version: dq 0x010000