; ============================================================================
; Kiosk Policy — Single Locked-Down App, No Escape
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define PolicyKiosk_size    40

section .text

struc PolicyKiosk
    .base:              resq 1
    .server:            resq 1
    .data:              resq 1
    .allowed_app_id:    resq 1
    .allow_exit:        resb 1
    .auto_restart:      resb 1
endstruc

; ---------------------------------------------------------------------------
; policy_kiosk_init
; ---------------------------------------------------------------------------
global policy_kiosk_init
policy_kiosk_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + PolicyKiosk.base], rdi
    mov qword [rbx + PolicyKiosk.server], r12
    mov qword [rbx + PolicyKiosk.data], 0
    mov qword [rbx + PolicyKiosk.allowed_app_id], r13
    mov byte [rbx + PolicyKiosk.allow_exit], 0
    mov byte [rbx + PolicyKiosk.auto_restart], 1

    ; Set function pointers
    mov qword [rdi + Policy.layout], policy_kiosk_layout
    mov qword [rdi + Policy.configure], policy_kiosk_configure
    mov qword [rdi + Policy.focus_change], policy_kiosk_focus_change
    mov qword [rdi + Policy.new_window], policy_kiosk_new_window
    mov qword [rdi + Policy.close_window], policy_kiosk_close_window
    mov qword [rdi + Policy.workspace_changed], policy_kiosk_workspace_changed
    mov qword [rdi + Policy.tile_window], policy_kiosk_tile_window
    mov qword [rdi + Policy.window_configured], policy_kiosk_window_configured

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_layout
;   Kiosk layout: single window fullscreen, no other windows allowed
; ---------------------------------------------------------------------------
global policy_kiosk_layout
policy_kiosk_layout:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Only one window allowed - make it fullscreen
    mov rax, [r12 + Output.toplevels]
    test rax, rax
    jz .done

    ; First window - fullscreen
    mov rbx, rax
    mov eax, [rbx + Toplevel.state]
    or eax, STATE_FLAG_FULLSCREEN
    mov [rbx + Toplevel.state], eax

    ; Remove any other windows
    mov rax, [rax + Toplevel.next_ws]
.remove_loop:
    test rax, rax
    jz .done
    ; Close additional windows
    mov r12, rax
    mov rax, [rax + Toplevel.next_ws]
    mov rdi, [r12 + Toplevel.shell]
    mov rsi, r12
    call toplevel_destroy
    mov rax, r12
    jmp .remove_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_configure
;   Only allow fullscreen geometry
; ---------------------------------------------------------------------------
global policy_kiosk_configure
policy_kiosk_configure:
    PROLOGUE
    ; Only allow fullscreen geometry
    mov rax, -(ENOTSUP)
    leave
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_focus_change
;   No focus changes allowed (only one window)
; ---------------------------------------------------------------------------
global policy_kiosk_focus_change
policy_kiosk_focus_change:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_new_window
;   Only allow one window (the kiosk app)
; ---------------------------------------------------------------------------
global policy_kiosk_new_window
policy_kiosk_new_window:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check if app_id matches allowed
    mov rax, [rbx + PolicyKiosk.allowed_app_id]
    test rax, rax
    jz .allow

    mov r13, [r12 + Toplevel.app_id]
    test r13, r13
    jz .deny

    mov rdi, rax
    mov rsi, r13
    call str_compare
    test rax, rax
    jnz .deny

.allow:
    ; Allow first window
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.deny:
    mov rax, -(EPERM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_close_window
;   Only allow closing if allow_exit is set
; ---------------------------------------------------------------------------
global policy_kiosk_close_window
policy_kiosk_close_window:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Check if exit allowed
    mov al, [rbx + PolicyKiosk.allow_exit]
    test al, al
    jnz .allow

    ; Auto-restart if enabled
    mov al, [rbx + PolicyKiosk.auto_restart]
    test al, al
    jnz .restart

    mov rax, -(EPERM)
    EPILOGUE_RESTORE rbx
    ret

.restart:
    ; Auto-restart the app
    ; TODO: Implement
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.allow:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_workspace_changed
; ---------------------------------------------------------------------------
global policy_kiosk_workspace_changed
policy_kiosk_workspace_changed:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_tile_window
; ---------------------------------------------------------------------------
global policy_kiosk_tile_window
policy_kiosk_tile_window:
    PROLOGUE
    mov rax, -(ENOTSUP)
    leave
    ret

; ---------------------------------------------------------------------------
; policy_kiosk_window_configured
; ---------------------------------------------------------------------------
global policy_kiosk_window_configured
policy_kiosk_window_configured:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
global policy_kiosk_version
policy_kiosk_version: dq 0x010000
