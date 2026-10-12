; ============================================================================
; demo_windows — Reference Client: Multiple Windows via Client Library
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
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT | CLIENT_CAP_SHELL
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    ; window 1
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, 400
    mov rdx, 300
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
    xor edx, edx
    xor ecx, ecx
    mov r8d, 400
    mov r9d, 300
    call canvas_surface_damage
    mov rdi, rbx
    mov esi, r12d
    xor edx, edx
    call canvas_surface_commit
    ; window 2
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, r12d
    call canvas_toplevel_create
    ; event loop: run 600 frames then exit
    xor r13d, r13d
.loop:
    cmp r13d, 600
    jae .done
    sub rsp, ClientEvent_size
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    add rsp, ClientEvent_size
    inc r13d
    jmp .loop
.done:
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call tv_task_exit
.fail:
    mov rax, 1
    call tv_task_exit

section .data
global demo_windows_version
demo_windows_version: dq 0x010000
