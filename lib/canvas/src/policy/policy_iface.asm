; ============================================================================
; Policy Interface — Window Management Policy (Pluggable)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define Policy_SIZE    80

section .text

; Policy struct layout (manual offsets)
; Offsets defined in inc/struct_offsets.inc

; ----------


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
    EPILOGUE_RESTORE rbx, r12
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
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_unregister
; ---------------------------------------------------------------------------
global policy_unregister
policy_unregister:
    PROLOGUE
    xor rax, rax
    leave
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
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_configure
;   Handle configure request
; ---------------------------------------------------------------------------
global policy_configure
policy_configure:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_focus_change
; ---------------------------------------------------------------------------
global policy_focus_change
policy_focus_change:
    PROLOGUE
    xor rax, rax
    leave
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
    EPILOGUE_RESTORE rbx, r12
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
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_workspace_changed
; ---------------------------------------------------------------------------
global policy_workspace_changed
policy_workspace_changed:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_tile_window
;   Request to tile a window
; ---------------------------------------------------------------------------
global policy_tile_window
policy_tile_window:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_window_configured
;   Called when window acks configure
; ---------------------------------------------------------------------------
global policy_window_configured
policy_window_configured:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_load_config
; ---------------------------------------------------------------------------
global policy_load_config
policy_load_config:
    PROLOGUE
    xor rax, rax
    leave
    ret

; Session transitions are policy notifications. Base policies have no private
; lock state, but validate both objects so callers get deterministic failures.
global policy_session_lock
policy_session_lock:
    test rdi, rdi
    jz policy_session_invalid
    test rsi, rsi
    jz policy_session_invalid
    xor eax, eax
    ret

global policy_session_unlock
policy_session_unlock:
    test rdi, rdi
    jz policy_session_invalid
    test rsi, rsi
    jz policy_session_invalid
    xor eax, eax
    ret
policy_session_invalid:
    mov rax, -(EINVAL)
    ret

section .data
global policy_version
policy_version: dq 0x010000
