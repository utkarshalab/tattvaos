; ============================================================================
; lockscreen — Reference Lock Screen Client (lock layer, input grab)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx, r12, r13
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, 1920
    mov rdx, 1080
    mov rcx, 0x41524742
    call canvas_buffer_create
    mov r13d, eax
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    mov rdi, rbx
    mov esi, r12d
    call canvas_layer_create
    mov rdi, rbx
    mov esi, r12d
    xor edx, edx
    call canvas_surface_commit
    ; wait for unlock event (any key)
.unlock_loop:
    sub rsp, ClientEvent_size
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test rax, rax
    jz .no_event
    mov rdi, rsp
    call canvas_event_type
    cmp rax, 1
    je .unlock
.no_event:
    add rsp, ClientEvent_size
    jmp .unlock_loop
.unlock:
    add rsp, ClientEvent_size
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call tv_task_exit
.fail:
    mov rax, 1
    call tv_task_exit

section .data
global lockscreen_version
lockscreen_version: dq 0x010000
