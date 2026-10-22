; ============================================================================
; Workspace Management — Virtual Desktops
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"

section .text

; ============================================================================
; workspace_create
;   Create new workspace
; ============================================================================
global workspace_create
workspace_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi  ; shell
    mov r13, rdx  ; output
    mov r14d, ecx ; index
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + WORKSPACE_OUTPUT], r13
    mov dword [rbx + WORKSPACE_IDX], r14d
    mov qword [rbx + WORKSPACE_LAYOUT], 0
    mov qword [rbx + WORKSPACE_TOPLEVELS], 0
    mov qword [rbx + WORKSPACE_NAME], 0

    ; Link into shell's workspace list
    mov rax, [r12 + SHELL_WORKSPACES]
    mov [rbx + WORKSPACE_NEXT], rax
    mov [r12 + SHELL_WORKSPACES], rbx
    inc dword [r12 + SHELL_WORKSPACE_COUNT]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; workspace_destroy
;   Destroy workspace
; ============================================================================
global workspace_destroy
workspace_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Move all toplevels to another workspace
    ; ...

    ; Unlink from shell
    mov r12, [rbx + WORKSPACE_SHELL]
    call .unlink_from_shell

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unlink_from_shell:
    mov rax, [r12 + SHELL_WORKSPACES]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + WORKSPACE_NEXT]
    mov [r12 + SHELL_WORKSPACES], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + WORKSPACE_NEXT]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + WORKSPACE_NEXT]
    mov [r12 + WORKSPACE_NEXT], rax
    dec dword [r12 + SHELL_WORKSPACE_COUNT]

.done:
    ret

; ============================================================================
; workspace_set_active
;   Set active workspace on output
; ============================================================================
global workspace_set_active
workspace_set_active:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; shell
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [r12 + SHELL_ACTIVE_WS], rbx
    mov eax, [rbx + WORKSPACE_IDX]
    mov dword [r12 + SHELL_ACTIVE_WS_IDX], eax

    ; Hide all toplevels on other workspaces, show this one
    call .update_visibility

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.update_visibility:
    ; Iterate toplevels and show/hide based on workspace
    ret

; ============================================================================
; workspace_get_active
;   Get active workspace for shell
; ============================================================================
global workspace_get_active
workspace_get_active:
    PROLOGUE
    mov rax, [rdi + SHELL_ACTIVE_WS]
    leave
    ret

; ============================================================================
; workspace_add_toplevel
;   Add toplevel to workspace
; ============================================================================
global workspace_add_toplevel
workspace_add_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Link into workspace's toplevel list
    mov rax, [rbx + WORKSPACE_TOPLEVELS]
    mov [r12 + TOPLEVEL_NEXT_WS], rax
    mov [rbx + WORKSPACE_TOPLEVELS], r12
    mov [r12 + TOPLEVEL_WORKSPACE], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; workspace_remove_toplevel
;   Remove toplevel from workspace
; ============================================================================
global workspace_remove_toplevel
workspace_remove_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Unlink from workspace's toplevel list
    mov rax, [rbx + WORKSPACE_TOPLEVELS]
    test rax, rax
    jz .done

    cmp rax, r12
    jne .find_prev
    mov rax, [r12 + TOPLEVEL_NEXT_WS]
    mov [rbx + WORKSPACE_TOPLEVELS], rax
    jmp .done

.find_prev:
    mov rax, [rbx + WORKSPACE_TOPLEVELS]
.prev_loop:
    mov rdx, [rax + TOPLEVEL_NEXT_WS]
    test rdx, rdx
    jz .done
    cmp rdx, r12
    je .unlink
    mov rax, rdx
    jmp .prev_loop

.unlink:
    mov rdx, [r12 + TOPLEVEL_NEXT_WS]
    mov [rax + TOPLEVEL_NEXT_WS], rdx

.done:
    mov qword [r12 + TOPLEVEL_WORKSPACE], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; workspace_get_toplevels
;   Get toplevels on workspace
; ============================================================================
global workspace_get_toplevels
workspace_get_toplevels:
    PROLOGUE
    mov rax, [rdi + WORKSPACE_TOPLEVELS]
    leave
    ret

section .data
global workspace_version
workspace_version: dq 0x010000
