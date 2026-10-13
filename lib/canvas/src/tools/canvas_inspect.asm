; ============================================================================
; canvas_inspect — Live Scene Inspector (dumps scene graph via cw_debug)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, inspect_banner
    mov rsi, inspect_banner_len
    call tv_log_write
    ; TODO: connect cw_debug, dump scene + clients + metrics
    xor rax, rax
    call tv_task_exit

global canvas_inspect_scene
canvas_inspect_scene:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    mov rdx, 4096
    call debug_scene_dump
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
inspect_banner: db "canvas-inspect 0.1.0", 10, 0
inspect_banner_len: equ $ - inspect_banner

section .data
global canvas_inspect_version
canvas_inspect_version: dq 0x010000
