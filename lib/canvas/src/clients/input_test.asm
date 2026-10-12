; ============================================================================
; input_test — Keyboard/Pointer Event Logger (serial output)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx, r12
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_SHELL
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, r12d
    call canvas_toplevel_create
    mov rdi, input_banner
    mov rsi, input_banner_len
    call tv_log_write
    xor r12d, r12d
.loop:
    cmp r12d, 1000
    jae .done
    sub rsp, ClientEvent_size
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test rax, rax
    jz .no_event
    mov rdi, rsp
    call canvas_event_type
    mov rsi, rax
    mov rdi, event_fmt
    call tv_log_printf
.no_event:
    add rsp, ClientEvent_size
    inc r12d
    jmp .loop
.done:
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call tv_task_exit
.fail:
    mov rax, 1
    call tv_task_exit

section .rodata
input_banner: db "input_test: logging 1000 polls", 10, 0
input_banner_len: equ $ - input_banner
event_fmt: db "event type=%d", 10, 0

section .data
global input_test_version
input_test_version: dq 0x010000
