; ============================================================================
; Workspace — Virtual Desktops / Workspaces
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Workspace_size    56
%define WORKSPACE_STATE_ACTIVE    1
%define WORKSPACE_STATE_INACTIVE  0

section .text

struc Workspace
    .id:                resd 1
    .shell:             resq 1
    .toplevels:         resq 1
    .state:             resd 1
    .layout_engine:     resq 1
    .name:              resq 1
    .next:              resq 1
    .next_ws:           resq 1
endstruc


; ---------------------------------------------------------------------------
; workspace_create
;   Create workspace
; ---------------------------------------------------------------------------
global workspace_create
workspace_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate workspace
    mov rdi, [rbx + Server.arena]
    mov rsi, Workspace_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov dword [rbx + Workspace.id], r13d
    mov qword [rbx + Workspace.shell], r12
    mov qword [rbx + Workspace.toplevels], 0
    mov dword [rbx + Workspace.state], WORKSPACE_STATE_INACTIVE
    mov qword [rbx + Workspace.layout_engine], 0
    mov qword [rbx + Workspace.name], 0
    mov qword [rbx + Workspace.next], 0
    mov qword [rbx + Workspace.next_ws], 0

    ; Add to shell
    mov rax, [r12 + Shell.workspaces]
    mov [rbx + Workspace.next], rax
    mov [r12 + Shell.workspaces], rbx
    inc dword [r12 + Shell.num_workspaces]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; workspace_destroy
; ---------------------------------------------------------------------------
global workspace_destroy
workspace_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Move toplevels to another workspace
    ; TODO

    ; Remove from shell list
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; workspace_set_active
;   Switch active workspace
; ---------------------------------------------------------------------------
global workspace_set_active
workspace_set_active:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Deactivate current
    mov rax, [r12 + Shell.workspaces]
.find_active:
    test rax, rax
    jz .set_new
    cmp dword [rax + Workspace.state], WORKSPACE_STATE_ACTIVE
    je .deactivate
    mov rax, [rax + Workspace.next]
    jmp .find_active

.deactivate:
    mov dword [rax + Workspace.state], WORKSPACE_STATE_INACTIVE
    ; Hide all toplevels on this workspace
    ; TODO

.set_new:
    ; Activate new
    mov dword [r12 + Workspace.state], WORKSPACE_STATE_ACTIVE
    mov eax, [r12 + Workspace.id]
    mov [r12 + Shell.active_ws], eax

    ; Show toplevels
    ; TODO

    ; Update policy
    mov rax, [r12 + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r12
    call policy_workspace_changed

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; workspace_add_toplevel
; ---------------------------------------------------------------------------
global workspace_add_toplevel
workspace_add_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Add to workspace's toplevel list
    mov rax, [rbx + Workspace.toplevels]
    mov [r12 + Toplevel.next_ws], rax
    mov [rbx + Workspace.toplevels], r12

    ; Set toplevel's workspace
    mov qword [r12 + Toplevel.workspace], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; workspace_remove_toplevel
; ---------------------------------------------------------------------------
global workspace_remove_toplevel
workspace_remove_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Remove from workspace's toplevel list
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; workspace_get_toplevels
; ---------------------------------------------------------------------------
global workspace_get_toplevels
workspace_get_toplevels:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Workspace.toplevels]
    leave
    ret

; ---------------------------------------------------------------------------
; workspace_get_active
; ---------------------------------------------------------------------------
global workspace_get_active
workspace_get_active:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Shell.workspaces]
.find_loop:
    test rax, rax
    jz .none
    cmp dword [rax + Workspace.state], WORKSPACE_STATE_ACTIVE
    je .found
    mov rax, [rax + Workspace.next]
    jmp .find_loop

.found:
    EPILOGUE_RESTORE rbx
    ret
.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; workspace_get_by_id
; ---------------------------------------------------------------------------
global workspace_get_by_id
workspace_get_by_id:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    mov rax, [rbx + Shell.workspaces]
.find_loop:
    test rax, rax
    jz .not_found
    cmp dword [rax + Workspace.id], r12d
    je .found
    mov rax, [rax + Workspace.next]
    jmp .find_loop

.found:
    EPILOGUE_RESTORE rbx, r12
    ret
.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; workspace_set_name
; ---------------------------------------------------------------------------
global workspace_set_name
workspace_set_name:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Free old name
    mov rax, [rbx + Workspace.name]
    test rax, rax
    jz .set_new
    ; TODO: free

.set_new:
    ; Copy new name
    call str_dup_arena
    test rax, rax
    jz .oom
    mov [rbx + Workspace.name], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; workspace_set_layout
;   Set layout engine for workspace
; ---------------------------------------------------------------------------
global workspace_set_layout
workspace_set_layout:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + Workspace.layout_engine], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global workspace_version
workspace_version: dq 0x010000
