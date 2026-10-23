; ============================================================================
; demo_subsurfaces — Parent + Subsurface Tree Demo
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
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT | CLIENT_CAP_SHELL
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    ; parent
    mov rdi, rbx
    call canvas_surface_create
    mov r12d, eax
    mov rdi, rbx
    mov esi, 500
    mov rdx, 400
    mov rcx, 0x41524742
    call canvas_buffer_create
    mov r13d, eax
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    xor ecx, ecx
    xor r8d, r8d
    call canvas_surface_attach
    ; child subsurface (video-like overlay at 50,50 200x150)
    mov rdi, rbx
    call canvas_surface_create
    mov r14d, eax
    mov rdi, rbx
    mov esi, 200
    mov rdx, 150
    mov rcx, 0x41524742
    call canvas_buffer_create
    mov r13d, eax
    mov rdi, rbx
    mov esi, r14d
    mov edx, r13d
    mov ecx, 50
    mov r8d, 50
    call canvas_surface_attach
    ; commit parent (synchronized children commit together)
    mov rdi, rbx
    mov esi, r12d
    mov edx, CLIENT_COMMIT_TRANSACTION
    call canvas_surface_commit
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call ut_task_exit
.fail:
    mov rax, 1
    call ut_task_exit

section .data
global demo_subsurfaces_version
demo_subsurfaces_version: dq 0x010000
