; ============================================================================
; Input — From Raw Events to the Focused Surface
; ============================================================================
; Every source, the kernel's drivers or virtual injection, hands raw records
; (RawInput, the INPUT_* types in inc/event.inc) to input_submit, which queues
; them on the active seat. server_poll calls input_dispatch once a turn, which
; drains the queue:
;
;   keys     go to the surface with keyboard focus; a held key that is not a
;            modifier or a lock repeats, checked at the end of each turn
;            (input_repeat_deadline says when the loop must wake for it)
;   pointer  moves within the first output; the topmost surface under it gets
;            enter, leave, motion, button and axis events in its own
;            coordinates. While a button is held that surface keeps the
;            pointer, so a drag stays with its window.
;   a press  on a surface raises it and, unless it is a background, bottom
;            or top layer, gives it the keyboard focus
;   Alt+F4   asks the focused window's client to close it; Super+Up
;            maximizes it or puts it back, Super+Down minimizes it;
;            Super+1 to 4 shows a workspace, Super+Shift+1 to 4 moves the
;            focused window there
;   Alt+drag moves the window under the pointer, Alt+right-drag resizes it
;            (configure with the new size); its client sees none of the drag
;   a press  on anything but a popup ends every popup (an Alt+drag does not)
;
; Server.input_seat is the one place input is routed from. input_set_seat
; switches it, first releasing every key and button the old seat holds, so
; nothing is left stuck: that is the hook a KVM switch needs.
;
; Events reach clients as cw_keyboard and cw_pointer events
; (proto/canvas-input.cwp), each payload (time: ulong, surface: handle) and,
; for most, two more 32-bit values.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern compositor_raise_surface
extern handle_resolve
extern keymap_key
extern msgbuf_write
extern region_contains_point
extern stacking_level
extern window_close
extern window_configure
extern window_dismiss_popups
extern window_list_activated
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
    jmp .handled                        ; an unknown type is dropped
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
    jne .done
    mov qword [rax + InputSeat.moving], 0
.done:
    xor eax, eax
    ret

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
; value); either way it stays on the first output.
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
    mov rdx, [rbx + InputSeat.server]
    mov rdx, [rdx + Server.outputs]
    test rdx, rdx
    jz .placed
    xor r8d, r8d
    test eax, eax
    cmovs eax, r8d
    test ecx, ecx
    cmovs ecx, r8d
    mov r8d, [rdx + Output.width]
    dec r8d
    cmp eax, r8d
    cmovg eax, r8d
    mov r8d, [rdx + Output.height]
    dec r8d
    cmp ecx, r8d
    cmovg ecx, r8d
.placed:
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
    mov ecx, [rax + Buffer.width]
    mov [rbx + InputSeat.resize_w], ecx
    mov ecx, [rax + Buffer.height]
    mov [rbx + InputSeat.resize_h], ecx
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
    mov edx, [rbx + InputSeat.mods]
    test edx, MOD_SUPER
    jz .window_keys
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
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    cmp r12, [rbx + InputSeat.keyboard_focus]
    je .out
    mov dword [rbx + InputSeat.repeat_key], 0   ; a new surface, no repeat
    mov rsi, [rbx + InputSeat.keyboard_focus]
    test rsi, rsi
    jz .enter
    mov rdi, rbx
    mov edx, KEYBOARD_LEAVE
    mov ecx, EVENT_SHORT
    call send_input
.enter:
    mov [rbx + InputSeat.keyboard_focus], r12
    mov rdi, [rbx + InputSeat.server]   ; the window list hears of it
    mov rsi, r12
    call window_list_activated
    test r12, r12
    jz .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, KEYBOARD_ENTER
    mov ecx, EVENT_SHORT
    call send_input
    mov rdi, rbx                        ; and where the modifiers stand
    mov rsi, r12
    call send_modifiers
.out:
    EPILOGUE_RESTORE rbx, r12

; rdi = seat -> rax = the topmost surface under the pointer, 0 if none.
; Output.surfaces runs bottom to top, so the last hit wins. A surface is hit
; inside its attached buffer, the size it is drawn at (sw_render), and inside
; its input region when that is not empty. Nothing attached: nothing to hit.
surface_at:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    xor r13d, r13d
    mov rax, [rbx + InputSeat.server]
    mov rax, [rax + Server.outputs]
    test rax, rax
    jz .done
    mov r12, [rax + Output.surfaces]
.surface:
    test r12, r12
    jz .done
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .next
    mov rax, [rbx + InputSeat.server]
    mov rdi, [rax + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .next
    mov r14, rax                        ; the buffer
    mov esi, [rbx + InputSeat.x]
    sub esi, [r12 + Surface.current + SurfaceState.buf_x]
    js .next
    cmp esi, [r14 + Buffer.width]
    jae .next
    mov edx, [rbx + InputSeat.y]
    sub edx, [r12 + Surface.current + SurfaceState.buf_y]
    js .next
    cmp edx, [r14 + Buffer.height]
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
.next:
    mov r12, [r12 + Surface.z_order_next]
    jmp .surface
.done:
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
send_input:
    PROLOGUE
    sub rsp, 48                         ; header at 0, payload at 16
    mov rax, [rsi + Surface.client]
    test rax, rax
    jz .out
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

section .data
global input_version
input_version: dq 0x020000
