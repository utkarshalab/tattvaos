; ============================================================================
; Shell Core — Window Management, Focus, Input, Output Integration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/externs.inc"

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

    mov qword [rbx + SHELL_SERVER], r12
    mov qword [rbx + SHELL_SEAT], r13
    mov qword [rbx + SHELL_ARENA], r14
    mov qword [rbx + SHELL_TOPLEVELS], 0
    mov qword [rbx + SHELL_POPUPS], 0
    mov qword [rbx + SHELL_LAYERS], 0
    mov qword [rbx + SHELL_WORKSPACES], 0
    mov qword [rbx + SHELL_ACTIVE_WS], 0
    mov dword [rbx + SHELL_WORKSPACE_COUNT], 0
    mov qword [rbx + SHELL_CONFIGURE_LIST], 0
    mov dword [rbx + SHELL_CONFIGURE_COUNT], 0
    mov qword [rbx + SHELL_POLICY], 0
    mov qword [rbx + SHELL_THEME], 0

    ; Create default workspaces
    call .create_default_workspaces

    ; Initialize default policy (floating)
    call policy_init
    mov qword [rbx + SHELL_POLICY], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.create_default_workspaces:
    ; Create workspace for each output
    mov r12, [rbx + SHELL_SERVER]
    mov r12, [r12 + SERVER_OUTPUTS]
.ws_loop:
    test r12, r12
    jz .done

    mov rdi, rbx
    mov rsi, rbx
    mov rdx, r12
    call workspace_create

    mov r12, [r12 + OUTPUT_NEXT]
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
    mov rax, [rbx + SHELL_TOPLEVELS]
.toplevel_loop:
    test rax, rax
    jz .toplevels_done
    push rax
    call toplevel_destroy
    pop rax
    mov rax, [rax + TOPLEVEL_NEXT_WS]
    jmp .toplevel_loop

.toplevels_done:
    ; Destroy all popups
    mov rax, [rbx + SHELL_POPUPS]
.popup_loop:
    test rax, rax
    jz .popups_done
    push rax
    call popup_destroy
    pop rax
    mov rax, [rax + POPUP_NEXT]
    jmp .popup_loop

.popups_done:
    ; Destroy all layers
    mov rax, [rbx + SHELL_LAYERS]
.layer_loop:
    test rax, rax
    jz .layers_done
    push rax
    call layer_destroy
    pop rax
    mov rax, [rax + LAYER_NEXT]
    jmp .layer_loop

.layers_done:
    ; Destroy workspaces
    mov rax, [rbx + SHELL_WORKSPACES]
.ws_loop:
    test rax, rax
    jz .workspaces_done
    push rax
    call workspace_destroy
    pop rax
    mov rax, [rax + WORKSPACE_NEXT]
    jmp .ws_loop

.workspaces_done:
    ; Destroy policy
    mov rax, [rbx + SHELL_POLICY]
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
    mov rax, [rbx + SHELL_TOPLEVELS]
.tl_loop:
    test rax, rax
    jz .not_found

    ; Check if point is within toplevel
    mov r14d, [rax + TOPLEVEL_X]
    mov r15d, [rax + TOPLEVEL_Y]
    mov r14d, [rax + TOPLEVEL_WIDTH]
    mov r15d, [rax + TOPLEVEL_HEIGHT]

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
    mov rax, [rax + TOPLEVEL_NEXT_WS]
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

    ; Update focus
    mov rax, [rbx + SHELL_SEAT]
    mov rdi, rax
    mov rsi, r12
    call seat_set_focus

    ; Call policy focus change
    mov rax, [rbx + SHELL_POLICY]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r12
    call qword [rax + POLICY_FOCUS_CHANGE]

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; shell_get_active_toplevel
;   Get currently focused toplevel
; ============================================================================
global shell_get_active_toplevel
shell_get_active_toplevel:
    PROLOGUE
    mov rax, [rdi + SHELL_SEAT]
    mov rax, [rax + SEAT_FOCUS]
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
    mov rax, [rbx + SHELL_ACTIVE_WS]
    test rax, rax
    jz .fail
    mov rdi, rax
    mov rsi, rax
    call workspace_add_toplevel

    ; Call policy new window
    mov rax, [rbx + SHELL_POLICY]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rax
    call qword [rax + POLICY_NEW_WINDOW]

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
    mov rax, [rbx + SHELL_POLICY]
    test rax, rax
    jz .direct
    mov rdi, rax
    call qword [rax + POLICY_CLOSE_WINDOW]

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

    mov eax, [r12 + TOPLEVEL_STATE]
    test eax, TOPLEVEL_STATE_MAXIMIZED
    jz .do_maximize

    ; Restore
    mov eax, [r12 + TOPLEVEL_STATE]
    and eax, ~TOPLEVEL_STATE_MAXIMIZED
    mov dword [r12 + TOPLEVEL_PENDING_STATE], eax
    jmp .schedule

.do_maximize:
    mov eax, [r12 + TOPLEVEL_STATE]
    or eax, TOPLEVEL_STATE_MAXIMIZED
    mov dword [r12 + TOPLEVEL_PENDING_STATE], eax

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

    mov eax, [r12 + TOPLEVEL_STATE]
    test eax, TOPLEVEL_STATE_FULLSCREEN
    jz .do_fullscreen

    ; Exit fullscreen
    mov eax, [r12 + TOPLEVEL_STATE]
    and eax, ~TOPLEVEL_STATE_FULLSCREEN
    mov dword [r12 + TOPLEVEL_PENDING_STATE], eax
    jmp .schedule

.do_fullscreen:
    mov eax, [r12 + TOPLEVEL_STATE]
    or eax, TOPLEVEL_STATE_FULLSCREEN
    mov dword [r12 + TOPLEVEL_PENDING_STATE], eax

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
    mov rax, [rbx + SHELL_POLICY]
    test rax, rax
    jz .create_new
    ; policy_destroy would go here

.create_new:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call policy_init
    mov [rbx + SHELL_POLICY], rax

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
    mov rax, [rdi + SHELL_TOPLEVELS]
    leave
    ret

; ============================================================================
; shell_get_popups
;   Get all popups
; ============================================================================
global shell_get_popups
shell_get_popups:
    PROLOGUE
    mov rax, [rdi + SHELL_POPUPS]
    leave
    ret

; ============================================================================
; shell_get_layers
;   Get all layers
; ============================================================================
global shell_get_layers
shell_get_layers:
    PROLOGUE
    mov rax, [rdi + SHELL_LAYERS]
    leave
    ret

; ============================================================================
; shell_get_outputs
;   Get all outputs
; ============================================================================
global shell_get_outputs
shell_get_outputs:
    PROLOGUE
    mov rax, [rdi + SHELL_OUTPUTS]
    leave
    ret

section .data
global shell_version
shell_version: dq 0x010000