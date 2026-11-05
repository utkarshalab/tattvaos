; ============================================================================
; Unit Test — Input Routing (src/input/input.asm)
; ============================================================================
; test_input_suite -> eax = failed cases (each case returns 0 / 1).
; A server on 64x48 and one client with two surfaces: A at (0, 0) and B on top
; of it at (16, 8), both 32x24; B was shown last, so it has the keyboard. Input
; goes in through virtual_input_inject and the client reads the cw_pointer and
; cw_keyboard events that come out.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern client_accept
extern input_repeat_deadline
extern input_set_repeat
extern input_set_seat
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern virtual_input_inject

%define HEAP_SIZE (2 * 1024 * 1024)

%define OP_CREATE   0
%define OP_DESTROY  1
%define OP_ATTACH   2
%define OP_DAMAGE   3
%define OP_COMMIT   12
%define OP_SET_INPUT 6
%define RG_CREATE   0
%define RG_ADD      2

; cw_pointer and cw_keyboard events (proto/canvas-input.cwp)
%define P_ENTER     0
%define P_LEAVE     1
%define P_MOTION    2
%define P_BUTTON    3
%define K_ENTER     0
%define K_LEAVE     1
%define K_KEY       2
%define K_MODIFIERS 3
%define K_TEXT      4

section .text

global test_input_suite
test_input_suite:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE ti_enter_leave
    CASE ti_click_focus
    CASE ti_raise
    CASE ti_keymap
    CASE ti_repeat
    CASE ti_held_button
    CASE ti_release_on_switch
    CASE ti_forget_surface
    CASE ti_unmap
    CASE ti_input_region
    CASE ti_queue_full
    CASE ti_clamp
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; inject type, code, value
%macro INJECT 3
    lea rdi, [rel server]
    mov esi, %1
    mov edx, %2
    mov ecx, %3
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; the next event: interface, event, surface variable, a, b
%macro EXPECT 5
    call next_input
    cmp rax, 20
    jne .fail
    cmp dword [rel hdr + MsgHdr.obj], %1
    jne .fail
    cmp word [rel hdr + MsgHdr.opcode], %2
    jne .fail
    mov eax, [rel %3]
    cmp [rel ans + 8], eax
    jne .fail
    cmp dword [rel ans + 12], %4
    jne .fail
    cmp dword [rel ans + 16], %5
    jne .fail
%endmacro

; the next event carries only (time, surface): interface, event, surface
%macro EXPECT_SHORT 3
    call next_input
    cmp rax, 12
    jne .fail
    cmp dword [rel hdr + MsgHdr.obj], %1
    jne .fail
    cmp word [rel hdr + MsgHdr.opcode], %2
    jne .fail
    mov eax, [rel %3]
    cmp [rel ans + 8], eax
    jne .fail
%endmacro

%macro NOTHING 0
    call next_input
    test rax, rax
    jns .fail
%endmacro

; send interface, opcode, the first %3 bytes of [req]
%macro SEND 3
    mov dword [rel hdr + MsgHdr.obj], %1
    mov word [rel hdr + MsgHdr.opcode], %2
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], %3
    call send
%endmacro

; a started server, client A, and the scene; every message so far read
fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    mov edx, 64
    mov ecx, 48
    xor r8d, r8d
    call server_init
    lea rdi, [rel server]
    lea rsi, [rel pair]
    xor edx, edx
    call client_accept
    call drain
    mov edi, 0
    mov esi, 0
    call scene_surface
    mov [rel surface_a], eax
    mov edi, 16
    mov esi, 8
    call scene_surface
    mov [rel surface_b], eax
    call poll
    call drain
    add rsp, 8
    ret

; a 32x24 surface shown at (edi, esi) -> eax = its handle
scene_surface:
    push rbx
    mov [rel show_x], edi
    mov [rel show_y], esi
    mov dword [rel req], 32
    mov dword [rel req + 4], 24
    mov dword [rel req + 8], DRM_FORMAT_BGRA8888
    mov dword [rel req + 12], 0
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_BUFFER, OP_CREATE, 24
    call poll
    call next_reply
    mov ebx, [rel ans]
    SEND CWP_OBJ_SURFACE, OP_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel shown], eax
    mov [rel req], eax
    mov [rel req + 4], ebx
    mov eax, [rel show_x]
    mov [rel req + 8], eax
    mov eax, [rel show_y]
    mov [rel req + 12], eax
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_SURFACE, OP_ATTACH, 24
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    mov dword [rel req + 12], 32
    mov dword [rel req + 16], 24
    SEND CWP_OBJ_SURFACE, OP_DAMAGE, 20
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    mov eax, [rel shown]
    pop rbx
    ret

send:
    sub rsp, 8
    lea rdi, [rel pair + ChannelPair.client_to_server]
    mov rdi, [rdi]
    lea rsi, [rel hdr]
    lea rdx, [rel req]
    call msgbuf_write
    add rsp, 8
    ret

poll:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    add rsp, 8
    ret

; the next message for the client into hdr / ans -> rax = payload length
next_event:
    sub rsp, 8
    lea rdi, [rel pair + ChannelPair.server_to_client]
    mov rdi, [rdi]
    lea rsi, [rel hdr]
    lea rdx, [rel ans]
    mov ecx, 256
    call msgbuf_read
    add rsp, 8
    ret

; the next reply, skipping events
next_reply:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    js .done
    test word [rel hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .next
.done:
    add rsp, 8
    ret

; the next cw_pointer or cw_keyboard event, skipping every other message
; (presentation feedback follows frames) -> rax = payload length, negative if
; none
next_input:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    js .done
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_POINTER
    je .done
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_KEYBOARD
    jne .next
.done:
    add rsp, 8
    ret

drain:
    sub rsp, 8
.next:
    call next_event
    test rax, rax
    jns .next
    add rsp, 8
    ret

; ---------------------------------------------------------------------------
; Cases
; ---------------------------------------------------------------------------

; The pointer enters A, crosses onto B, which is on top, and moves there
ti_enter_leave:
    sub rsp, 8
    INJECT INPUT_POSITION, 4, 4
    call poll
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_a, 4, 4
    NOTHING
    INJECT INPUT_POSITION, 20, 10
    call poll
    EXPECT_SHORT CWP_OBJ_POINTER, P_LEAVE, surface_a
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_b, 4, 2
    INJECT INPUT_MOTION, 1, 1
    call poll
    EXPECT CWP_OBJ_POINTER, P_MOTION, surface_b, 5, 3
    NOTHING
    PASS

; Keys go to the surface shown last until a click focuses another, then only
; to that one; a release of a key that is not down is dropped
ti_click_focus:
    sub rsp, 8
    INJECT INPUT_POSITION, 4, 4
    INJECT INPUT_KEY, 30, 1
    INJECT INPUT_KEY, 30, 0
    call poll
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_a, 4, 4
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 30, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_b, 'a', 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 30, 0
    NOTHING
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    EXPECT_SHORT CWP_OBJ_KEYBOARD, K_LEAVE, surface_b
    EXPECT_SHORT CWP_OBJ_KEYBOARD, K_ENTER, surface_a
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_a, 0, 0
    EXPECT CWP_OBJ_POINTER, P_BUTTON, surface_a, 0, 1
    EXPECT CWP_OBJ_POINTER, P_BUTTON, surface_a, 0, 0
    NOTHING
    INJECT INPUT_KEY, 31, 1
    INJECT INPUT_KEY, 31, 0
    INJECT INPUT_KEY, 31, 0
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 31, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_a, 's', 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 31, 0
    NOTHING
    PASS

; A click raises the surface: A is now over B where they overlap
ti_raise:
    sub rsp, 8
    INJECT INPUT_POSITION, 4, 4
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    call drain
    INJECT INPUT_POSITION, 20, 10
    call poll
    EXPECT CWP_OBJ_POINTER, P_MOTION, surface_a, 20, 10
    NOTHING
    PASS

; Shift, Caps Lock and Num Lock choose the character; Ctrl types none
ti_keymap:
    sub rsp, 8
    INJECT INPUT_POSITION, 4, 4
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    call drain
    INJECT INPUT_KEY, 42, 1             ; Shift
    INJECT INPUT_KEY, 30, 1             ; a
    INJECT INPUT_KEY, 30, 0
    INJECT INPUT_KEY, 3, 1              ; 2
    INJECT INPUT_KEY, 42, 0
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 42, 1
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_a, 1, 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 30, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_a, 'A', 1
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 30, 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 3, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_a, '@', 1
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 42, 0
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_a, 0, 0
    NOTHING
    INJECT INPUT_KEY, 3, 0
    INJECT INPUT_KEY, 58, 1             ; Caps Lock on
    INJECT INPUT_KEY, 58, 0
    INJECT INPUT_KEY, 48, 1             ; b
    INJECT INPUT_KEY, 48, 0
    INJECT INPUT_KEY, 2, 1              ; 1: Caps Lock shifts letters only
    INJECT INPUT_KEY, 2, 0
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 3, 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 58, 1
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_a, 0, 2
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 58, 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 48, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_a, 'B', 2
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 48, 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 2, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_a, '1', 2
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 2, 0
    NOTHING
    call drain
    INJECT INPUT_KEY, 79, 1             ; keypad 1, Num Lock off: nothing
    INJECT INPUT_KEY, 79, 0
    INJECT INPUT_KEY, 29, 1             ; Ctrl
    INJECT INPUT_KEY, 46, 1             ; c: a shortcut, no text
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 79, 1
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 79, 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 29, 1
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_a, 4, 2
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 46, 1
    NOTHING
    PASS

; A held key repeats with its text; letting go stops it. Shift does not
; repeat. No delay here, so the first repeat comes in the turn of the press.
ti_repeat:
    sub rsp, 8
    lea rdi, [rel server]
    xor esi, esi                        ; no delay
    mov edx, 1000000000                 ; then one a second
    call input_set_repeat
    test rax, rax
    jnz .fail
    INJECT INPUT_KEY, 30, 1
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 30, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_b, 'a', 0
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 30, 2
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_b, 'a', 0
    NOTHING
    call poll                           ; not a second yet
    NOTHING
    INJECT INPUT_KEY, 30, 0
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 30, 0
    NOTHING
    INJECT INPUT_KEY, 42, 1
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 42, 1
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_b, 1, 0
    NOTHING
    lea rdi, [rel server]
    call input_repeat_deadline
    test rax, rax
    jnz .fail
    PASS

; While a button is held B keeps the pointer over A; letting go hands it on
ti_held_button:
    sub rsp, 8
    INJECT INPUT_POSITION, 20, 10
    INJECT INPUT_BUTTON, 0, 1
    call poll
    call drain
    INJECT INPUT_POSITION, 4, 4
    call poll
    EXPECT CWP_OBJ_POINTER, P_MOTION, surface_b, -12, -4
    NOTHING
    INJECT INPUT_BUTTON, 0, 0
    call poll
    EXPECT CWP_OBJ_POINTER, P_BUTTON, surface_b, 0, 0
    EXPECT_SHORT CWP_OBJ_POINTER, P_LEAVE, surface_b
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_a, 4, 4
    NOTHING
    PASS

; Switching seats lets go of every held key and button first
ti_release_on_switch:
    sub rsp, 8
    INJECT INPUT_POSITION, 4, 4
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_KEY, 30, 1
    call poll
    call drain
    lea rdi, [rel server]
    xor esi, esi
    call input_set_seat
    test rax, rax
    jz .fail
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_a, 30, 0
    EXPECT CWP_OBJ_POINTER, P_BUTTON, surface_a, 0, 0
    NOTHING
    INJECT INPUT_KEY, 30, 1
    cmp rax, -(ENODEV)
    jne .fail
    PASS

; A destroyed surface holds no focus and gets nothing more; the keyboard
; goes to the surface left on top, and with none left to nothing
ti_forget_surface:
    sub rsp, 8
    INJECT INPUT_POSITION, 4, 4
    INJECT INPUT_BUTTON, 0, 1
    INJECT INPUT_BUTTON, 0, 0
    call poll
    call drain
    mov eax, [rel surface_a]
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, OP_DESTROY, 4
    call poll
    EXPECT_SHORT CWP_OBJ_KEYBOARD, K_ENTER, surface_b
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_b, 0, 0
    NOTHING
    mov rax, [rel server + Server.input_seat]
    cmp qword [rax + InputSeat.pointer_focus], 0
    jne .fail
    INJECT INPUT_KEY, 30, 1
    INJECT INPUT_MOTION, 0, 0
    call poll
    EXPECT CWP_OBJ_KEYBOARD, K_KEY, surface_b, 30, 1
    EXPECT CWP_OBJ_KEYBOARD, K_TEXT, surface_b, 'a', 0
    NOTHING
    mov eax, [rel surface_b]
    mov [rel req], eax
    SEND CWP_OBJ_SURFACE, OP_DESTROY, 4
    call poll
    NOTHING
    mov rax, [rel server + Server.input_seat]
    cmp qword [rax + InputSeat.keyboard_focus], 0
    jne .fail
    PASS

; A surface that stops showing a buffer hands the keyboard on, and is told
ti_unmap:
    sub rsp, 8
    mov eax, [rel surface_b]
    mov [rel req], eax
    mov dword [rel req + 4], 0          ; no buffer
    mov qword [rel req + 8], 0
    mov qword [rel req + 16], 0
    SEND CWP_OBJ_SURFACE, OP_ATTACH, 24
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    EXPECT_SHORT CWP_OBJ_KEYBOARD, K_LEAVE, surface_b
    EXPECT_SHORT CWP_OBJ_KEYBOARD, K_ENTER, surface_a
    EXPECT CWP_OBJ_KEYBOARD, K_MODIFIERS, surface_a, 0, 0
    NOTHING
    PASS

; The queue holds INPUT_QUEUE_LEN events between turns, and counts the rest
ti_queue_full:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx                        ; accepted
    mov r12d, INPUT_QUEUE_LEN + 10
.inject:
    INJECT INPUT_MOTION, 0, 0
    test rax, rax
    jnz .refused
    inc ebx
    jmp .counted
.refused:
    cmp rax, -(ENOSPC)
    jne .bad
.counted:
    dec r12d
    jnz .inject
    cmp ebx, INPUT_QUEUE_LEN
    jne .bad
    mov rax, [rel server + Server.input_seat]
    cmp dword [rax + InputSeat.dropped], 10
    jne .bad
    call poll
    INJECT INPUT_MOTION, 0, 0           ; room again
    test rax, rax
    jnz .bad
    xor eax, eax
    add rsp, 8
    pop r12
    pop rbx
    ret
.bad:
    mov eax, 1
    add rsp, 8
    pop r12
    pop rbx
    ret

; The pointer stays on the output
ti_clamp:
    sub rsp, 8
    INJECT INPUT_POSITION, -5, 1000
    INJECT INPUT_MOTION, -10, 3
    call poll
    mov rax, [rel server + Server.input_seat]
    cmp dword [rax + InputSeat.x], 0
    jne .fail
    cmp dword [rax + InputSeat.y], 47
    jne .fail
    PASS

; An input region takes B's input to its top-left 8x8: elsewhere on B the
; pointer is over A beneath; a region not the client's is refused
ti_input_region:
    sub rsp, 8
    SEND CWP_OBJ_REGION, RG_CREATE, 0
    call poll
    call next_reply
    mov eax, [rel ans]
    mov [rel region], eax
    mov [rel req], eax
    mov dword [rel req + 4], 0
    mov dword [rel req + 8], 0
    mov dword [rel req + 12], 8
    mov dword [rel req + 16], 8
    SEND CWP_OBJ_REGION, RG_ADD, 20
    mov eax, [rel surface_b]
    mov [rel req], eax
    mov eax, [rel region]
    mov [rel req + 4], eax
    SEND CWP_OBJ_SURFACE, OP_SET_INPUT, 8
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    call drain
    INJECT INPUT_POSITION, 30, 20       ; on B, outside its region: A's
    call poll
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_a, 30, 20
    INJECT INPUT_POSITION, 18, 9        ; inside it: B's
    call poll
    EXPECT_SHORT CWP_OBJ_POINTER, P_LEAVE, surface_a
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_b, 2, 1
    NOTHING
    mov eax, [rel surface_b]            ; a handle that is no region of its
    mov [rel req], eax
    mov dword [rel req + 4], 999
    SEND CWP_OBJ_SURFACE, OP_SET_INPUT, 8
    mov dword [rel req + 4], 0
    SEND CWP_OBJ_SURFACE, OP_COMMIT, 8
    call poll
    call drain
    INJECT INPUT_POSITION, 30, 20       ; the region still holds
    call poll
    EXPECT_SHORT CWP_OBJ_POINTER, P_LEAVE, surface_b
    EXPECT CWP_OBJ_POINTER, P_ENTER, surface_a, 30, 20
    PASS

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair:           resb ChannelPair_size
hdr:            resb MsgHdr_size
surface_a:      resd 1
surface_b:      resd 1
region:         resd 1
shown:          resd 1
show_x:         resd 1
show_y:         resd 1
alignb 16
req:            resb 64
ans:            resb 256
alignb 16
heap:           resb HEAP_SIZE
