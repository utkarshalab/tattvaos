; Native surface input delivery. Events are fixed-size records placed directly
; on the owning client's receive ring, which is the format consumed by
; canvas_event_poll.

%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/event.inc"
%include "inc/struct_offsets.inc"

extern ring_push
extern tv_time_now_ns

%define SERVER_SURFACE_CLIENT 40
%define SERVER_SURFACE_ID      0
%define SERVER_CLIENT_RX_RING 48
%define SERVER_SURFACE_X      280
%define SERVER_SURFACE_Y      284
%define SERVER_SURFACE_WIDTH  288
%define SERVER_SURFACE_HEIGHT 292

section .text

; rdi=surface, esi=type, edx=a, ecx=b, r8d=c
surface_emit_event:
    test rdi, rdi
    jz .invalid
    mov rax, [rdi + SERVER_SURFACE_CLIENT]
    test rax, rax
    jz .ok
    mov rax, [rax + SERVER_CLIENT_RX_RING]
    test rax, rax
    jz .ok
    sub rsp, EVENT_SIZE + 8
    mov [rsp + Event.type], esi
    mov [rsp + Event.a], edx
    mov [rsp + Event.b], ecx
    mov [rsp + Event.c], r8d
    mov r9, rax
    call tv_time_now_ns
    mov [rsp + Event.time], rax
    mov rdi, r9
    mov rsi, rsp
    mov rdx, EVENT_SIZE
    call ring_push
    add rsp, EVENT_SIZE + 8
    ret
.ok:
    xor eax, eax
    ret
.invalid:
    mov rax, -EINVAL
    ret

global surface_pointer_enter
surface_pointer_enter:
    mov r8d, [rdi + SERVER_SURFACE_ID]
    xor edx, edx
    xor ecx, ecx
    mov esi, EVENT_POINTER_ENTER
    jmp surface_emit_event

global surface_pointer_leave
surface_pointer_leave:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov esi, EVENT_POINTER_LEAVE
    jmp surface_emit_event

global surface_pointer_motion
surface_pointer_motion:
    mov r8d, [rdi + SERVER_SURFACE_ID]
    mov ecx, edx
    mov edx, esi
    mov esi, EVENT_POINTER_MOTION
    jmp surface_emit_event

global surface_pointer_button
surface_pointer_button:
    mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    test ecx, ecx
    mov esi, EVENT_POINTER_BUTTON_RELEASE
    jz surface_emit_event
    mov esi, EVENT_POINTER_BUTTON_PRESS
    jmp surface_emit_event

global surface_pointer_axis
surface_pointer_axis:
    mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    mov esi, EVENT_POINTER_AXIS
    jmp surface_emit_event

global surface_keyboard_enter
surface_keyboard_enter:
    ; Focus transitions use the surface id as the payload and no key state.
    mov edx, [rdi + SERVER_SURFACE_ID]
    xor ecx, ecx
    xor r8d, r8d
    mov esi, EVENT_NONE
    jmp surface_emit_event

global surface_keyboard_leave
surface_keyboard_leave:
    mov edx, [rdi + SERVER_SURFACE_ID]
    xor ecx, ecx
    xor r8d, r8d
    mov esi, EVENT_NONE
    jmp surface_emit_event

global surface_keyboard_key
surface_keyboard_key:
    ; keycode, state, time, serial -> compact key event
    mov r9d, edx
    mov edx, esi
    mov ecx, r8d
    xor r8d, r8d
    cmp r9d, 0
    mov esi, EVENT_KEY_RELEASE
    je surface_emit_event
    cmp r9d, 2
    mov esi, EVENT_KEY_REPEAT
    je surface_emit_event
    mov esi, EVENT_KEY_PRESS
    jmp surface_emit_event

global surface_touch_down
surface_touch_down:
    mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    mov esi, EVENT_TOUCH_DOWN
    jmp surface_emit_event

global surface_touch_up
surface_touch_up:
    mov edx, esi
    xor ecx, ecx
    xor r8d, r8d
    mov esi, EVENT_TOUCH_UP
    jmp surface_emit_event

global surface_touch_motion
surface_touch_motion:
    mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    mov esi, EVENT_TOUCH_MOTION
    jmp surface_emit_event

global surface_touch_cancel
surface_touch_cancel:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov esi, EVENT_TOUCH_CANCEL
    jmp surface_emit_event

global surface_tablet_axis
surface_tablet_axis:
    mov ecx, edx
    mov edx, esi
    xor r8d, r8d
    mov esi, EVENT_TABLET_PAD_RING
    jmp surface_emit_event

global surface_tablet_proximity
surface_tablet_proximity:
    mov ecx, edx
    mov edx, esi
    xor r8d, r8d
    mov esi, EVENT_TABLET_TOOL_PROXIMITY
    jmp surface_emit_event

global surface_tablet_tip
surface_tablet_tip:
    mov ecx, edx
    mov edx, esi
    xor r8d, r8d
    mov esi, EVENT_TABLET_TOOL_TIP
    jmp surface_emit_event

global surface_tablet_button
surface_tablet_button:
    mov ecx, edx
    mov edx, esi
    xor r8d, r8d
    mov esi, EVENT_TABLET_TOOL_BUTTON
    jmp surface_emit_event

global surface_unset_pointer_focus
surface_unset_pointer_focus:
    jmp surface_pointer_leave

global surface_unset_touch_focus
surface_unset_touch_focus:
    jmp surface_touch_cancel

global surface_set_cursor
surface_set_cursor:
    test rdi, rdi
    jz .bad
    mov [rdi + Pointer.x], rsi
    mov [rdi + Pointer.y], rdx
    xor eax, eax
    ret
.bad:
    mov rax, -EINVAL
    ret

global surface_set_position
surface_set_position:
    test rdi, rdi
    jz .position_bad
    mov [rdi + SERVER_SURFACE_X], esi
    mov [rdi + SERVER_SURFACE_Y], edx
    xor eax, eax
    ret
.position_bad:
    mov rax, -EINVAL
    ret

global surface_set_size
surface_set_size:
    test rdi, rdi
    jz .size_bad
    test esi, esi
    jle .size_bad
    test edx, edx
    jle .size_bad
    mov [rdi + SERVER_SURFACE_WIDTH], esi
    mov [rdi + SERVER_SURFACE_HEIGHT], edx
    xor eax, eax
    ret
.size_bad:
    mov rax, -EINVAL
    ret

section .data
global surface_events_version
surface_events_version: dq 0x010000
