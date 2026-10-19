; ============================================================================
; canvas_info / canvas_inspect — Server Info + Live Scene Inspector
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
    mov rbx, rdi
    mov rdi, info_banner
    mov rsi, info_banner_len
    call tv_log_write
    test rbx, rbx
    jz .info_exit
    sub rsp, 4096
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 4096
    call debug_scene_dump
    test rax, rax
    js .info_free
    mov rsi, rax
    mov rdi, rsp
    call tv_log_write
.info_free:
    add rsp, 4096
.info_exit:
    call tv_task_exit

section .data

info_banner: db "Canvas Display Server - Info Tool", 10, 0
info_banner_len: equ $ - info_banner

global canvas_info_version
canvas_info_version: dq 0x010000
