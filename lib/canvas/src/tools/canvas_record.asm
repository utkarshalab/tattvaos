; ============================================================================
; canvas_record / canvas_replay — CLI Wrappers Around Record/Replay
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/externs.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi                    ; server capability
    mov r12, rsi                   ; mode: 0 record, 1 replay
    mov r13, rdx                   ; path
    mov rdi, rec_banner
    mov rsi, rec_banner_len
    call ut_log_write
    test rbx, rbx
    jz .record_bad
    test r13, r13
    jz .record_bad
    mov rdi, r13
    call canvas_tool_strlen
    test r12, r12
    jnz .run_replay
    mov rdi, rbx
    mov rsi, r13
    mov rdx, rax
    call record_start
    jmp .record_exit
.run_replay:
    mov rdi, rbx
    mov rsi, r13
    mov rdx, rax
    xor rcx, rcx
    xor r8d, r8d
    call replay_run_file
    jmp .record_exit
.record_bad:
    mov rax, -(EINVAL)
.record_exit:
    call ut_task_exit

canvas_tool_strlen:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    xor eax, eax
.strlen_loop:
    cmp byte [rbx + rax], 0
    je .strlen_done
    inc rax
    jmp .strlen_loop
.strlen_done:
    EPILOGUE_RESTORE rbx
    ret

global canvas_record_run
canvas_record_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    call record_start
    EPILOGUE_RESTORE rbx, r12
    ret

global canvas_replay_run
canvas_replay_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    call replay_run_file
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

rec_banner: db "Canvas Record/Replay Tool", 10, 0
rec_banner_len: equ $ - rec_banner

global canvas_record_version
canvas_record_version: dq 0x010000
global canvas_replay_version
canvas_replay_version: dq 0x010000
