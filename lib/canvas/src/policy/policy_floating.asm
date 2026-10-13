; ============================================================================
; Floating Policy — Default Stacking Window Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define PolicyFloating_size    24

section .text

struc PolicyFloating
    .base:              resq 1
    .server:            resq 1
    .data:              resq 1
endstruc

; ---------------------------------------------------------------------------
; policy_floating_init
;   Initialize floating policy
; ---------------------------------------------------------------------------
global policy_floating_init
policy_floating_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + PolicyFloating.base], rdi
    mov qword [rbx + PolicyFloating.server], r12
    mov qword [rbx + PolicyFloating.data], 0

    ; Set function pointers
    mov qword [rdi + Policy.layout], policy_floating_layout
    mov qword [rdi + Policy.configure], policy_floating_configure
    mov qword [rdi + Policy.focus_change], policy_floating_focus_change
    mov qword [rdi + Policy.new_window], policy_floating_new_window
    mov qword [rdi + Policy.close_window], policy_floating_close_window
    mov qword [rdi + Policy.workspace_changed], policy_floating_workspace_changed
    mov qword [rdi + Policy.tile_window], policy_floating_tile_window
    mov qword [rdi + Policy.window_configured], policy_floating_window_configured

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_floating_layout
;   Floating layout: windows stack by focus order, user positions them
; ---------------------------------------------------------------------------
global policy_floating_layout
policy_floating_layout:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Floating policy: windows keep their user-assigned positions
    ; Just ensure they're within output bounds
    mov rax, [r12 + Output.toplevels]
    test rax, rax
    jz .done

.layout_loop:
    ; Check if window is within output bounds
    ; TODO: Clamp to output
    mov rax, [rax + Toplevel.next_ws]
    test rax, rax
    jnz .layout_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_floating_configure
;   Handle configure request - floating allows any geometry
; ---------------------------------------------------------------------------
global policy_floating_configure
policy_floating_configure:
    PROLOGUE
    ; Floating allows any configure
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_floating_focus_change
; ---------------------------------------------------------------------------
global policy_floating_focus_change
policy_floating_focus_change:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Raise focused window
    ; TODO: Update z-order

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; policy_floating_new_window
;   Place new window at cursor or center
; ---------------------------------------------------------------------------
global policy_floating_new_window
policy_floating_new_window:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get default seat
    mov r13, [rbx + Server.default_seat]
    test r13, r13
    jz .center

    ; Place at cursor
    mov r13, [r13 + Seat.pointer]
    mov eax, [r13 + Pointer.x]
    mov [r12 + Toplevel.pending_width], eax
    mov eax, [r13 + Pointer.y]
    mov [r12 + Toplevel.pending_height], eax
    mov byte [r12 + Toplevel.pending_state], 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.center:
    ; Center on output
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; policy_floating_close_window
; ---------------------------------------------------------------------------
global policy_floating_close_window
policy_floating_close_window:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_floating_workspace_changed
; ---------------------------------------------------------------------------
global policy_floating_workspace_changed
policy_floating_workspace_changed:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; policy_floating_tile_window
;   Floating policy doesn't tile
; ---------------------------------------------------------------------------
global policy_floating_tile_window
policy_floating_tile_window:
    PROLOGUE
    mov rax, -(ENOTSUP)
    leave
    ret

; ---------------------------------------------------------------------------
; policy_floating_window_configured
; ---------------------------------------------------------------------------
global policy_floating_window_configured
policy_floating_window_configured:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
global policy_floating_version
policy_floating_version: dq 0x010000
