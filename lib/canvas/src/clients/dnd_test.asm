; ============================================================================
; dnd_test / ime_test / a11y_test — Protocol Exercisers
; Each defines client_main; built as separate images via static pattern rules
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

; NOTE: only one client_main per image; the three tests below are assembled
; from this shared template with TEST_ID selecting behavior.

global client_main
client_main:
    PROLOGUE_SAVE rbx
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_DATA
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
banner: db "dnd/ime/a11y protocol test", 10, 0
banner_len: equ $ - banner

section .data
global proto_test_version
proto_test_version: dq 0x010000
