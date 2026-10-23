; ============================================================================
; canvas_inspect — Live Scene Inspector (dumps scene graph via cw_debug)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/externs.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rbx, rdi                    ; native launch passes server capability
    mov rdi, inspect_banner
    mov rsi, inspect_banner_len
    call ut_log_write
    test rbx, rbx
    jz .inspect_exit
    sub rsp, 4096
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 4096
    call debug_scene_dump
    test rax, rax
    js .inspect_free
    mov rsi, rax
    mov rdi, rsp
    call ut_log_write
.inspect_free:
    add rsp, 4096
.inspect_exit:
    call ut_task_exit

global canvas_inspect_scene
canvas_inspect_scene:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    call debug_scene_dump
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

inspect_banner: db "Canvas Display Server - Scene Inspector", 10, 0
inspect_banner_len: equ $ - inspect_banner

global canvas_inspect_version
canvas_inspect_version: dq 0x010000
