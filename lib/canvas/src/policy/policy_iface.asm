; ============================================================================
; Policy Interface — Window Management Policy (Pluggable)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Policy {
    .server:            resq 1
    .name:              resq 1
    .layout:            resq 1
    .configure:         resq 1
    .focus_change:      resq 1
    .new_window:        resq 1
    .close_window:      resq 1
    .workspace_changed: resq 1
    .tile_window:       resq 1
    .window_configured: resq 1
    .data:              resq 1
}
%define Policy_size    80

; ---------------------------------------------------------------------------
; policy_init
; ---------------------------------------------------------------------------
global policy_init
policy_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.policy], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_register
;   Register policy with server
; ---------------------------------------------------------------------------
global policy_register
policy_register:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [r12 + Policy.server], rdi
    mov qword [rbx + Server.policy], r12
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_unregister
; ---------------------------------------------------------------------------
global policy_unregister
policy_unregister:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_layout
;   Layout windows on output
; ---------------------------------------------------------------------------
global policy_layout
policy_layout:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Default: do nothing (floating)
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_configure
;   Handle configure request
; ---------------------------------------------------------------------------
global policy_configure
policy_configure:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_focus_change
; ---------------------------------------------------------------------------
global policy_focus_change
policy_focus_change:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_new_window
;   Called when new toplevel is created
; ---------------------------------------------------------------------------
global policy_new_window
policy_new_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Default: place at cursor or center
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_close_window
; ---------------------------------------------------------------------------
global policy_close_window
policy_close_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Default: nothing
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_workspace_changed
; ---------------------------------------------------------------------------
global policy_workspace_changed
policy_workspace_changed:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_tile_window
;   Request to tile a window
; ---------------------------------------------------------------------------
global policy_tile_window
policy_tile_window:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_window_configured
;   Called when window acks configure
; ---------------------------------------------------------------------------
global policy_window_configured
policy_window_configured:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; policy_load_config
; ---------------------------------------------------------------------------
global policy_load_config
policy_load_config:
    PROLOGUE
    xor rax, rax
    ret

section .data
global policy_version
policy_version: dq 0x010000