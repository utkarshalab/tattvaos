; ============================================================================
; Shell Core — Window Management, Focus, Input, Output Integration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/backend.inc"

extern layer_destroy
extern policy_init
extern popup_destroy
extern input_focus_surface
extern toplevel_create
extern toplevel_destroy
extern toplevel_schedule_configure
extern workspace_add_toplevel
extern workspace_create
extern workspace_destroy

section .text

; ============================================================================
; shell_create
;   Create shell
; ============================================================================
global shell_create
shell_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi  ; server
    mov r13, rdx  ; seat
    mov r14, rcx  ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14

    mov qword [rbx + Shell.server], r12
    mov qword [rbx + Shell.seat], r13
    mov qword [rbx + Shell.arena], r14
    mov qword [rbx + Shell.toplevels], 0
    mov qword [rbx + Shell.popups], 0
    mov qword [rbx + Shell.layers], 0
    mov qword [rbx + Shell.workspaces], 0
    mov qword [rbx + Shell.active_ws], 0
    mov dword [rbx + Shell.workspace_count], 0
    mov qword [rbx + Shell.configure_list], 0
    mov dword [rbx + Shell.configure_count], 0
    mov qword [rbx + Shell.policy], 0
    mov qword [rbx + Shell.theme], 0

    ; Create default workspaces
    call .create_default_workspaces

    ; Initialize default policy (floating)
    call policy_init
    mov qword [rbx + Shell.policy], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.create_default_workspaces:
    ; Create workspace for each output
    mov r12, [rbx + Shell.server]
    mov r12, [r12 + Server.outputs]
.ws_loop:
    test r12, r12
    jz .done

    mov rdi, rbx
    mov rsi, rbx
    mov rdx, r12
    call workspace_create

    mov r12, [r12 + Output.next]
    jmp .ws_loop

.done:
    ret

; ============================================================================
; shell_destroy
;   Destroy shell
; ============================================================================
global shell_destroy
shell_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Destroy all toplevels
    mov rax, [rbx + Shell.toplevels]
.toplevel_loop:
    test rax, rax
    jz .toplevels_done
    push rax
    call toplevel_destroy
    pop rax
    mov rax, [rax + Toplevel.next_ws]
    jmp .toplevel_loop

.toplevels_done:
    ; Destroy all popups
    mov rax, [rbx + Shell.popups]
.popup_loop:
    test rax, rax
    jz .popups_done
    push rax
    call popup_destroy
    pop rax
    mov rax, [rax + Popup.next]
    jmp .popup_loop

.popups_done:
    ; Destroy all layers
    mov rax, [rbx + Shell.layers]
.layer_loop:
    test rax, rax
    jz .layers_done
    push rax
    call layer_destroy
    pop rax
    mov rax, [rax + Layer.next]
    jmp .layer_loop

.layers_done:
    ; Destroy workspaces
    mov rax, [rbx + Shell.workspaces]
.ws_loop:
    test rax, rax
    jz .workspaces_done
    push rax
    call workspace_destroy
    pop rax
    mov rax, [rax + Workspace.next]
    jmp .ws_loop

.workspaces_done:
    ; Destroy policy
    mov rax, [rbx + Shell.policy]
    test rax, rax
    jz .done
    ; policy_destroy would be called here

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; shell_get_toplevel_at
;   Get toplevel at screen coordinates
; ============================================================================
global shell_get_toplevel_at
shell_get_toplevel_at:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Iterate toplevels from top to bottom (Z-order)
    mov rax, [rbx + Shell.toplevels]
.tl_loop:
    test rax, rax
    jz .not_found

    ; Check if point is within toplevel
    mov r14d, [rax + Toplevel.x]
    mov r15d, [rax + Toplevel.y]
    mov r14d, [rax + Toplevel.width]
    mov r15d, [rax + Toplevel.height]

    ; Check bounds
    cmp r12d, r14d
    jl .next_tl
    cmp r13d, r15d
    jl .next_tl
    cmp r12d, r14d
    jge .next_tl
    cmp r13d, r15d
    jge .next_tl

    ; Found
    jmp .found

.next_tl:
    mov rax, [rax + Toplevel.next_ws]
    jmp .tl_loop

.found:
    EPILOGUE_RESTORE rbx
    ret

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; shell_focus_toplevel
;   Set keyboard focus to toplevel
; ============================================================================
global shell_focus_toplevel
shell_focus_toplevel:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Keyboard focus to its surface; no toplevel: to none
    mov rdi, [rbx + Shell.server]
    xor esi, esi
    test r12, r12
    jz .focus
    mov rsi, [r12 + Toplevel.surface]
.focus:
    call input_focus_surface

    ; Call policy focus change
    mov rax, [rbx + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r12
    call qword [rax + Policy.focus_change]

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13

; ============================================================================
; shell_get_active_toplevel
;   Get currently focused toplevel
; ============================================================================
global shell_get_active_toplevel
shell_get_active_toplevel:
    PROLOGUE
    mov rax, [rdi + Shell.seat]
    mov rax, [rax + Seat.focus]
    leave
    ret

; ============================================================================
; shell_new_toplevel
;   Create new toplevel from surface
; ============================================================================
global shell_new_toplevel
shell_new_toplevel:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi  ; surface
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create toplevel
    mov rdi, rbx
    mov rsi, rbx
    mov rdx, r12
    mov rcx, 0  ; title
    mov r8, 0   ; app_id
    call toplevel_create
    test rax, rax
    jnz .fail

    ; Add to workspace
    mov rax, [rbx + Shell.active_ws]
    test rax, rax
    jz .fail
    mov rdi, rax
    mov rsi, rax
    call workspace_add_toplevel

    ; Call policy new window
    mov rax, [rbx + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rax
    call qword [rax + Policy.new_window]

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.fail:
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; shell_close_toplevel
;   Close toplevel
; ============================================================================
global shell_close_toplevel
shell_close_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Call policy close
    mov rax, [rbx + Shell.policy]
    test rax, rax
    jz .direct
    mov rdi, rax
    call qword [rax + Policy.close_window]

.direct:
    call toplevel_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; shell_maximize_toplevel
;   Maximize toplevel
; ============================================================================
global shell_maximize_toplevel
shell_maximize_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [r12 + Toplevel.state]
    test eax, TOPLEVEL_STATE_MAXIMIZED
    jz .do_maximize

    ; Restore
    mov eax, [r12 + Toplevel.state]
    and eax, ~TOPLEVEL_STATE_MAXIMIZED
    mov dword [r12 + Toplevel.pending_state], eax
    jmp .schedule

.do_maximize:
    mov eax, [r12 + Toplevel.state]
    or eax, TOPLEVEL_STATE_MAXIMIZED
    mov dword [r12 + Toplevel.pending_state], eax

.schedule:
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; shell_fullscreen_toplevel
;   Fullscreen toplevel
; ============================================================================
global shell_fullscreen_toplevel
shell_fullscreen_toplevel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [r12 + Toplevel.state]
    test eax, TOPLEVEL_STATE_FULLSCREEN
    jz .do_fullscreen

    ; Exit fullscreen
    mov eax, [r12 + Toplevel.state]
    and eax, ~TOPLEVEL_STATE_FULLSCREEN
    mov dword [r12 + Toplevel.pending_state], eax
    jmp .schedule

.do_fullscreen:
    mov eax, [r12 + Toplevel.state]
    or eax, TOPLEVEL_STATE_FULLSCREEN
    mov dword [r12 + Toplevel.pending_state], eax

.schedule:
    call toplevel_schedule_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; shell_set_policy
;   Set window management policy
; ============================================================================
global shell_set_policy
shell_set_policy:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi  ; type
    mov r13, rdx  ; arena
    mov r14, rcx  ; config
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Destroy old policy
    mov rax, [rbx + Shell.policy]
    test rax, rax
    jz .create_new
    ; policy_destroy would go here

.create_new:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call policy_init
    mov [rbx + Shell.policy], rax

    xor rax, rax
    leave
    ret

; ============================================================================
; shell_get_toplevels
;   Get all toplevels
; ============================================================================
global shell_get_toplevels
shell_get_toplevels:
    PROLOGUE
    mov rax, [rdi + Shell.toplevels]
    leave
    ret

; ============================================================================
; shell_get_popups
;   Get all popups
; ============================================================================
global shell_get_popups
shell_get_popups:
    PROLOGUE
    mov rax, [rdi + Shell.popups]
    leave
    ret

; ============================================================================
; shell_get_layers
;   Get all layers
; ============================================================================
global shell_get_layers
shell_get_layers:
    PROLOGUE
    mov rax, [rdi + Shell.layers]
    leave
    ret

; ============================================================================
; shell_get_outputs
;   Get all outputs
; ============================================================================
global shell_get_outputs
shell_get_outputs:
    PROLOGUE
    mov rax, [rdi + Shell.outputs]
    leave
    ret

section .data
global shell_version
shell_version: dq 0x010000
