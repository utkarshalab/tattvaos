; ============================================================================
; demo_alpha — Alpha Blending Demo (semi-transparent windows)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"
%include "inc/client_api.inc"

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx, r12, r13
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT | CLIENT_CAP_SHELL
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    ; 50% transparent red buffer
    mov rdi, rbx
    mov esi, 300
    mov rdx, 200
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
    mov r8d, 300
    mov r9d, 200
    call canvas_surface_damage
    mov rdi, rbx
    mov esi, r12d
    xor edx, edx
    call canvas_surface_commit
    ; present + wait one frame
    mov rdi, rbx
    mov esi, r12d
    mov rdx, 1000000000
    call canvas_present_wait
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call ut_task_exit
.fail:
    mov rax, 1
    call ut_task_exit

section .data
global demo_alpha_version
demo_alpha_version: dq 0x010000
