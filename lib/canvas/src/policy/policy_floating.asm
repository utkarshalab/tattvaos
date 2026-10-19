; ============================================================================
; Floating Policy — Default Stacking Window Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define PolicyFloating_SIZE    24

section .text

; PolicyFloating struct layout (manual offsets)
; Offsets defined in inc/struct_offsets.inc

; ----------


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
    mov r13,rax
    mov ecx,[r13 + Toplevel.width]
    mov edx,[r12 + Output.width]
    cmp ecx,edx
    jbe .width_ok
    mov ecx,edx
    mov [r13 + Toplevel.pending_width],ecx
.width_ok:
    mov r8d,[r13 + Toplevel.height]
    mov r9d,[r12 + Output.height]
    cmp r8d,r9d
    jbe .height_ok
    mov r8d,r9d
    mov [r13 + Toplevel.pending_height],r8d
.height_ok:
    mov esi,[r13 + Toplevel.x]
    mov edx,[r13 + Toplevel.y]
    mov r10d,[r12 + Output.x]
    mov r11d,[r12 + Output.y]
    cmp esi,r10d
    cmovl esi,r10d
    cmp edx,r11d
    cmovl edx,r11d
    mov eax,[r12 + Output.x]
    add eax,[r12 + Output.width]
    sub eax,ecx
    cmp esi,eax
    cmovg esi,eax
    mov eax,[r12 + Output.y]
    add eax,[r12 + Output.height]
    sub eax,r8d
    cmp edx,eax
    cmovg edx,eax
    mov rdi,r13
    call toplevel_set_position
    mov rax,[r13 + Toplevel.next_ws]
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

    test r12,r12
    jz .done
    mov rdi,[rbx + PolicyFloating.server]
    mov rsi,[r12 + Toplevel.surface]
    test rdi,rdi
    jz .done
    test rsi,rsi
    jz .done
    call zorder_top
.done:
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
    mov r13,[r13 + Seat.pointer]
    test r13,r13
    jz .center
    mov esi,[r13 + Pointer.x]
    mov edx,[r13 + Pointer.y]
    mov rdi,r12
    call toplevel_set_position
    xor eax,eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.center:
    mov rax,[r12 + Toplevel.output]
    test rax,rax
    jz .done
    mov esi,[rax + Output.width]
    sub esi,[r12 + Toplevel.width]
    sar esi,1
    add esi,[rax + Output.x]
    mov edx,[rax + Output.height]
    sub edx,[r12 + Toplevel.height]
    sar edx,1
    add edx,[rax + Output.y]
    mov rdi,r12
    call toplevel_set_position
.done:
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
