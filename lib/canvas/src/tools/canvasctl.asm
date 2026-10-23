; ============================================================================
; canvasctl — Runtime Control (inspect/control server at runtime)
; Usage: canvasctl <cmd> [args]  (commands via serial argv)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/externs.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi                    ; server capability
    mov r12, rsi                   ; command string
    mov rdi, ctl_banner
    mov rsi, ctl_banner_len
    call ut_log_write
    test rbx, rbx
    jz .ctl_bad
    test r12, r12
    jz .ctl_bad
    cmp byte [r12], 'c'
    je .ctl_clients
    cmp byte [r12], 's'
    je .ctl_surfaces
    cmp byte [r12], 'l'
    je .ctl_layers
    mov rax, -(EINVAL)
    jmp .ctl_exit
.ctl_clients:
    mov rdi, rbx
    sub rsp, 4096
    mov rsi, rsp
    call debug_client_list
    jmp .ctl_print
.ctl_surfaces:
    mov rdi, rbx
    sub rsp, 4096
    mov rsi, rsp
    mov rdx, 4096
    call debug_scene_dump
    jmp .ctl_print
.ctl_layers:
    mov rdi, rbx
    sub rsp, 4096
    mov rsi, rsp
    mov rdx, 4096
    call debug_scene_dump
.ctl_print:
    test rax, rax
    js .ctl_free
    mov rsi, rax
    mov rdi, rsp
    call ut_log_write
.ctl_free:
    add rsp, 4096
    jmp .ctl_exit
.ctl_bad:
    mov rax, -(EINVAL)
.ctl_exit:
    call ut_task_exit

; ---------------------------------------------------------------------------
; canvasctl subcommands (also callable in-process)
; ---------------------------------------------------------------------------
global canvasctl_clients
canvasctl_clients:
    jmp debug_client_list

global canvasctl_surfaces
canvasctl_surfaces:
    jmp debug_scene_dump

global canvasctl_layers
canvasctl_layers:
    jmp debug_scene_dump

global canvasctl_record_start
canvasctl_record_start:
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

global canvasctl_record_stop
canvasctl_record_stop:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    call record_stop
    EPILOGUE_RESTORE rbx, r12
    ret

global canvasctl_trace_mask
canvasctl_trace_mask:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov esi, r12d
    call trace_set_mask
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

ctl_banner: db "canvasctl - Canvas Display Server Control", 10, 0
ctl_banner_len: equ $ - ctl_banner

global canvasctl_version
canvasctl_version: dq 0x010000
