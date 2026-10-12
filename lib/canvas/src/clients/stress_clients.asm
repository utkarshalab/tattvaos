; ============================================================================
; stress_clients — Churn: Connect/Commit/Fault Loop (soak helper)
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
    xor r13d, r13d
.cycle:
    cmp r13d, 50
    jae .done
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_SHELL
    call canvas_connect
    test rax, rax
    jz .next
    mov rbx, rax
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, 320
    mov rdx, 240
    mov rcx, 0x41524742
    call canvas_buffer_create
    mov rdi, rbx
    mov esi, r12d
    mov edx, eax
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    mov rdi, rbx
    mov esi, r12d
    xor edx, edx
    call canvas_surface_commit
    mov rdi, rbx
    call canvas_disconnect
.next:
    inc r13d
    jmp .cycle
.done:
    mov rdi, stress_done
    mov rsi, stress_done_len
    call tv_log_write
    xor rax, rax
    call tv_task_exit

section .rodata
stress_done: db "stress_clients: 50 connect/commit cycles done", 10, 0
stress_done_len: equ $ - stress_done

section .data
global stress_clients_version
stress_clients_version: dq 0x010000
