; ============================================================================
; Policy Engine — Window Management Policies (Floating, Tiling, Kiosk)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; policy_init
;   Initialize policy engine
; ============================================================================
global policy_init
policy_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi  ; server
    mov r13, rdx  ; type (0=floating, 1=tiling, 2=kiosk)
    mov r14, rcx  ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14

    mov qword [rbx + POLICY_SERVER], r12
    mov dword [rbx + POLICY_TYPE], r13d

    ; Initialize based on type
    cmp r13d, 0
    je .floating
    cmp r13d, 1
    je .tiling
    cmp r13d, 2
    je .kiosk
    mov rax, -EINVAL
    jmp .done

.floating:
    call policy_floating_init
    jmp .done

.tiling:
    call policy_tiling_init
    jmp .done

.kiosk:
    call policy_kiosk_init
    jmp .done

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; policy_floating_init
;   Initialize floating policy
; ============================================================================
global policy_floating_init
policy_floating_init:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + POLICY_TYPE], 0
    mov qword [rbx + POLICY_CONFIGURE], policy_floating_configure
    mov qword [rbx + POLICY_FOCUS_CHANGE], policy_floating_focus
    mov qword [rbx + POLICY_NEW_WINDOW], policy_floating_new_window
    mov qword [rbx + POLICY_CLOSE_WINDOW], policy_floating_close
    mov qword [rbx + POLICY_WS_CHANGED], policy_floating_ws_changed

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; policy_tiling_init
;   Initialize tiling policy
; ============================================================================
global policy_tiling_init
policy_tiling_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov dword [rbx + POLICY_TYPE], 1
    mov qword [rbx + POLICY_CONFIGURE], policy_tiling_configure
    mov qword [rbx + POLICY_FOCUS_CHANGE], policy_tiling_focus
    mov qword [rbx + POLICY_NEW_WINDOW], policy_tiling_new_window
    mov qword [rbx + POLICY_CLOSE_WINDOW], policy_tiling_close
    mov qword [rbx + POLICY_WS_CHANGED], policy_tiling_ws_changed
    mov qword [rbx + POLICY_LAYOUT], 0  ; layout engine

    ; Create layout engine
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call layout_engine_create

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; policy_kiosk_init
;   Initialize kiosk policy
; ============================================================================
global policy_kiosk_init
policy_kiosk_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14

    mov dword [rbx + POLICY_TYPE], 2
    mov qword [rbx + POLICY_CONFIGURE], policy_kiosk_configure
    mov qword [rbx + POLICY_FOCUS_CHANGE], policy_kiosk_focus
    mov qword [rbx + POLICY_NEW_WINDOW], policy_kiosk_new_window
    mov qword [rbx + POLICY_CLOSE_WINDOW], policy_kiosk_close
    mov qword [rbx + POLICY_WS_CHANGED], policy_kiosk_ws_changed

    ; Store kiosk config
    mov qword [rbx + POLICY_KIOSK_ALLOWED_APP], r14

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; Policy Callbacks — Floating
; ============================================================================

policy_floating_configure:
    ; Floating: respect client's requested size/position
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Just apply client's requested size
    call toplevel_configure
    EPILOGUE_RESTORE rbx, r12
    ret

policy_floating_focus:
    ; Raise window on focus
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Raise in compositor
    call compositor_raise_surface
    EPILOGUE_RESTORE rbx, r12
    ret

policy_floating_new_window:
    ; Position new window (cascade or center)
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Center on output or cascade
    call .cascade_position

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.cascade_position:
    ; Simple cascade: offset by 20px from last window
    ret

policy_floating_close:
    ; Nothing special
    xor rax, rax
    leave
    ret

policy_floating_ws_changed:
    ; Move window to new workspace
    xor rax, rax
    leave
    ret

; ============================================================================
; Policy Callbacks — Tiling
; ============================================================================

policy_tiling_configure:
    ; Tiling: apply layout engine
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get layout engine
    mov rax, [rbx + POLICY_LAYOUT]
    test rax, rax
    jz .no_layout

    ; Get output rect
    mov rdi, rax
    mov rsi, rsp
    call layout_apply

.no_layout:
    call toplevel_configure
    EPILOGUE_RESTORE rbx, r12
    ret

policy_tiling_focus:
    ; Focus follows mouse or keyboard
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Update layout focus
    call compositor_focus_surface

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

policy_tiling_new_window:
    ; Add to layout engine
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + POLICY_LAYOUT]
    test rax, rax
    jz .no_layout

    mov rdi, rax
    mov rsi, r12
    call layout_add_toplevel

.no_layout:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

policy_tiling_close:
    ; Remove from layout
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + POLICY_LAYOUT]
    test rax, rax
    jz .no_layout

    mov rdi, rax
    mov rsi, r12
    call layout_remove_toplevel

.no_layout:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

policy_tiling_ws_changed:
    ; Re-apply layout on workspace change
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + POLICY_LAYOUT]
    test rax, rax
    jz .no_layout

    mov rdi, rax
    mov rsi, rsp
    call layout_apply

.no_layout:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; Policy Callbacks — Kiosk
; ============================================================================

policy_kiosk_configure:
    ; Kiosk: force fullscreen, no decorations
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Force fullscreen state
    mov eax, [r12 + CONFIGURE_STATES]
    or eax, TOPLEVEL_STATE_FULLSCREEN
    mov [r12 + CONFIGURE_STATES], eax

    ; No decorations
    call toplevel_configure

    EPILOGUE_RESTORE rbx, r12
    ret

policy_kiosk_focus:
    ; Only allow configured app
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check if this is the allowed app
    mov rax, [rbx + POLICY_KIOSK_ALLOWED_APP]
    mov rdx, [r12 + TOPLEVEL_APP_ID]
    cmp rax, rdx
    je .allow

    ; Not allowed - deny focus
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

.allow:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

policy_kiosk_new_window:
    ; Deny new windows (only one app allowed)
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check if this is the allowed app
    mov rax, [rbx + POLICY_KIOSK_ALLOWED_APP]
    mov rdx, [r12 + TOPLEVEL_APP_ID]
    cmp rax, rdx
    je .allow

    ; Not allowed - destroy window
    call toplevel_destroy
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

.allow:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

policy_kiosk_close:
    ; If kiosk app closes, restart or shutdown
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + POLICY_KIOSK_ALLOWED_APP]
    mov rdx, [r12 + TOPLEVEL_APP_ID]
    cmp rax, rdx
    je .restart
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.restart:
    ; Schedule restart
    ; ...
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

policy_kiosk_ws_changed:
    ; Kiosk doesn't support workspaces
    xor rax, rax
    leave
    ret

; ============================================================================
; policy_external_init
;   Initialize external policy (cw_policy process)
; ============================================================================
global policy_external_init
policy_external_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Connect to cw_policy process
    call cw_policy_external_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; policy_iface_init
;   Initialize policy interface
; ============================================================================
global policy_iface_init
policy_iface_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    call cw_policy_iface_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global policy_version
policy_version: dq 0x010000