; ============================================================================
; Shell — Window Shell Protocol Implementation
; Roles, states, configure/ack, workspaces, layers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Shell {
    .server:        resq 1
    .toplevels:     resq 1
    .popups:        resq 1
    .layers:        resq 1
    .workspaces:    resq 1
    .active_ws:     resd 1
    .num_workspaces: resd 1
    .policy:        resq 1
}
%define Shell_size    56

%define SHELL_ROLE_NONE       0
%define SHELL_ROLE_TOPLEVEL   1
%define SHELL_ROLE_POPUP      2
%define SHELL_ROLE_LAYER      3
%define SHELL_ROLE_DIALOG     4

%define TOPLEVEL_STATE_DEFAULT    0
%define TOPLEVEL_STATE_MAXIMIZED  1
%define TOPLEVEL_STATE_FULLSCREEN 2
%define TOPLEVEL_STATE_MINIMIZED  3
%define TOPLEVEL_STATE_TILED      4
%define TOPLEVEL_STATE_FLOATING   5

%define POPUP_POSITION_CENTER     0
%define POPUP_POSITION_CURSOR     1
%define POPUP_POSITION_RECT       2

%define LAYER_BACKGROUND      0
%define LAYER_BOTTOM          1
%define LAYER_NORMAL          2
%define LAYER_TOP             3
%define LAYER_OVERLAY         4
%define LAYER_LOCK            5

%define WORKSPACE_STATE_ACTIVE    1
%define WORKSPACE_STATE_INACTIVE  0

; ---------------------------------------------------------------------------
; shell_init
;   Initialize shell subsystem
; ---------------------------------------------------------------------------
global shell_init
shell_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.shell], 0
    mov qword [rbx + Server.arena], r12

    ; Allocate shell
    mov rdi, r12
    mov rsi, Shell_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Shell.server], rdi
    mov qword [rbx + Shell.toplevels], 0
    mov qword [rbx + Shell.popups], 0
    mov qword [rbx + Shell.layers], 0
    mov qword [rbx + Shell.workspaces], 0
    mov dword [rbx + Shell.active_ws], 0
    mov dword [rbx + Shell.num_workspaces], 4
    mov qword [rbx + Shell.policy], 0

    ; Create default workspaces
    call shell_create_workspaces

    ; Load policy
    call shell_load_policy

    mov qword [rdi + Server.shell], rbx
    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; shell_create_workspaces
; ---------------------------------------------------------------------------
shell_create_workspaces:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, [rbx + Server.arena]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13d, [rbx + Shell.num_workspaces]
    test r13d, r13d
    jz .done

.ws_loop:
    ; Create workspace
    mov rdi, r12
    mov rsi, Workspace_size
    call arena_alloc
    test rax, rax
    jz .oom

    ; Initialize workspace
    mov dword [rax + Workspace.id], r13d
    mov qword [rax + Workspace.shell], rbx
    mov qword [rax + Workspace.toplevels], 0
    mov dword [rax + Workspace.state], WORKSPACE_STATE_INACTIVE
    mov dword [rax + Workspace.layout_engine], 0

    ; Add to shell
    mov rdx, [rbx + Shell.workspaces]
    mov [rax + Workspace.next], rdx
    mov [rbx + Shell.workspaces], rax

    dec r13d
    jnz .ws_loop

    ; Set first workspace active
    mov rax, [rbx + Shell.workspaces]
    mov dword [rax + Workspace.state], WORKSPACE_STATE_ACTIVE
    mov dword [rbx + Shell.active_ws], 0

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; shell_load_policy
; ---------------------------------------------------------------------------
shell_load_policy:
    PROLOGUE
    ; TODO: Load policy from config
    ; For now, use default floating policy
    mov rax, [rbx + Shell.server]
    mov rdi, [rax + Server.arena]
    mov rsi, PolicyFloating_size
    call arena_alloc
    test rax, rax
    jz .fail

    ; Initialize floating policy
    call policy_floating_init

    mov [rbx + Shell.policy], rax
    ret

.fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; shell_set_policy
; ---------------------------------------------------------------------------
global shell_set_policy
shell_set_policy:
    PROLOGUE
    ; TODO: Switch policy at runtime
    xor rax, rax
    ret

section .data

%define Shell_server      0
%define Shell_toplevels   8
%define Shell_popups      16
%define Shell_layers      24
%define Shell_workspaces  32
%define Shell_active_ws   40
%define Shell_num_workspaces 44
%define Shell_policy      48
%define Shell_size        56

%define Workspace_id      0
%define Workspace_shell   8
%define Workspace_toplevels 16
%define Workspace_state   24
%define Workspace_layout_engine 28
%define Workspace_next    32
%define Workspace_size    40

global shell_version
shell_version: dq 0x010000