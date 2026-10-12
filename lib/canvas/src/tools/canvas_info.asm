; ============================================================================
; canvas_info / canvas_inspect — Server Info + Live Scene Inspector
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, info_banner
    mov rsi, info_banner_len
    call tv_log_write
    ; TODO: query canvasd via cw_debug (version, outputs, clients, metrics)
    xor rax, rax
    call tv_task_exit

global canvas_info_dump
canvas_info_dump:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; dump version
    mov rdi, r12
    mov rsi, ver_fmt
    mov rdx, 0
    mov rcx, 1
    mov r8, 0
    call tv_log_printf
    ; dump outputs
    mov rdi, rbx
    call debug_scene_dump
    ret

section .rodata
info_banner: db "canvas-info 0.1.0", 10, 0
info_banner_len: equ $ - info_banner
ver_fmt: db "canvasd %d.%d.%d", 10, 0

section .data
global canvas_info_version
canvas_info_version: dq 0x010000
