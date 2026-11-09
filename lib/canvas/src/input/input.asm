; ============================================================================
; Input — From Raw Events to the Focused Surface
; ============================================================================
; Every source, the kernel's drivers or virtual injection, hands raw records
; (RawInput, the INPUT_* types in inc/event.inc) to input_submit, which queues
; them on the active seat. server_poll calls input_dispatch once a turn, which
; drains the queue:
;
;   touch    (TCH-01) a finger goes to the surface it went down on, which a
;            tap focuses; each scan ends with frame to the surfaces in it
;   pen      (TCH-10) with the surface under it, the one it touched while its
;            tip is down; proximity, motion, axes, tip and barrel buttons
;   sticky   (A11Y-04) a modifier tapped alone latches for the next key, twice
;            locks, a third time is off; five Shift taps turn them on or off
;   keys     go to the surface with keyboard focus, and one that is not a
;            modifier or a lock hides the pointer until it moves; a held key
;            that is not a
;            modifier or a lock repeats, checked at the end of each turn
;            (input_repeat_deadline says when the loop must wake for it)
;   pointer  moves across every output; the topmost surface under it gets
;            enter, leave, motion, button and axis events in its own
;            coordinates. While a button is held that surface keeps the
;            pointer, so a drag stays with its window.
;   a press  on a surface raises it and, unless it is a background, bottom
;            or top layer, gives it the keyboard focus
;   Alt+F4   asks the focused window's client to close it; Super+Up
;            maximizes it or puts it back, Super+Down minimizes it;
;            Super+Shift+H turns high contrast on or off and Super+Shift+M
;            the magnifier through 2x, 4x and off, on the login screen too;
;            Super+1 to 4 shows a workspace, Super+Shift+1 to 4 moves the
;            focused window there; Super+L locks; Alt+Tab switches windows
;            (shell/switcher), Esc giving up and letting go of Alt choosing.
;            While the login screen is up (Server.locked) none of these does
;            anything
;   Alt+drag moves the window under the pointer, Alt+right-drag resizes it
;            (configure with the new size); its client sees none of the drag
;   a press  on anything but a popup ends every popup (an Alt+drag does not)
;   a drag   (data/dnd) while it lasts has the motion, and the last button let
;            go drops it
;   a bar    a server-drawn title bar (shell/titlebar) is not its window's
;            for the client: a press on a button acts, elsewhere on the bar
;            starts a move
;
; Server.input_seat is the one place input is routed from. input_set_seat
; switches it, first releasing every key and button the old seat holds, so
; nothing is left stuck: that is the hook a KVM switch needs.
;
; Events reach clients as cw_keyboard and cw_pointer events
; (proto/canvas-input.cwp), each payload (time: ulong, surface: handle) and,
; for most, two more 32-bit values; only to a client that asked for that
; kind (CAP_POINTER, CAP_KEYBOARD, CAP_TOUCH), and the keyboard focus never
; goes to one without CAP_KEYBOARD, so it cannot read what is typed.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/caps.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern compositor_raise_surface
extern compositor_layout_bounds
extern sw_cursor_moved
extern sw_cursor_hide
extern clipboard_focus_changed
extern dnd_active
extern dnd_over
extern dnd_release
extern dnd_forget_surface
extern keymap_mods
extern keymap_modifier
extern surface_logical_size
extern server_set_high_contrast
extern server_set_magnifier
extern magnify_moved
extern magnify_focus
extern umath_bezier_cubic_eval
extern gesture_touch
extern server_wake
extern handle_resolve
extern keymap_key
extern msgbuf_write
extern region_contains_point
extern stacking_level
extern titlebar_part
extern titlebar_focus_changed
extern window_close
extern window_configure
extern window_dismiss_popups
extern window_list_activated
extern greeter_lock
extern seat_tell_switch
extern seat_tell_device
extern clamshell_lid
extern clamshell_sleep
extern switcher_cancel
extern switcher_finish
extern switcher_next
extern switcher_selected
extern window_maximize
extern window_minimize
extern window_move_to_workspace
extern window_switch_workspace
extern window_move

; cw_keyboard and cw_pointer events: interface << 16 | event index
%define KEYBOARD_ENTER  (CWP_OBJ_KEYBOARD << 16 | 0)
%define KEYBOARD_LEAVE  (CWP_OBJ_KEYBOARD << 16 | 1)
%define KEYBOARD_KEY    (CWP_OBJ_KEYBOARD << 16 | 2)
%define KEYBOARD_MODIFIERS (CWP_OBJ_KEYBOARD << 16 | 3)
%define KEYBOARD_TEXT   (CWP_OBJ_KEYBOARD << 16 | 4)
%define POINTER_ENTER   (CWP_OBJ_POINTER << 16 | 0)
%define POINTER_LEAVE   (CWP_OBJ_POINTER << 16 | 1)
%define POINTER_MOTION  (CWP_OBJ_POINTER << 16 | 2)
%define POINTER_BUTTON  (CWP_OBJ_POINTER << 16 | 3)
%define POINTER_AXIS    (CWP_OBJ_POINTER << 16 | 4)

%define KEY_REPEATED    2               ; cw_keyboard.key state of a repeat

; A held key repeats after half a second, 30 times a second
%define REPEAT_DELAY_NS     500000000
%define REPEAT_INTERVAL_NS  33333333

; Keys that do not repeat (evdev numbering)
%define KEY_LEFTCTRL    29
%define KEY_LEFTSHIFT   42
%define KEY_RIGHTSHIFT  54
%define KEY_LEFTALT     56
%define KEY_CAPSLOCK    58
%define KEY_NUMLOCK     69
%define KEY_SCROLLLOCK  70
%define KEY_RIGHTCTRL   97
%define KEY_RIGHTALT    100
%define KEY_LEFTMETA    125
%define KEY_RIGHTMETA   126
%define KEY_F4          62
%define KEY_UP          103
%define KEY_1           2               ; 1 to 4 are 2 to 5
%define KEY_L           38
%define KEY_H           35
%define KEY_M           50
%define KEY_TAB         15
%define KEY_ESC         1
%define KEY_DOWN        108

%define EVENT_SHORT     12              ; time, surface
%define EVENT_LONG      20              ; time, surface, a, b

section .text

; ---------------------------------------------------------------------------
; input_init
;   Create the seat and make it the active one; listen to the kernel's drivers
;   when it has them (virtual input works without)
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK, -ENOMEM
; ---------------------------------------------------------------------------
global input_init
input_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov esi, InputSeat_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, InputSeat_size
    rep stosb
    mov [r12 + InputSeat.server], rbx

    ; The pointer starts in the middle of the first output
    mov rax, [rbx + Server.outputs]
    test rax, rax
    jz .placed
    mov ecx, [rax + Output.width]
    shr ecx, 1
    mov [r12 + InputSeat.x], ecx
    mov ecx, [rax + Output.height]
    shr ecx, 1
    mov [r12 + InputSeat.y], ecx
.placed:
    mov qword [r12 + InputSeat.repeat_delay], REPEAT_DELAY_NS
    mov qword [r12 + InputSeat.repeat_interval], REPEAT_INTERVAL_NS
    mov [rbx + Server.input_seat], r12

    lea rdi, [rel input_kernel_event]
    mov rsi, rbx
    call ut_input_register_callback     ; a kernel without input is not an error
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; input_deinit
;   Stop listening to the kernel's drivers
; ---------------------------------------------------------------------------
global input_deinit
input_deinit:
    PROLOGUE
    call ut_input_unregister_callback
    xor eax, eax
    EPILOGUE

; The kernel's callback: rdi = RawInput*, rsi = the server given at registration
input_kernel_event:
    xchg rdi, rsi
    jmp input_submit

; ---------------------------------------------------------------------------
; input_submit
;   Queue one raw event on the active seat; it is copied, and delivered on
;   the next turn
;   IN:  rdi = server*, rsi = RawInput* (time 0: stamped now)
;   OUT: rax = 0, -ENODEV with no seat, -ENOSPC when the queue is full
; ---------------------------------------------------------------------------
global input_submit
input_submit:
    PROLOGUE_SAVE rbx, r12
    mov r12, rsi
    mov rbx, [rdi + Server.input_seat]
    mov rax, -(ENODEV)
    test rbx, rbx
    jz .out
    mov eax, [rbx + InputSeat.tail]
    sub eax, [rbx + InputSeat.head]
    cmp eax, INPUT_QUEUE_LEN
    jae .full

    mov rax, [r12 + RawInput.time]
    test rax, rax
    jnz .stamped
    call ut_time_now_ns
.stamped:
    mov ecx, [rbx + InputSeat.tail]
    and ecx, INPUT_QUEUE_LEN - 1
    imul ecx, ecx, RawInput_size
    lea rdi, [rbx + InputSeat.queue + rcx]
    mov [rdi + RawInput.time], rax
    mov eax, [r12 + RawInput.type]
    mov [rdi + RawInput.type], eax
    mov eax, [r12 + RawInput.code]
    mov [rdi + RawInput.code], eax
    mov eax, [r12 + RawInput.value]
    mov [rdi + RawInput.value], eax
    mov eax, [r12 + RawInput.device]
    mov [rdi + RawInput.device], eax
    inc dword [rbx + InputSeat.tail]
    mov rdi, [rbx + InputSeat.server]   ; the loop woken to deliver it
    call server_wake
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
.full:
    inc dword [rbx + InputSeat.dropped]
    mov rax, -(ENOSPC)
    jmp .out

; ---------------------------------------------------------------------------
; input_dispatch
;   Deliver every queued event of the active seat
;   IN:  rdi = server*
;   OUT: rax = events taken off the queue
; ---------------------------------------------------------------------------
global input_dispatch
input_dispatch:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8
    mov rbx, [rdi + Server.input_seat]
    xor r13d, r13d
    test rbx, rbx
    jz .done
.next:
    mov eax, [rbx + InputSeat.head]
    cmp eax, [rbx + InputSeat.tail]
    je .queued
    and eax, INPUT_QUEUE_LEN - 1
    imul eax, eax, RawInput_size
    lea r12, [rbx + InputSeat.queue + rax]
    mov rax, [r12 + RawInput.time]
    mov [rbx + InputSeat.time], rax

    mov rdi, rbx
    mov rsi, r12
    mov eax, [r12 + RawInput.type]
    cmp eax, INPUT_KEY
    je .key
    cmp eax, INPUT_MOTION
    je .pointer
    cmp eax, INPUT_POSITION
    je .pointer
    cmp eax, INPUT_BUTTON
    je .button
    cmp eax, INPUT_AXIS
    je .axis
    cmp eax, INPUT_TOUCH
    je .touch
    cmp eax, INPUT_PEN
    je .pen
    cmp eax, INPUT_PEN_AXES
    je .pen_axes
    cmp eax, INPUT_SWITCH
    je .switch
    cmp eax, INPUT_DEVICE
    je .device
    cmp eax, INPUT_PAD
    je .pad
    jmp .handled                        ; an unknown type is dropped
.switch:
    call switch_event
    jmp .handled
.device:
    call device_event
    jmp .handled
.pad:
    call pad_event
    jmp .handled
.touch:
    call touch_event
    jmp .handled
.pen:
    call pen_event
    jmp .handled
.pen_axes:
    call pen_axes_event
    jmp .handled
.key:
    call key_event
    jmp .handled
.pointer:
    call pointer_event
    jmp .handled
.button:
    call button_event
    jmp .handled
.axis:
    call axis_event
.handled:
    inc dword [rbx + InputSeat.head]    ; only now may input_submit reuse it
    inc r13
    jmp .next
.queued:
    mov rdi, rbx
    call key_repeat
.done:
    mov rax, r13
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; input_set_repeat
;   How a held key repeats on the active seat
;   IN:  rdi = server*, rsi = delay before the first repeat, ns,
;        rdx = interval between repeats, ns (0: keys do not repeat)
;   OUT: rax = 0, -ENODEV with no seat
; ---------------------------------------------------------------------------
global input_set_repeat
input_set_repeat:
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .none
    mov [rax + InputSeat.repeat_delay], rsi
    mov [rax + InputSeat.repeat_interval], rdx
    mov dword [rax + InputSeat.repeat_key], 0
    xor eax, eax
    ret
.none:
    mov rax, -(ENODEV)
    ret

; ---------------------------------------------------------------------------
; input_repeat_deadline
;   When a held key repeats next, for the event loop to wake by
;   IN:  rdi = server*
;   OUT: rax = monotonic ns, 0 if nothing is repeating
; ---------------------------------------------------------------------------
global input_repeat_deadline
input_repeat_deadline:
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .none
    cmp dword [rax + InputSeat.repeat_key], 0
    je .none
    mov rax, [rax + InputSeat.repeat_next]
    ret
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; input_set_seat
;   Make another seat the active one. The old seat releases every key and
;   button it holds and drops what it has queued.
;   IN:  rdi = server*, rsi = InputSeat* (0: none)
;   OUT: rax = the seat that was active
; ---------------------------------------------------------------------------
global input_set_seat
input_set_seat:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + Server.input_seat]
    test r13, r13
    jz .switch
    cmp r13, r12
    je .switch
    mov rdi, r13
    call input_release_all
    mov eax, [r13 + InputSeat.tail]
    mov [r13 + InputSeat.head], eax
.switch:
    mov [rbx + Server.input_seat], r12
    mov rax, r13
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; input_release_all
;   Release every held key and button: each focused surface is told, as if
;   the user had let go
;   IN:  rdi = InputSeat*
; ---------------------------------------------------------------------------
global input_release_all
input_release_all:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov dword [rbx + InputSeat.repeat_key], 0
    mov qword [rbx + InputSeat.moving], 0
    call ut_time_now_ns
    mov [rbx + InputSeat.time], rax

    xor r12d, r12d                      ; keycode
.key:
    mov eax, r12d
    shr eax, 3
    movzx eax, byte [rbx + InputSeat.keys + rax]
    mov ecx, r12d
    and ecx, 7
    bt eax, ecx
    jnc .next_key
    mov rsi, [rbx + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .next_key
    mov rdi, rbx
    mov edx, KEYBOARD_KEY
    mov ecx, EVENT_LONG
    mov r8d, r12d
    xor r9d, r9d
    call send_input
.next_key:
    inc r12d
    cmp r12d, 256
    jb .key
    lea rdi, [rbx + InputSeat.keys]
    xor eax, eax
    mov ecx, 32
    rep stosb
    cmp dword [rbx + InputSeat.mods], 0
    je .buttons                         ; no modifier was held
    mov dword [rbx + InputSeat.mods], 0
    mov rsi, [rbx + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .buttons
    mov rdi, rbx
    call send_modifiers
.buttons:

    xor r12d, r12d                      ; button
.button:
    mov eax, [rbx + InputSeat.buttons]
    bt eax, r12d
    jnc .next_button
    mov rsi, [rbx + InputSeat.pointer_focus]
    test rsi, rsi
    jz .next_button
    mov rdi, rbx
    mov edx, POINTER_BUTTON
    mov ecx, EVENT_LONG
    mov r8d, r12d
    xor r9d, r9d
    call send_input
.next_button:
    inc r12d
    cmp r12d, 32
    jb .button
    mov dword [rbx + InputSeat.buttons], 0
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; input_focus_surface
;   Give a surface the keyboard focus, as the shell does for a new window
;   IN:  rdi = server*, rsi = surface* (0: no surface has it)
;   OUT: rax = 0, -ENODEV with no seat
; ---------------------------------------------------------------------------
global input_focus_surface
input_focus_surface:
    PROLOGUE_SAVE rbx, r12
    mov rbx, [rdi + Server.input_seat]
    mov r12, rsi
    mov rax, -(ENODEV)
    test rbx, rbx
    jz .out
    call ut_time_now_ns
    mov [rbx + InputSeat.time], rax
    mov rdi, rbx
    mov rsi, r12
    call set_keyboard_focus
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; input_keep_pointer
;   The pointer back inside what the outputs span, after one went
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global input_keep_pointer
input_keep_pointer:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, [rdi + Server.input_seat]
    test rbx, rbx
    jz .done
    cmp qword [rdi + Server.outputs], 0
    je .done
    call compositor_layout_bounds
    dec ecx                             ; the last column and row
    dec r8d
    mov r9d, [rbx + InputSeat.x]
    cmp r9d, eax
    cmovl r9d, eax
    cmp r9d, ecx
    cmovg r9d, ecx
    mov [rbx + InputSeat.x], r9d
    mov r9d, [rbx + InputSeat.y]
    cmp r9d, edx
    cmovl r9d, edx
    cmp r9d, r8d
    cmovg r9d, r8d
    mov [rbx + InputSeat.y], r9d
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; input_forget_surface
;   A surface is going: it stops holding any focus. It gets no events; its
;   client destroyed it.
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global input_forget_surface
input_forget_surface:
    mov rax, [rdi + Server.input_seat]  ; one seat until there are more
    test rax, rax
    jz .done
    cmp [rax + InputSeat.pointer_focus], rsi
    jne .keyboard
    mov qword [rax + InputSeat.pointer_focus], 0
.keyboard:
    cmp [rax + InputSeat.keyboard_focus], rsi
    jne .move
    mov qword [rax + InputSeat.keyboard_focus], 0
.move:
    cmp [rax + InputSeat.moving], rsi
    jne .touch
    mov qword [rax + InputSeat.moving], 0
.touch:
    xor ecx, ecx                        ; no finger on it, no pen with it
.contact:
    imul edx, ecx, TouchContact_size
    cmp [rax + InputSeat.touches + rdx + TouchContact.surface], rsi
    jne .next_contact
    mov qword [rax + InputSeat.touches + rdx + TouchContact.surface], 0
.next_contact:
    cmp [rax + InputSeat.scan + rcx * 8], rsi
    jne .scanned
    mov qword [rax + InputSeat.scan + rcx * 8], 0
.scanned:
    inc ecx
    cmp ecx, TOUCH_SLOTS
    jb .contact
    cmp [rax + InputSeat.pen_surface], rsi
    jne .gesture
    mov qword [rax + InputSeat.pen_surface], 0
.gesture:
    cmp [rax + InputSeat.tp_surface], rsi   ; no touchpad gesture to it
    jne .done
    mov qword [rax + InputSeat.tp_surface], 0
.done:
    jmp dnd_forget_surface              ; and no drag holds it

; ---------------------------------------------------------------------------
; Delivery: rdi = seat, rsi = RawInput*
; ---------------------------------------------------------------------------

; A key goes to the keyboard focus. The seat keeps which keys are down, so a
; release of a key that is not down is dropped and input_release_all knows
; what to let go of. After the key come the modifiers, if they changed, and
; the character it types, if any (keymap_us.asm).
key_event:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov ecx, [r12 + RawInput.code]
    cmp ecx, 255
    ja .out                             ; no such keycode
    mov edx, ecx
    shr edx, 3
    and ecx, 7
    mov r8d, 1
    shl r8d, cl
    movzx eax, byte [rbx + InputSeat.keys + rdx]
    cmp dword [r12 + RawInput.value], 0
    je .up
    or eax, r8d
    jmp .mark
.up:
    test eax, r8d
    jz .out
    not r8d
    and eax, r8d
.mark:
    mov [rbx + InputSeat.keys + rdx], al
    mov rdi, rbx                        ; sticky keys keep their books
    mov rsi, r12
    call sticky_key

    ; A press of a key that repeats starts it repeating; letting go of the
    ; repeating key stops it. Modifiers and locks do not repeat.
    mov ecx, [r12 + RawInput.code]
    cmp dword [r12 + RawInput.value], 0
    jne .press
    cmp ecx, [rbx + InputSeat.repeat_key]
    jne .keymap
    mov dword [rbx + InputSeat.repeat_key], 0
    jmp .keymap
.press:
    cmp qword [rbx + InputSeat.repeat_interval], 0
    je .keymap
    mov edi, ecx
    call key_repeats
    test eax, eax
    jz .keymap
    mov ecx, [r12 + RawInput.code]
    mov [rbx + InputSeat.repeat_key], ecx
    mov rax, [rbx + InputSeat.time]
    add rax, [rbx + InputSeat.repeat_delay]
    mov [rbx + InputSeat.repeat_next], rax
.keymap:
    mov rdi, rbx
    mov esi, [r12 + RawInput.code]
    xor edx, edx
    cmp dword [r12 + RawInput.value], 0
    setne dl
    call keymap_key
    mov r13d, eax                       ; the character, 0: none
    mov r14d, ecx                       ; 1: modifiers changed

    ; A shortcut is the server's: the window's client gets neither the press
    ; nor its release, and it does not repeat
    cmp dword [r12 + RawInput.value], 0
    je .route
    mov rdi, rbx
    mov esi, [r12 + RawInput.code]
    call shortcut
    test eax, eax
    jz .route
    mov ecx, [r12 + RawInput.code]
    mov edx, ecx
    shr edx, 3
    and ecx, 7
    mov al, 1
    shl al, cl
    not al
    and [rbx + InputSeat.keys + rdx], al
    mov ecx, [r12 + RawInput.code]
    cmp [rbx + InputSeat.repeat_key], ecx
    jne .out
    mov dword [rbx + InputSeat.repeat_key], 0
    jmp .out
.route:
    cmp dword [r12 + RawInput.value], 0  ; Alt let go: an Alt+Tab chooses
    jne .routed
    mov eax, [r12 + RawInput.code]
    cmp eax, KEY_LEFTALT
    je .alt_up
    cmp eax, KEY_RIGHTALT
    jne .routed
.alt_up:
    mov rdi, [rbx + InputSeat.server]
    call switcher_finish
.routed:
    cmp dword [r12 + RawInput.value], 0 ; typing hides the pointer: a press,
    je .shown                           ; not the server's, not a modifier
    mov edi, [r12 + RawInput.code]
    call key_repeats
    test eax, eax
    jz .shown
    mov rdi, [rbx + InputSeat.server]
    call sw_cursor_hide
.shown:
    mov rsi, [rbx + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .out
    mov rdi, rbx
    mov edx, KEYBOARD_KEY
    mov ecx, EVENT_LONG
    mov r8d, [r12 + RawInput.code]
    xor r9d, r9d
    cmp dword [r12 + RawInput.value], 0
    setne r9b
    call send_input
    test r14d, r14d
    jz .text
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.keyboard_focus]
    call send_modifiers
.text:
    test r13d, r13d
    jz .out
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.keyboard_focus]
    mov edx, KEYBOARD_TEXT
    mov ecx, EVENT_LONG
    mov r8d, r13d
    mov r9d, [rbx + InputSeat.mods]
    or r9d, [rbx + InputSeat.locks]
    call send_input
.out:
    cmp dword [rbx + InputSeat.sticky_clear], 0
    je .exit                            ; the key a latch was for: it goes
    mov rdi, rbx
    call sticky_unlatch
.exit:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; The held key again, if it is time: a key event with state 2 and the
; character it types, as a press would. One repeat a turn; a loop that fell
; behind does not catch up in a burst.
; rdi = seat
key_repeat:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, [rbx + InputSeat.repeat_key]
    test r12d, r12d
    jz .out
    cmp qword [rbx + InputSeat.keyboard_focus], 0
    je .stop
    call ut_time_now_ns
    cmp rax, [rbx + InputSeat.repeat_next]
    jb .out
    mov [rbx + InputSeat.time], rax
    mov rcx, [rbx + InputSeat.repeat_next]
    add rcx, [rbx + InputSeat.repeat_interval]
    cmp rcx, rax
    ja .next_set
    mov rcx, rax
    add rcx, [rbx + InputSeat.repeat_interval]
.next_set:
    mov [rbx + InputSeat.repeat_next], rcx
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.keyboard_focus]
    mov edx, KEYBOARD_KEY
    mov ecx, EVENT_LONG
    mov r8d, r12d
    mov r9d, KEY_REPEATED
    call send_input
    mov rdi, rbx
    mov esi, r12d
    mov edx, 1
    call keymap_key
    test eax, eax
    jz .out
    mov r8d, eax
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.keyboard_focus]
    mov edx, KEYBOARD_TEXT
    mov ecx, EVENT_LONG
    mov r9d, [rbx + InputSeat.mods]
    or r9d, [rbx + InputSeat.locks]
    call send_input
.out:
    EPILOGUE_RESTORE rbx, r12
.stop:
    mov dword [rbx + InputSeat.repeat_key], 0
    jmp .out

; ---------------------------------------------------------------------------
; Touch and pen (TCH-01, TCH-10): records 6, 7 and 8 (KERNEL_NEEDS.md step 3)
; ---------------------------------------------------------------------------

%define TOUCH_DOWN      (CWP_OBJ_TOUCH << 16 | TOUCH_EV_DOWN)
%define TOUCH_MOTION    (CWP_OBJ_TOUCH << 16 | TOUCH_EV_MOTION)
%define TOUCH_UP        (CWP_OBJ_TOUCH << 16 | TOUCH_EV_UP)
%define TOUCH_CANCEL    (CWP_OBJ_TOUCH << 16 | TOUCH_EV_CANCEL)
%define TOUCH_FRAME     (CWP_OBJ_TOUCH << 16 | TOUCH_EV_FRAME)
%define PEN_IN          (CWP_OBJ_TABLET_TOOL << 16 | TABLET_TOOL_EV_PROXIMITY_IN)
%define PEN_OUT         (CWP_OBJ_TABLET_TOOL << 16 | TABLET_TOOL_EV_PROXIMITY_OUT)
%define PEN_MOTION      (CWP_OBJ_TABLET_TOOL << 16 | TABLET_TOOL_EV_MOTION)
%define PEN_AXES        (CWP_OBJ_TABLET_TOOL << 16 | TABLET_TOOL_EV_AXES)
%define PEN_TIP         (CWP_OBJ_TABLET_TOOL << 16 | TABLET_TOOL_EV_TIP)
%define PEN_BUTTON      (CWP_OBJ_TABLET_TOOL << 16 | TABLET_TOOL_EV_BUTTON)
%define PAD_BUTTON      (CWP_OBJ_TABLET_PAD << 16 | TABLET_PAD_EV_BUTTON)
%define PAD_RING        (CWP_OBJ_TABLET_PAD << 16 | TABLET_PAD_EV_RING)
%define PAD_STRIP       (CWP_OBJ_TABLET_PAD << 16 | TABLET_PAD_EV_STRIP)
%define DEV_POINTER     2               ; InputDevInfo.caps
%define DEV_TOUCH       4
%define PHASE_DOWN      0
%define PHASE_MOVE      1
%define PHASE_UP        2
%define PHASE_FRAME     3
%define PHASE_CANCEL    4
%define PEN_IN_RANGE    1
%define PEN_TIP_DOWN    2
%define PEN_BUTTON_1    8
%define PEN_BUTTON_2    16

; (input_device_point for input/gestures)
; rdi = seat, esi = device, edx = value (x | y << 16, device units) ->
; eax = x, edx = y in the layout: on the first output, scaled by the
; device's range when ut_input_device_info gives it, else taken as pixels
global input_device_point
input_device_point:
device_point:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    movzx r12d, dx                      ; x
    shr edx, 16
    mov r13d, edx                       ; y
    mov edi, esi
    call ut_input_device_info
    mov rcx, [rbx + InputSeat.server]
    mov rcx, [rcx + Server.outputs]
    test rcx, rcx
    jz .raw
    test rax, rax
    jle .on_output                      ; no range: pixels
    mov r8d, [rax + 40]                 ; InputDevInfo.max_x, max_y
    mov r9d, [rax + 44]
    test r8d, r8d
    jz .on_output
    test r9d, r9d
    jz .on_output
    mov eax, r12d                       ; x * width / (max_x + 1)
    mul dword [rcx + Output.width]
    inc r8d
    div r8d
    mov r12d, eax
    mov eax, r13d
    mul dword [rcx + Output.height]
    inc r9d
    div r9d
    mov r13d, eax
.on_output:
    add r12d, [rcx + Output.x]
    add r13d, [rcx + Output.y]
.raw:
    mov eax, r12d
    mov edx, r13d
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; rdi = seat, esi = x, edx = y in the layout -> rax = the topmost surface
; there for a finger or a pen, 0 for none (as the pointer would find it; the
; pointer's own place and title bar are kept)
surface_at_point:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12d, [rbx + InputSeat.x]
    mov r13d, [rbx + InputSeat.y]
    mov rax, [rbx + InputSeat.bar]
    mov [rsp], rax
    mov [rbx + InputSeat.x], esi
    mov [rbx + InputSeat.y], edx
    call surface_at
    mov [rbx + InputSeat.x], r12d
    mov [rbx + InputSeat.y], r13d
    mov rcx, [rsp]
    mov [rbx + InputSeat.bar], rcx
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; rdi = surface, esi = x, edx = y in the layout -> eax = x | y << 16 in the
; surface's own pixels, each 16 bits
local_xy:
    sub esi, [rdi + Surface.current + SurfaceState.buf_x]
    sub edx, [rdi + Surface.current + SurfaceState.buf_y]
    movzx eax, si
    shl edx, 16
    or eax, edx
    ret

; rdi = seat, rsi = surface: a tap on it, as a click: raised, and the
; keyboard unless it is a panel
tap_focus:
    push rbx
    sub rsp, 16                         ; the pointer's own; 16-byte aligned
    mov rbx, rdi
    mov rax, [rbx + InputSeat.pointer_focus]
    mov [rsp], rax
    mov [rbx + InputSeat.pointer_focus], rsi
    call click_focus
    mov rax, [rsp]
    mov [rbx + InputSeat.pointer_focus], rax
    add rsp, 16
    pop rbx
    ret

; rdi = seat, rsi = surface: on the scan's list, once
scan_add:
    xor ecx, ecx
    mov r8d, -1
.look:
    cmp ecx, [rdi + InputSeat.scan_count]
    jae .add
    cmp [rdi + InputSeat.scan + rcx * 8], rsi
    je .out
    inc ecx
    jmp .look
.add:
    cmp ecx, TOUCH_SLOTS
    jae .out
    mov [rdi + InputSeat.scan + rcx * 8], rsi
    inc dword [rdi + InputSeat.scan_count]
.out:
    ret

; Type 6: a finger down goes to the surface under it, which then has it,
; moves and up or cancel too, until it is lifted; a frame end tells each
; surface that heard of the scan. rdi = seat, rsi = RawInput*
touch_event:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov edi, [r12 + RawInput.device]    ; a touchpad's: gestures, not the
    call ut_input_device_info           ; screen
    test rax, rax
    jle .screen
    mov rax, [rax + 32]                 ; InputDevInfo.caps
    and eax, DEV_POINTER | DEV_TOUCH
    cmp eax, DEV_POINTER | DEV_TOUCH
    jne .screen
    mov rdi, rbx
    mov rsi, r12
    call gesture_touch
    jmp .out
.screen:
    mov eax, [r12 + RawInput.code]
    shr eax, 8
    and eax, 0xF
    mov r15d, eax                       ; the phase
    cmp r15d, PHASE_FRAME
    je .frame
    mov r14d, [r12 + RawInput.device]   ; its key: device, slot
    shl r14d, 8
    movzx eax, byte [r12 + RawInput.code]
    or r14d, eax
    xor r13d, r13d                      ; its entry, if it has one
.find:
    imul eax, r13d, TouchContact_size
    lea rcx, [rbx + InputSeat.touches + rax]
    cmp qword [rcx + TouchContact.surface], 0
    je .other
    cmp [rcx + TouchContact.key], r14d
    je .found
.other:
    inc r13d
    cmp r13d, TOUCH_SLOTS
    jb .find
    xor ecx, ecx                        ; none
.found:
    mov r13, rcx
    cmp r15d, PHASE_DOWN
    je .down
    test r13, r13
    jz .out                             ; nothing of it down
    cmp r15d, PHASE_MOVE
    je .move
    cmp r15d, PHASE_UP
    je .up
    cmp r15d, PHASE_CANCEL
    jne .out
    mov edx, TOUCH_CANCEL
    jmp .lifted
.up:
    mov edx, TOUCH_UP
.lifted:
    mov rsi, [r13 + TouchContact.surface]
    mov qword [r13 + TouchContact.surface], 0   ; the slot is free
    push rsi
    push rdx
    mov rdi, rbx
    call scan_add
    pop rdx
    pop rsi
    mov rdi, rbx
    mov ecx, EVENT_LONG
    movzx r8d, byte [r12 + RawInput.code]
    xor r9d, r9d
    call send_input
    jmp .out
.move:
    mov rdi, rbx
    mov esi, [r12 + RawInput.device]
    mov edx, [r12 + RawInput.value]
    call device_point
    mov rdi, [r13 + TouchContact.surface]
    mov esi, eax
    call local_xy
    mov r9d, eax
    mov rsi, [r13 + TouchContact.surface]
    mov rdi, rbx
    push r9
    push rsi
    call scan_add
    pop rsi
    pop r9
    mov rdi, rbx
    mov edx, TOUCH_MOTION
    mov ecx, EVENT_LONG
    movzx r8d, byte [r12 + RawInput.code]
    call send_input
    jmp .out
.down:
    test r13, r13
    jnz .move                           ; down again: as a move
    mov rdi, rbx                        ; the surface under it
    mov esi, [r12 + RawInput.device]
    mov edx, [r12 + RawInput.value]
    call device_point
    mov r15d, eax                       ; (the phase is not needed again)
    mov [rsp], edx
    mov rdi, rbx
    mov esi, eax
    call surface_at_point
    test rax, rax
    jz .out                             ; on nothing
    mov r13, rax
    xor ecx, ecx                        ; a free entry
.free:
    imul eax, ecx, TouchContact_size
    lea rdx, [rbx + InputSeat.touches + rax]
    cmp qword [rdx + TouchContact.surface], 0
    je .take
    inc ecx
    cmp ecx, TOUCH_SLOTS
    jb .free
    jmp .out                            ; too many fingers: this one ignored
.take:
    mov [rdx + TouchContact.surface], r13
    mov [rdx + TouchContact.key], r14d
    mov rdi, rbx
    mov rsi, r13
    call tap_focus
    mov rdi, rbx
    mov rsi, r13
    call scan_add
    mov rdi, r13
    mov esi, r15d
    mov edx, [rsp]
    call local_xy
    mov r9d, eax
    mov rdi, rbx
    mov rsi, r13
    mov edx, TOUCH_DOWN
    mov ecx, EVENT_LONG
    movzx r8d, byte [r12 + RawInput.code]
    call send_input
    jmp .out
.frame:
    mov rdi, rbx
    call scan_end
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; The scan over: frame to each surface that heard of it. rdi = seat
scan_end:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    xor r12d, r12d
.tell:
    cmp r12d, [rbx + InputSeat.scan_count]
    jae .told
    mov rsi, [rbx + InputSeat.scan + r12 * 8]
    test rsi, rsi
    jz .next                            ; gone meanwhile
    mov rdi, rbx
    mov edx, TOUCH_FRAME
    mov ecx, EVENT_SHORT
    call send_input
.next:
    inc r12d
    jmp .tell
.told:
    mov dword [rbx + InputSeat.scan_count], 0
    EPILOGUE_RESTORE rbx, r12

; Type 7: the pen in range goes to the surface under it (proximity in, then
; out when it leaves it or the range), the one it touched while the tip is
; down; motion, tip and the barrel buttons as they change.
; rdi = seat, rsi = RawInput*
pen_event:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r15d, [r12 + RawInput.code]     ; the bits now
    test r15d, PEN_IN_RANGE
    jnz .in_range
    mov rsi, [rbx + InputSeat.pen_surface]  ; out of range: gone
    test rsi, rsi
    jz .gone
    mov rdi, rbx
    mov edx, PEN_OUT
    mov ecx, EVENT_SHORT
    call send_input
.gone:
    mov qword [rbx + InputSeat.pen_surface], 0
    mov dword [rbx + InputSeat.pen_flags], 0
    jmp .out
.in_range:
    mov rdi, rbx
    mov esi, [r12 + RawInput.device]
    mov edx, [r12 + RawInput.value]
    call device_point
    mov r13d, eax                       ; x, y in the layout
    mov r14d, edx
    mov rax, [rbx + InputSeat.pen_surface]
    test rax, rax
    jz .target
    test dword [rbx + InputSeat.pen_flags], PEN_TIP_DOWN
    jnz .kept                           ; the tip down: it keeps the pen
.target:
    mov rdi, rbx
    mov esi, r13d
    mov edx, r14d
    call surface_at_point
.kept:
    cmp rax, [rbx + InputSeat.pen_surface]
    je .same
    push rax
    push rax                            ; 16-byte aligned
    mov rsi, [rbx + InputSeat.pen_surface]
    test rsi, rsi
    jz .entered
    mov rdi, rbx                        ; the last one: out
    mov edx, PEN_OUT
    mov ecx, EVENT_SHORT
    call send_input
.entered:
    pop rax
    pop rax
    mov [rbx + InputSeat.pen_surface], rax
    mov dword [rbx + InputSeat.pen_flags], PEN_IN_RANGE ; it hears it all anew
    test rax, rax
    jz .none
    mov rdi, rbx                        ; this one: in, with the tool
    mov rsi, rax
    mov edx, PEN_IN
    mov ecx, EVENT_LONG
    mov r8d, r15d
    shr r8d, 16
    and r8d, 0xFF
    xor r9d, r9d
    call send_input
.same:
    mov rsi, [rbx + InputSeat.pen_surface]
    test rsi, rsi
    jz .none
    mov rdi, rbx                        ; where it is
    mov edx, PEN_MOTION
    mov ecx, EVENT_LONG
    mov r8d, r13d
    sub r8d, [rsi + Surface.current + SurfaceState.buf_x]
    mov r9d, r14d
    sub r9d, [rsi + Surface.current + SurfaceState.buf_y]
    call send_input
    mov eax, r15d                       ; the tip, if it changed
    xor eax, [rbx + InputSeat.pen_flags]
    test eax, PEN_TIP_DOWN
    jz .buttons
    xor r8d, r8d
    test r15d, PEN_TIP_DOWN
    jz .tip
    mov r8d, 1
    mov rdi, rbx                        ; a tip down is a tap
    mov rsi, [rbx + InputSeat.pen_surface]
    call tap_focus
    mov r8d, 1
.tip:
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.pen_surface]
    mov edx, PEN_TIP
    mov ecx, EVENT_LONG
    xor r9d, r9d
    call send_input
.buttons:
%macro PEN_BUTTON_CHANGE 2              ; bit, number
    mov eax, r15d
    xor eax, [rbx + InputSeat.pen_flags]
    test eax, %1
    jz %%same
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.pen_surface]
    mov edx, PEN_BUTTON
    mov ecx, EVENT_LONG
    mov r8d, %2
    xor r9d, r9d
    test r15d, %1
    setnz r9b
    call send_input
%%same:
%endmacro
    PEN_BUTTON_CHANGE PEN_BUTTON_1, 0
    PEN_BUTTON_CHANGE PEN_BUTTON_2, 1
.none:
    mov [rbx + InputSeat.pen_flags], r15d
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; Type 8: the pen's pressure, distance, tilt and rotation, to the surface it
; is with; the pressure through the pen curve when one is set, the rest as
; they came. rdi = seat, rsi = RawInput*
pen_axes_event:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    cmp qword [rbx + InputSeat.pen_surface], 0
    je .none
    mov r8d, [r12 + RawInput.code]
    mov rax, [rbx + InputSeat.server]
    cmp qword [rax + Server.pen_curve_on], 0
    je .send
    lea rdi, [rax + Server.pen_curve]   ; y at x = the pressure (the curve's
    movzx ecx, r8w                      ; x is its t: inner points at x 1/3
    cvtsi2sd xmm0, ecx                  ; and 2/3)
    divsd xmm0, [rel pressure_max]
    call umath_bezier_cubic_eval
    mulsd xmm1, [rel pressure_max]
    addsd xmm1, [rel pressure_half]
    cvttsd2si eax, xmm1
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    mov ecx, 0xFFFF
    cmp eax, ecx
    cmovg eax, ecx
    mov r8d, [r12 + RawInput.code]
    and r8d, 0xFFFF0000
    or r8d, eax
.send:
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.pen_surface]
    mov edx, PEN_AXES
    mov ecx, EVENT_LONG
    mov r9d, [r12 + RawInput.value]
    call send_input
.none:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; server_set_pen_curve
;   Pen pressure through a curve: a cubic from (0, 0) to (1, 1) with inner
;   points at x 1/3 and 2/3, heights y1 and y2 (0-65535 for 0 to 1); 21845
;   and 43690 change nothing, higher ones make a light touch count more,
;   lower ones less. Both 0: no curve.
;   IN:  rdi = server*, esi = y1, edx = y2
;   OUT: rax = 0, -EINVAL past 65535
; ---------------------------------------------------------------------------
global server_set_pen_curve
server_set_pen_curve:
    mov rax, -(EINVAL)
    cmp esi, 0xFFFF
    ja .out
    cmp edx, 0xFFFF
    ja .out
    xor eax, eax
    mov ecx, esi
    or ecx, edx
    setnz al
    mov [rdi + Server.pen_curve_on], rax
    pxor xmm0, xmm0                     ; (0, 0)
    movsd [rdi + Server.pen_curve], xmm0
    movsd [rdi + Server.pen_curve + 8], xmm0
    movsd xmm0, [rel pressure_third]    ; (1/3, y1)
    movsd [rdi + Server.pen_curve + 16], xmm0
    cvtsi2sd xmm0, esi
    divsd xmm0, [rel pressure_max]
    movsd [rdi + Server.pen_curve + 24], xmm0
    movsd xmm0, [rel pressure_two_thirds]   ; (2/3, y2)
    movsd [rdi + Server.pen_curve + 32], xmm0
    cvtsi2sd xmm0, edx
    divsd xmm0, [rel pressure_max]
    movsd [rdi + Server.pen_curve + 40], xmm0
    movsd xmm0, [rel pressure_one]      ; (1, 1)
    movsd [rdi + Server.pen_curve + 48], xmm0
    movsd [rdi + Server.pen_curve + 56], xmm0
    xor eax, eax
.out:
    ret

; Type 11: a pad's button, ring or strip, to the surface with the keyboard.
; rdi = seat, rsi = RawInput*
pad_event:
    mov rax, rsi
    mov rsi, [rdi + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .none
    mov ecx, [rax + RawInput.code]
    mov r8d, ecx                        ; which
    shr r8d, 8
    and r8d, 0xFF
    movzx ecx, cl                       ; what
    mov edx, PAD_BUTTON
    cmp ecx, INPUT_PAD_BUTTON
    je .send
    mov edx, PAD_RING
    cmp ecx, INPUT_PAD_RING
    je .send
    mov edx, PAD_STRIP
    cmp ecx, INPUT_PAD_STRIP
    jne .none
.send:
    mov ecx, EVENT_LONG
    mov r9d, [rax + RawInput.value]
    jmp send_input
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Switches and devices (SES-08): records 9 and 10 (KERNEL_NEEDS.md step 3)
; ---------------------------------------------------------------------------

; Type 9: a switch on or off; a change goes to the cw_seat watchers, and the
; lid closing locks. rdi = seat, rsi = RawInput*
switch_event:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov ecx, [r12 + RawInput.code]
    cmp ecx, 32
    jae .out                            ; no such switch
    mov eax, [rbx + InputSeat.switches]
    mov edx, eax
    btr edx, ecx
    cmp dword [r12 + RawInput.value], 0
    je .set
    bts edx, ecx
.set:
    cmp edx, eax
    je .out                             ; as it was: nothing to tell
    mov [rbx + InputSeat.switches], edx
    mov rdi, [rbx + InputSeat.server]
    mov esi, ecx
    bt edx, ecx
    setc dl
    movzx edx, dl
    call seat_tell_switch
    cmp dword [r12 + RawInput.code], INPUT_SWITCH_LID
    jne .out
    mov rdi, [rbx + InputSeat.server]   ; the built-in panel off or on
    xor esi, esi
    cmp dword [r12 + RawInput.value], 0
    setne sil
    call clamshell_lid
    test eax, eax
    jnz .out                            ; another screen on: no lock
    cmp dword [r12 + RawInput.value], 0
    je .out
    mov rdi, [rbx + InputSeat.server]   ; the lid closed: locked, asleep
    call clamshell_sleep
.out:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; Type 10: a device added, removed or changed goes to the cw_seat watchers;
; one removed has its touch contacts cancelled first.
; rdi = seat, rsi = RawInput*
device_event:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    cmp dword [r12 + RawInput.code], INPUT_DEVICE_CHANGED
    ja .out                             ; no such change
    cmp dword [r12 + RawInput.code], INPUT_DEVICE_REMOVED
    jne .tell
    xor r13d, r13d                      ; its contacts: cancelled
.contact:
    imul eax, r13d, TouchContact_size
    lea rcx, [rbx + InputSeat.touches + rax]
    mov rsi, [rcx + TouchContact.surface]
    test rsi, rsi
    jz .next
    mov eax, [rcx + TouchContact.key]
    shr eax, 8
    cmp eax, [r12 + RawInput.device]
    jne .next
    mov qword [rcx + TouchContact.surface], 0
    mov [rsp], rsi
    mov rdi, rbx
    call scan_add
    imul eax, r13d, TouchContact_size
    movzx r8d, byte [rax + rbx + InputSeat.touches + TouchContact.key]
    mov rsi, [rsp]
    mov rdi, rbx
    mov edx, TOUCH_CANCEL
    mov ecx, EVENT_LONG
    xor r9d, r9d
    call send_input
.next:
    inc r13d
    cmp r13d, TOUCH_SLOTS
    jb .contact
    mov rdi, rbx                        ; and a frame to those that had them
    call scan_end
.tell:
    mov rdi, [rbx + InputSeat.server]
    mov esi, [r12 + RawInput.code]
    mov edx, [r12 + RawInput.device]
    mov ecx, [r12 + RawInput.value]
    call seat_tell_device
.out:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; input_set_sticky
;   Sticky keys on (1) or off (0); off, nothing stays latched or locked
;   IN:  rdi = server*, esi = 1 on, 0 off
;   OUT: rax = 0, -ENODEV with no seat
; ---------------------------------------------------------------------------
global input_set_sticky
input_set_sticky:
    mov rax, -(ENODEV)
    mov rdi, [rdi + Server.input_seat]
    test rdi, rdi
    jz .out
    mov [rdi + InputSeat.sticky_on], esi
    jmp sticky_reset
.out:
    ret

; Sticky keys (A11Y-04): a modifier pressed and let go with no key between
; latches it for the next key; tapped again it locks, and once more it is
; off. Five lone Shift taps in a row turn sticky keys on or off.
; rdi = seat, rsi = RawInput* (its key already marked held or not)
sticky_key:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov edi, [r12 + RawInput.code]
    call keymap_modifier
    test eax, eax
    jz .key
    cmp dword [r12 + RawInput.value], 0
    je .let_go
    mov [rbx + InputSeat.sticky_lone], eax  ; pressed: lone so far
    jmp .out
.let_go:
    cmp [rbx + InputSeat.sticky_lone], eax
    jne .out                            ; a key came between: no tap
    mov dword [rbx + InputSeat.sticky_lone], 0
    cmp eax, MOD_SHIFT
    jne .not_shift
    inc dword [rbx + InputSeat.shift_taps]
    cmp dword [rbx + InputSeat.shift_taps], 5
    jb .tap
    mov dword [rbx + InputSeat.shift_taps], 0   ; five: on or off
    xor dword [rbx + InputSeat.sticky_on], 1
    mov rdi, rbx
    call sticky_reset
    jmp .out
.not_shift:
    mov dword [rbx + InputSeat.shift_taps], 0
.tap:
    cmp dword [rbx + InputSeat.sticky_on], 0
    je .out
    test [rbx + InputSeat.sticky_locked], eax
    jz .not_locked
    not eax                             ; locked: off
    and [rbx + InputSeat.sticky_locked], eax
    and [rbx + InputSeat.sticky_latched], eax
    jmp .out
.not_locked:
    test [rbx + InputSeat.sticky_latched], eax
    jz .latch
    or [rbx + InputSeat.sticky_locked], eax ; latched: locked
    not eax
    and [rbx + InputSeat.sticky_latched], eax
    jmp .out
.latch:
    or [rbx + InputSeat.sticky_latched], eax
    jmp .out
.key:
    cmp dword [r12 + RawInput.value], 0
    je .out
    mov dword [rbx + InputSeat.sticky_lone], 0  ; a key: no lone tap, no
    mov dword [rbx + InputSeat.shift_taps], 0   ; run of Shift taps
    cmp dword [rbx + InputSeat.sticky_latched], 0
    je .out
    mov dword [rbx + InputSeat.sticky_clear], 1 ; the latch is this key's
.out:
    EPILOGUE_RESTORE rbx, r12

; rdi = seat: what was latched goes once its key is done; a latched Alt
; going is Alt let go (an Alt+Tab chooses); the client hears the modifiers
sticky_unlatch:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov eax, [rbx + InputSeat.sticky_latched]
    mov dword [rbx + InputSeat.sticky_latched], 0
    mov dword [rbx + InputSeat.sticky_clear], 0
    test eax, MOD_ALT
    jz .mods
    mov rdi, [rbx + InputSeat.server]
    call switcher_finish
.mods:
    mov rdi, rbx
    call sticky_tell
    add rsp, 8
    EPILOGUE_RESTORE rbx

; rdi = seat: nothing latched or locked; the client hears the modifiers
sticky_reset:
    mov dword [rdi + InputSeat.sticky_latched], 0
    mov dword [rdi + InputSeat.sticky_locked], 0
    mov dword [rdi + InputSeat.sticky_clear], 0
; rdi = seat: the modifiers again, told to the keyboard's client if changed
sticky_tell:
    push rbx
    mov rbx, rdi
    call keymap_mods
    test ecx, ecx
    jz .same
    mov rsi, [rbx + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .same
    mov rdi, rbx
    call send_modifiers
.same:
    xor eax, eax
    pop rbx
    ret

; edi = keycode -> eax = 1 if holding it repeats: not a modifier or a lock
key_repeats:
    xor eax, eax
    cmp edi, KEY_LEFTCTRL
    je .no
    cmp edi, KEY_LEFTSHIFT
    je .no
    cmp edi, KEY_RIGHTSHIFT
    je .no
    cmp edi, KEY_LEFTALT
    je .no
    cmp edi, KEY_CAPSLOCK
    je .no
    cmp edi, KEY_NUMLOCK
    je .no
    cmp edi, KEY_SCROLLLOCK
    je .no
    cmp edi, KEY_RIGHTCTRL
    je .no
    cmp edi, KEY_RIGHTALT
    je .no
    cmp edi, KEY_LEFTMETA
    je .no
    cmp edi, KEY_RIGHTMETA
    je .no
    inc eax
.no:
    ret

; Motion moves the pointer by (code, value), position puts it at (code,
; value); either way it stays inside what the outputs span.
pointer_event:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov eax, [rsi + RawInput.code]
    mov ecx, [rsi + RawInput.value]
    cmp dword [rsi + RawInput.type], INPUT_POSITION
    je .clamp
    add eax, [rbx + InputSeat.x]
    add ecx, [rbx + InputSeat.y]
.clamp:
    mov rdx, [rbx + InputSeat.server]   ; inside what the outputs span
    cmp qword [rdx + Server.outputs], 0
    je .placed
    push rax
    push rcx
    mov rdi, rdx
    call compositor_layout_bounds
    mov r9d, eax                        ; left
    mov r10d, edx                       ; top
    mov r11d, ecx                       ; right
    dec r11d
    dec r8d                             ; bottom
    pop rcx
    pop rax
    cmp eax, r9d
    cmovl eax, r9d
    cmp eax, r11d
    cmovg eax, r11d
    cmp ecx, r10d
    cmovl ecx, r10d
    cmp ecx, r8d
    cmovg ecx, r8d
.placed:
    push rax                            ; the arrow redrawn, where it was
    push rcx                            ; and where it goes
    mov rdi, [rbx + InputSeat.server]
    mov esi, [rbx + InputSeat.x]
    mov edx, [rbx + InputSeat.y]
    mov r8d, ecx
    mov ecx, eax
    call sw_cursor_moved
    mov rdi, [rbx + InputSeat.server]   ; and a zoomed view goes with it
    call magnify_moved
    pop rcx
    pop rax
    mov [rbx + InputSeat.x], eax
    mov [rbx + InputSeat.y], ecx

    ; An Alt+drag takes the window along or resizes it, and nobody hears of
    ; the motion
    mov rsi, [rbx + InputSeat.moving]
    test rsi, rsi
    jz .route
    cmp dword [rbx + InputSeat.move_mode], MOVE_RESIZE
    je .resize
    mov rdi, [rbx + InputSeat.server]
    mov edx, eax
    sub edx, [rbx + InputSeat.move_dx]
    sub ecx, [rbx + InputSeat.move_dy]
    call window_move
    jmp .out
.resize:
    mov rdi, rsi                        ; its size grows with the travel
    sub eax, [rbx + InputSeat.move_dx]
    add eax, [rbx + InputSeat.resize_w]
    mov esi, RESIZE_MIN
    cmp eax, esi
    cmovl eax, esi
    sub ecx, [rbx + InputSeat.move_dy]
    add ecx, [rbx + InputSeat.resize_h]
    cmp ecx, esi
    cmovl ecx, esi
    mov esi, eax
    mov edx, ecx
    call window_configure
    jmp .out
.route:

    ; A drag has the motion: the surface under the pointer hears of it
    mov rdi, [rbx + InputSeat.server]
    call dnd_active
    test eax, eax
    jz .no_drag
    mov rdi, rbx
    call surface_at
    mov rdi, [rbx + InputSeat.server]
    mov rsi, rax
    call dnd_over
    jmp .out
.no_drag:

    ; A held button keeps the surface; otherwise the one under the pointer
    ; takes it, and its enter carries the position
    cmp dword [rbx + InputSeat.buttons], 0
    jne .motion
    mov rdi, rbx
    call pointer_retarget
    test eax, eax
    jnz .out
.motion:
    mov rsi, [rbx + InputSeat.pointer_focus]
    test rsi, rsi
    jz .out
    mov rdi, rbx
    mov edx, POINTER_MOTION
    call send_at
.out:
    EPILOGUE_RESTORE rbx, r12

; A press on a surface focuses it, then the surface gets the button. Repeats
; (a press of a button that is down, a release of one that is up) are dropped.
; When the last button is up, the surface under the pointer takes it again.
button_event:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, [rsi + RawInput.code]
    cmp r12d, 31
    ja .out
    cmp qword [rbx + InputSeat.moving], 0
    jne .moving
    cmp dword [rsi + RawInput.value], 0
    je .release_held

    mov eax, [rbx + InputSeat.buttons]

    ; Alt+press on a window, no other button down: a move (left) or a
    ; resize (right) starts
    test dword [rbx + InputSeat.mods], MOD_ALT
    jz .press
    test eax, eax
    jnz .press
    cmp r12d, 1
    ja .press                           ; middle and beyond: an ordinary press
    mov rsi, [rbx + InputSeat.pointer_focus]
    test rsi, rsi
    jz .press
    mov rcx, [rsi + Surface.window]
    test rcx, rcx
    jz .press
    cmp dword [rcx + Window.kind], ROLE_TOPLEVEL
    jne .press
    mov [rbx + InputSeat.moving], rsi
    test r12d, r12d
    jnz .start_resize
    mov dword [rbx + InputSeat.move_mode], MOVE_MOVE
    mov edx, [rbx + InputSeat.x]
    sub edx, [rcx + Window.x]
    mov [rbx + InputSeat.move_dx], edx
    mov edx, [rbx + InputSeat.y]
    sub edx, [rcx + Window.y]
    mov [rbx + InputSeat.move_dy], edx
    jmp .started
.start_resize:
    mov dword [rbx + InputSeat.move_mode], MOVE_RESIZE
    mov edx, [rbx + InputSeat.x]
    mov [rbx + InputSeat.move_dx], edx
    mov edx, [rbx + InputSeat.y]
    mov [rbx + InputSeat.move_dy], edx
    mov dword [rbx + InputSeat.resize_w], RESIZE_MIN    ; until its buffer says
    mov dword [rbx + InputSeat.resize_h], RESIZE_MIN
    mov rsi, [rsi + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .started
    mov rdi, [rbx + InputSeat.server]
    mov rdi, [rdi + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .started
    mov rdi, [rbx + InputSeat.moving]   ; its size on the screen
    mov rsi, rax
    call surface_logical_size
    mov [rbx + InputSeat.resize_w], eax
    mov [rbx + InputSeat.resize_h], edx
.started:
    mov rdi, rbx
    call click_focus
    jmp .out
.release_held:
    mov eax, [rbx + InputSeat.buttons]
    jmp .release

.press:
    bt eax, r12d
    jc .out
    mov rdi, [rbx + InputSeat.server]   ; on anything but a popup, it ends
    mov rsi, [rbx + InputSeat.pointer_focus]    ; the popups
    call window_dismiss_popups
    mov eax, [rbx + InputSeat.buttons]
    cmp qword [rbx + InputSeat.pointer_focus], 0
    jne .held
    cmp qword [rbx + InputSeat.bar], 0
    je .held
    test eax, eax                       ; a title bar: the left button alone
    jnz .out
    test r12d, r12d
    jnz .out
    mov rdi, rbx
    call bar_press
    jmp .out
.held:
    bts eax, r12d
    mov [rbx + InputSeat.buttons], eax
    cmp qword [rbx + InputSeat.pointer_focus], 0
    je .out                             ; on no surface: focus stays
    mov rdi, rbx
    call click_focus
    mov r9d, 1
    jmp .send

    ; During a move every press is ignored and a release ends it
.moving:
    cmp dword [rsi + RawInput.value], 0
    jne .out
    mov qword [rbx + InputSeat.moving], 0
    mov rdi, rbx
    call pointer_retarget
    jmp .out
.release:
    btr eax, r12d
    jnc .out
    mov [rbx + InputSeat.buttons], eax
    test eax, eax                       ; the last up: a drag drops
    jnz .still_held
    mov rdi, [rbx + InputSeat.server]
    call dnd_release
.still_held:
    xor r9d, r9d
.send:
    mov rsi, [rbx + InputSeat.pointer_focus]
    test rsi, rsi
    jz .regrab
    mov rdi, rbx
    mov edx, POINTER_BUTTON
    mov ecx, EVENT_LONG
    mov r8d, r12d
    call send_input
.regrab:
    cmp dword [rbx + InputSeat.buttons], 0
    jne .out
    mov rdi, rbx
    call pointer_retarget
.out:
    EPILOGUE_RESTORE rbx, r12

; The server's keys: Super+1 to 4 and, for the window with the keyboard,
; Super+Shift+1 to 4, Alt+F4, Super+Up, Super+Down.
; rdi = seat, esi = the keycode pressed -> eax = 1 if it was one
shortcut:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, [rbx + InputSeat.server]
    mov edx, [rbx + InputSeat.mods]     ; Super+Shift+H: high contrast, on
    and edx, MOD_SUPER | MOD_SHIFT | MOD_CTRL | MOD_ALT  ; the login screen
    cmp edx, MOD_SUPER | MOD_SHIFT      ; too; Super+Shift+M: the magnifier
    jne .not_contrast
    cmp esi, KEY_M
    je .magnifier
    cmp esi, KEY_H
    jne .not_contrast
    mov rdi, rax
    mov esi, [rax + Server.high_contrast]
    xor esi, 1
    call server_set_high_contrast
    jmp .yes
.magnifier:                             ; off, 2x, 4x, off
    mov rdi, rax
    mov rsi, [rax + Server.magnify]
    add esi, esi
    cmp esi, 4
    jbe .zoom
    xor esi, esi
.zoom:
    test esi, esi
    jnz .zoomed
    cmp qword [rax + Server.magnify], 0
    jne .zoomed
    mov esi, 2
.zoomed:
    call server_set_magnifier
    jmp .yes
.not_contrast:
    mov rax, [rbx + InputSeat.server]
    cmp qword [rax + Server.locked], 0
    jne .no                             ; the login screen's keys are its own
    mov edx, [rbx + InputSeat.mods]
    test edx, MOD_ALT
    jz .super_keys
    cmp esi, KEY_TAB
    jne .alt_esc
    mov rdi, rax
    call switcher_next
    jmp .yes
.alt_esc:
    cmp esi, KEY_ESC
    jne .super_keys
    call switcher_selected_any
    test eax, eax
    jz .super_keys                      ; no switch running: Esc is the client's
    call switcher_cancel
    jmp .yes
.super_keys:
    mov rax, [rbx + InputSeat.server]
    mov edx, [rbx + InputSeat.mods]
    test edx, MOD_SUPER
    jz .window_keys
    cmp esi, KEY_L
    jne .workspace_keys
    mov rdi, [rax + Server.greeter]
    test rdi, rdi
    jz .no
    call greeter_lock
    jmp .yes
.workspace_keys:
    lea eax, [rsi - KEY_1]
    cmp eax, WORKSPACES
    jae .window_keys
    test edx, MOD_SHIFT
    jnz .move_to
    mov rdi, [rbx + InputSeat.server]
    mov esi, eax
    call window_switch_workspace
    jmp .yes
.move_to:
    mov rdi, [rbx + InputSeat.server]
    mov rsi, [rbx + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .yes
    mov edx, eax
    call window_move_to_workspace       ; -EINVAL for no window: still a key
    jmp .yes
.window_keys:
    mov r12, [rbx + InputSeat.keyboard_focus]
    test r12, r12
    jz .no
    mov rcx, [r12 + Surface.window]
    test rcx, rcx
    jz .no
    cmp dword [rcx + Window.kind], ROLE_TOPLEVEL
    jne .no
    mov edx, [rbx + InputSeat.mods]
    test edx, MOD_ALT
    jz .super
    cmp esi, KEY_F4
    jne .super
    mov rdi, r12
    call window_close
    jmp .yes
.super:
    test edx, MOD_SUPER
    jz .no
    cmp esi, KEY_UP
    je .maximize
    cmp esi, KEY_DOWN
    jne .no
    mov rdi, [rbx + InputSeat.server]
    mov rsi, r12
    call window_minimize
    jmp .yes
.maximize:
    xor edx, edx                        ; the other way from how it is
    test dword [rcx + Window.state], WINDOW_MAXIMIZED
    setz dl
    mov rdi, [rbx + InputSeat.server]
    mov rsi, r12
    call window_maximize
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

; -> eax = 1 while an Alt+Tab runs
switcher_selected_any:
    sub rsp, 8
    call switcher_selected
    add rsp, 8
    test rax, rax
    setnz al
    movzx eax, al
    ret

; A press on the surface under the pointer raises it, and gives it the
; keyboard unless it is a layer below the windows or a top layer.
; rdi = seat
click_focus:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov rdi, [rbx + InputSeat.server]
    mov rsi, [rbx + InputSeat.pointer_focus]
    call compositor_raise_surface
    mov rdi, [rbx + InputSeat.pointer_focus]
    call stacking_level
    test eax, eax
    js .out
    cmp eax, LEVEL_TOP
    je .out                             ; a panel: the window keeps it
    mov rdi, rbx
    mov rsi, [rbx + InputSeat.pointer_focus]
    call set_keyboard_focus
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx

; A press on a title bar: the window is raised and focused, then the
; button acts, or a move starts.
; rdi = seat
bar_press:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + InputSeat.bar]
    mov rdi, [rbx + InputSeat.server]
    mov rsi, r12
    call compositor_raise_surface
    mov rdi, rbx
    mov rsi, r12
    call set_keyboard_focus
    mov eax, [rbx + InputSeat.bar_part]
    cmp eax, TITLEBAR_CLOSE
    je .close
    cmp eax, TITLEBAR_MAXIMIZE
    je .maximize
    cmp eax, TITLEBAR_MINIMIZE
    je .minimize
    mov rcx, [r12 + Surface.window]     ; the bar itself: a move
    mov [rbx + InputSeat.moving], r12
    mov dword [rbx + InputSeat.move_mode], MOVE_MOVE
    mov edx, [rbx + InputSeat.x]
    sub edx, [rcx + Window.x]
    mov [rbx + InputSeat.move_dx], edx
    mov edx, [rbx + InputSeat.y]
    sub edx, [rcx + Window.y]
    mov [rbx + InputSeat.move_dy], edx
    jmp .out
.close:
    mov rdi, r12
    call window_close
    jmp .out
.maximize:
    mov rcx, [r12 + Surface.window]
    xor edx, edx
    test dword [rcx + Window.state], WINDOW_MAXIMIZED
    setz dl
    mov rdi, [rbx + InputSeat.server]
    mov rsi, r12
    call window_maximize
    jmp .out
.minimize:
    mov rdi, [rbx + InputSeat.server]
    mov rsi, r12
    call window_minimize
.out:
    EPILOGUE_RESTORE rbx, r12

; Scrolling goes to the surface under the pointer
axis_event:
    mov eax, [rsi + RawInput.code]
    cmp eax, 1
    ja .drop
    mov r8d, eax
    mov r9d, [rsi + RawInput.value]
    mov rsi, [rdi + InputSeat.pointer_focus]
    test rsi, rsi
    jz .drop
    mov edx, POINTER_AXIS
    mov ecx, EVENT_LONG
    jmp send_input
.drop:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Focus
; ---------------------------------------------------------------------------

; rdi = seat -> eax = 1 if the pointer moved to another surface (leave, enter
; sent), 0 if it stayed
pointer_retarget:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    call surface_at
    xor r12d, r12d
    cmp rax, [rbx + InputSeat.pointer_focus]
    je .out
    mov rdi, rbx
    mov rsi, rax
    call set_pointer_focus
    mov r12d, 1
.out:
    mov eax, r12d
    EPILOGUE_RESTORE rbx, r12

; rdi = seat, rsi = surface or 0
set_pointer_focus:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rsi, [rbx + InputSeat.pointer_focus]
    test rsi, rsi
    jz .enter
    mov rdi, rbx
    mov edx, POINTER_LEAVE
    mov ecx, EVENT_SHORT
    call send_input
.enter:
    mov [rbx + InputSeat.pointer_focus], r12
    test r12, r12
    jz .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, POINTER_ENTER
    call send_at
.out:
    EPILOGUE_RESTORE rbx, r12

; rdi = seat, rsi = surface or 0
set_keyboard_focus:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + InputSeat.keyboard_focus]
    cmp r12, r13
    je .out
    test r12, r12                       ; never to a client without the
    jz .lock                            ; keyboard capability
    mov rax, [r12 + Surface.client]
    test rax, rax
    jz .out
    test qword [rax + Client.caps], CAP_KEYBOARD
    jz .out
.lock:
    mov rax, [rbx + InputSeat.server]   ; locked: it stays on the login screen
    cmp qword [rax + Server.locked], 0  ; unless it goes to another overlay
    je .allowed
    test r12, r12
    jz .out
    mov rax, [r12 + Surface.window]
    test rax, rax
    jz .out
    cmp dword [rax + Window.level], LEVEL_OVERLAY
    jl .out
.allowed:
    mov dword [rbx + InputSeat.repeat_key], 0   ; a new surface, no repeat
    test r13, r13
    jz .enter
    mov rdi, rbx
    mov rsi, r13
    mov edx, KEYBOARD_LEAVE
    mov ecx, EVENT_SHORT
    call send_input
.enter:
    mov [rbx + InputSeat.keyboard_focus], r12
    mov rdi, [rbx + InputSeat.server]   ; the window list hears of it
    mov rsi, r12
    call window_list_activated
    mov rdi, [rbx + InputSeat.server]   ; both title bars change colour
    mov rsi, r13
    mov rdx, r12
    call titlebar_focus_changed
    test r12, r12
    jz .out
    mov rdi, [rbx + InputSeat.server]   ; the magnifier goes to it
    mov rsi, r12
    call magnify_focus
    mov rdi, rbx
    mov rsi, r12
    mov edx, KEYBOARD_ENTER
    mov ecx, EVENT_SHORT
    call send_input
    mov rdi, rbx                        ; and where the modifiers stand
    mov rsi, r12
    call send_modifiers
    mov rdi, [rbx + InputSeat.server]   ; and what it could paste
    mov rsi, [r12 + Surface.client]
    call clipboard_focus_changed
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; (input_surface_at for input/gestures)
; rdi = seat -> rax = the topmost surface under the pointer, 0 if none, on
; whichever output. Server.stack runs bottom to top, so the last hit wins. A surface is hit
; inside its attached buffer, the size it is drawn at (sw_render), and inside
; its input region when that is not empty. Nothing attached: nothing to hit.
global input_surface_at
input_surface_at:
surface_at:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    xor r13d, r13d
    mov qword [rbx + InputSeat.bar], 0
    mov rax, [rbx + InputSeat.server]
    mov r12, [rax + Server.stack]
.surface:
    test r12, r12
    jz .done
    mov rax, [rbx + InputSeat.server]   ; locked: only the overlays are there
    cmp qword [rax + Server.locked], 0
    je .unlocked
    mov rax, [r12 + Surface.window]
    test rax, rax
    jz .next
    cmp dword [rax + Window.level], LEVEL_OVERLAY
    jl .next
.unlocked:
    mov rdi, r12                        ; its title bar, if it has one
    mov esi, [rbx + InputSeat.x]
    mov edx, [rbx + InputSeat.y]
    call titlebar_part
    test eax, eax
    jz .content
    mov r13, r12
    mov [rbx + InputSeat.bar], r12
    mov [rbx + InputSeat.bar_part], eax
    jmp .next
.content:
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .next
    mov rax, [rbx + InputSeat.server]
    mov rdi, [rax + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .next
    mov rdi, r12                        ; its size on the screen: r14d wide,
    mov rsi, rax                        ; the high half high
    call surface_logical_size
    mov r14d, eax
    shl rdx, 32
    or r14, rdx
    mov esi, [rbx + InputSeat.x]
    sub esi, [r12 + Surface.current + SurfaceState.buf_x]
    js .next
    cmp esi, r14d
    jae .next
    mov edx, [rbx + InputSeat.y]
    sub edx, [r12 + Surface.current + SurfaceState.buf_y]
    js .next
    mov rcx, r14
    shr rcx, 32
    cmp edx, ecx
    jae .next
    mov rdi, [r12 + Surface.current + SurfaceState.input]
    test rdi, rdi
    jz .hit
    cmp qword [rdi + Region.count], 0
    je .hit                             ; empty: the whole surface
    call region_contains_point
    test rax, rax
    jz .next
.hit:
    mov r13, r12
    mov qword [rbx + InputSeat.bar], 0
.next:
    mov r12, [r12 + Surface.z_order_next]
    jmp .surface
.done:
    cmp qword [rbx + InputSeat.bar], 0
    je .found
    xor r13d, r13d                      ; a bar: no surface for the client
.found:
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; Sending
; ---------------------------------------------------------------------------

; The modifiers event: held modifiers and locks (MOD_* in inc/input.inc).
; rdi = seat, rsi = surface
send_modifiers:
    mov r8d, [rdi + InputSeat.mods]
    mov r9d, [rdi + InputSeat.locks]
    mov edx, KEYBOARD_MODIFIERS
    mov ecx, EVENT_LONG
    jmp send_input

; An event carrying the pointer in the surface's coordinates.
; rdi = seat, rsi = surface, edx = event
send_at:
    mov r8d, [rdi + InputSeat.x]
    sub r8d, [rsi + Surface.current + SurfaceState.buf_x]
    mov r9d, [rdi + InputSeat.y]
    sub r9d, [rsi + Surface.current + SurfaceState.buf_y]
    mov ecx, EVENT_LONG
    jmp send_input

; rdi = seat, rsi = surface, edx = event (interface << 16 | index),
; ecx = payload bytes (EVENT_SHORT or EVENT_LONG), r8d = a, r9d = b.
; The payload is (time, surface, a, b); a client whose ring is full misses it.
global input_send
input_send:
send_input:
    PROLOGUE
    sub rsp, 48                         ; header at 0, payload at 16
    mov rax, [rsi + Surface.client]
    test rax, rax
    jz .out
    mov r10d, edx                       ; only to a client that asked for
    shr r10d, 16                        ; that kind of input
    mov r11d, CAP_POINTER
    cmp r10d, CWP_OBJ_POINTER
    je .gate
    cmp r10d, CWP_OBJ_GESTURE
    je .gate
    mov r11d, CAP_KEYBOARD
    cmp r10d, CWP_OBJ_KEYBOARD
    je .gate
    mov r11d, CAP_TOUCH
    cmp r10d, CWP_OBJ_TOUCH
    je .gate
    mov r11d, CAP_TABLET
    cmp r10d, CWP_OBJ_TABLET_TOOL
    je .gate
    cmp r10d, CWP_OBJ_TABLET_PAD
    jne .allowed
.gate:
    test [rax + Client.caps], r11
    jz .out
.allowed:
    mov r10, [rdi + InputSeat.time]
    mov [rsp + 16], r10
    mov r10d, [rsi + Surface.id]
    mov [rsp + 24], r10d
    mov [rsp + 28], r8d
    mov [rsp + 32], r9d
    mov r10d, edx
    shr r10d, 16
    mov [rsp + MsgHdr.obj], r10d
    mov [rsp + MsgHdr.opcode], dx
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov [rsp + MsgHdr.len], ecx
    mov rdi, [rax + Client.rx_ring]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
.out:
    EPILOGUE

section .rodata
align 8
pressure_max:       dq 65535.0
pressure_half:      dq 0.5
pressure_third:     dq 0.3333333333333333
pressure_two_thirds: dq 0.6666666666666666
pressure_one:       dq 1.0

section .data
global input_version
input_version: dq 0x020000
