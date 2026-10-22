; ============================================================================
; a11y_test — Accessibility Tree Exerciser
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
    PROLOGUE_SAVE rbx
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, banner
    mov rsi, banner_len
    call tv_log_write
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call tv_task_exit
.fail:
    mov rax, 1
    call tv_task_exit

section .rodata
banner: db "a11y_test: ok", 10, 0
banner_len: equ $ - banner

section .data
global a11y_test_version
a11y_test_version: dq 0x010000
