; ============================================================================
; Unit Test — the Login Screen (src/session/greeter.asm)
; ============================================================================
; test_greeter_suite -> eax = failed cases (each case returns 0 / 1).
; A server on 400x80 with a greeter, a few turns after it started. A turn is
; server_poll then greeter_step, as in canvasd's loop. Keys go in through
; virtual_input_inject; the cases look at what the greeter drew in its buffer
; and what it kept of the text.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/event.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/greeter.inc"

extern arena_init
extern greeter_done
extern greeter_set_idle
extern handle_resolve
extern greeter_set_verify
extern greeter_start
extern login_reset
extern login_verify
extern ui_text_init
extern greeter_step
extern server_init
extern server_poll
extern virtual_input_inject

%define HEAP_SIZE (8 * 1024 * 1024)
%define WIDTH     400
%define HEIGHT    160                 ; room for the label and the names

; The field on this screen
%define FX        ((WIDTH - GREETER_FIELD_W) / 2)
%define FY        ((HEIGHT - GREETER_FIELD_H) / 2)
%define DOT_Y     (FY + (GREETER_FIELD_H - GREETER_DOT) / 2 + 2)
%define CARET_Y   (FY + (GREETER_FIELD_H - GREETER_CARET_H) / 2 + 2)
%define DOT_X(n)  (FX + GREETER_PAD + (n) * GREETER_DOT_STEP)

%define KEY_A       30
%define KEY_B       48
%define KEY_ESC     1
%define KEY_BS      14
%define KEY_ENTER   28

section .text

global test_greeter_suite
test_greeter_suite:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tg_shown
    CASE tg_label
    CASE tg_typing
    CASE tg_wrong
    CASE tg_right
    CASE tg_login
    CASE tg_lockout
    CASE tg_lock_key
    CASE tg_lid_lock
    CASE tg_idle_lock
    CASE tg_locked_keys
    CASE tg_users
    call tg_too_small
    add ebx, eax
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

; inject a key: keycode, state
%macro INJECT_KEY 2
    lea rdi, [rel server]
    mov esi, INPUT_KEY
    mov edx, %1
    mov ecx, %2
    xor r8d, r8d
    call virtual_input_inject
%endmacro

; a key pressed and let go, then a turn
%macro TYPE 1
    mov esi, %1
    call type_key
%endmacro

; the pixel at x, y of the greeter's buffer is colour
%macro PIXEL 3
    mov edi, %1
    mov esi, %2
    call pixel
    cmp eax, %3
    jne .fail
%endmacro

; a started server with a greeter, shown
fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    mov edx, WIDTH
    mov ecx, HEIGHT
    xor r8d, r8d
    call server_init
    lea rdi, [rel arena]
    call ui_text_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call greeter_start
    mov [rel greeter], rax
    call poll
    call poll
    call poll
    add rsp, 8
    ret

poll:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    mov rdi, [rel server + Server.greeter]
    test rdi, rdi
    jz .out
    call greeter_step
.out:
    add rsp, 8
    ret

; esi = keycode: down, up, a turn
type_key:
    push rbx
    mov ebx, esi
    lea rdi, [rel server]
    mov esi, INPUT_KEY
    mov edx, ebx
    mov ecx, 1
    xor r8d, r8d
    call virtual_input_inject
    lea rdi, [rel server]
    mov esi, INPUT_KEY
    mov edx, ebx
    xor ecx, ecx
    xor r8d, r8d
    call virtual_input_inject
    call poll
    pop rbx
    ret

; edi = x, esi = y -> eax = the greeter's pixel there
pixel:
    mov rax, [rel greeter]
    mov ecx, [rax + Greeter.stride]
    imul esi, ecx
    mov rax, [rax + Greeter.pixels]
    add rax, rsi
    mov eax, [rax + rdi * 4]
    ret

; rdi = text, esi = length -> rax 0 for "ab"
verify_ab:
    mov eax, 1
    cmp esi, 2
    jne .out
    cmp word [rdi], 'ab'
    jne .out
    xor eax, eax
.out:
    ret

; ---------------------------------------------------------------------------
; Cases
; ---------------------------------------------------------------------------

; Shown, with the keyboard: background, an empty field, the caret
tg_shown:
    sub rsp, 8
    mov rax, [rel greeter]
    test rax, rax
    js .fail
    cmp dword [rax + Greeter.state], GREETER_SHOWN
    jne .fail
    mov rcx, [rel server + Server.input_seat]
    cmp qword [rcx + InputSeat.keyboard_focus], 0
    je .fail
    mov rcx, [rel server + Server.stack]
    test rcx, rcx
    jz .fail
    PIXEL 0, 0, GREETER_BG
    PIXEL WIDTH - 1, HEIGHT - 1, GREETER_BG
    PIXEL FX, FY, GREETER_BORDER
    PIXEL FX + 4, FY + 4, GREETER_FIELD
    PIXEL DOT_X(0), CARET_Y, GREETER_INK
    PIXEL DOT_X(0) + GREETER_CARET_W, CARET_Y, GREETER_FIELD
    PASS

; "Password" above the field: ink in the label's box, the background left
; and right of the field
%define LABEL_Y   (FY - GREETER_LABEL_GAP - GREETER_LABEL_H)
tg_label:
    sub rsp, 8
    xor ecx, ecx                        ; ink found
    mov esi, LABEL_Y
.row:
    mov edi, FX
.col:
    push rcx
    push rsi
    push rdi
    sub rsp, 8
    call pixel
    add rsp, 8
    pop rdi
    pop rsi
    pop rcx
    cmp eax, GREETER_BG
    je .bg
    inc ecx
.bg:
    inc edi
    cmp edi, FX + GREETER_FIELD_W
    jb .col
    inc esi
    cmp esi, FY - GREETER_LABEL_GAP
    jb .row
    cmp ecx, 20
    jb .fail
    PIXEL FX - 1, LABEL_Y + 10, GREETER_BG
    PASS

; A dot a character, the caret after them; Backspace takes one back, Esc all
tg_typing:
    sub rsp, 8
    TYPE KEY_A
    TYPE KEY_B
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.len], 2
    jne .fail
    cmp word [rax + Greeter.text], 'ab'
    jne .fail
    PIXEL DOT_X(0) + 5, DOT_Y, GREETER_INK
    PIXEL DOT_X(1) + 5, DOT_Y, GREETER_INK
    PIXEL DOT_X(2), CARET_Y, GREETER_INK
    TYPE KEY_BS
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.len], 1
    jne .fail
    cmp byte [rax + Greeter.text + 1], 0
    jne .fail
    PIXEL DOT_X(1), CARET_Y, GREETER_INK
    PIXEL DOT_X(1) + 5, DOT_Y, GREETER_FIELD
    PIXEL DOT_X(2), CARET_Y, GREETER_FIELD
    TYPE KEY_ESC
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.len], 0
    jne .fail
    PIXEL DOT_X(0) + 5, DOT_Y, GREETER_FIELD
    PASS

; With no verify hook every password is wrong: wiped, and the edge goes red
; until the next key
tg_wrong:
    sub rsp, 8
    TYPE KEY_A
    TYPE KEY_ENTER
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.len], 0
    jne .fail
    cmp byte [rax + Greeter.text], 0
    jne .fail
    cmp dword [rax + Greeter.failed], 1
    jne .fail
    PIXEL FX, FY, GREETER_FAILED
    TYPE KEY_B
    PIXEL FX, FY, GREETER_BORDER
    PASS

; The right password ends the greeter and its surface goes; a wrong one first
; does not
tg_right:
    sub rsp, 8
    mov rdi, [rel greeter]
    lea rsi, [rel verify_ab]
    call greeter_set_verify
    TYPE KEY_A
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jnz .fail
    TYPE KEY_A
    TYPE KEY_B
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jz .fail
    mov rax, [rel greeter]
    cmp word [rax + Greeter.text], 0
    jne .fail
    call poll
    call greeter_surface                ; on, but showing nothing
    cmp qword [rax + Surface.current + SurfaceState.buffer], 0
    jne .fail
    cmp qword [rel server + Server.locked], 0
    jne .fail
    PASS

; "secret", the host's password, letter by letter
type_secret:
    sub rsp, 8
    TYPE 31                             ; s
    TYPE 18                             ; e
    TYPE 46                             ; c
    TYPE 19                             ; r
    TYPE 18                             ; e
    TYPE 20                             ; t
    add rsp, 8
    ret

; Through login_verify the kernel's check decides: a wrong password is
; refused, the right one lets the user in (ravi, the host's second user)
tg_login:
    sub rsp, 8
    call login_reset
    mov rdi, [rel greeter]
    lea rsi, [rel login_verify]
    call greeter_set_verify
    TYPE 106                            ; Right: ravi
    TYPE KEY_A
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jnz .fail
    call type_secret
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jz .fail
    PASS

; Three wrong in a row: then even the right one is refused for a while
tg_lockout:
    sub rsp, 8
    call login_reset
    mov rdi, [rel greeter]
    lea rsi, [rel login_verify]
    call greeter_set_verify
    TYPE KEY_A
    TYPE KEY_ENTER
    TYPE KEY_A
    TYPE KEY_ENTER
    TYPE KEY_A
    TYPE KEY_ENTER
    call type_secret
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jnz .fail                           ; locked out
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.failed], 1
    jne .fail
    call login_reset
    PASS

; -> rax = the greeter's Surface*
greeter_surface:
    sub rsp, 8
    mov rax, [rel greeter]
    mov esi, [rax + Greeter.surface]
    mov rdi, [rel server + Server.surface_table]
    call handle_resolve
    add rsp, 8
    ret

; logged in with "ab" through verify_ab, the idle lock off
unlocked:
    sub rsp, 8
    mov rdi, [rel greeter]
    xor esi, esi
    call greeter_set_idle
    mov rdi, [rel greeter]
    lea rsi, [rel verify_ab]
    call greeter_set_verify
    TYPE KEY_A
    TYPE KEY_B
    TYPE KEY_ENTER
    call poll
    add rsp, 8
    ret

; the login screen is up again: a buffer shown, the keyboard, locked, an
; empty field; .fail if not
%macro LOCKED 0
    call greeter_surface
    cmp qword [rax + Surface.current + SurfaceState.buffer], 0
    je .fail
    mov rcx, [rel server + Server.input_seat]
    cmp [rcx + InputSeat.keyboard_focus], rax
    jne .fail
    cmp qword [rel server + Server.locked], 1
    jne .fail
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.len], 0
    jne .fail
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jnz .fail
%endmacro

; Super+L brings it back; the right password again puts the desktop back
tg_lock_key:
    sub rsp, 8
    call unlocked
    cmp qword [rel server + Server.locked], 0
    jne .fail
    INJECT_KEY 125, 1                   ; Super
    INJECT_KEY 38, 1                    ; L
    INJECT_KEY 38, 0
    INJECT_KEY 125, 0
    call poll
    call poll
    LOCKED
    TYPE KEY_A
    TYPE KEY_B
    TYPE KEY_ENTER
    call poll
    cmp qword [rel server + Server.locked], 0
    jne .fail
    PASS

; Closing the lid locks, as Super+L does; opening it does not unlock
tg_lid_lock:
    sub rsp, 8
    call unlocked
    lea rdi, [rel server]
    mov esi, INPUT_SWITCH
    mov edx, INPUT_SWITCH_LID
    mov ecx, 1                          ; closed
    xor r8d, r8d
    call virtual_input_inject
    call poll
    call poll
    LOCKED
    lea rdi, [rel server]
    mov esi, INPUT_SWITCH
    mov edx, INPUT_SWITCH_LID
    xor ecx, ecx                        ; open again
    xor r8d, r8d
    call virtual_input_inject
    call poll
    cmp qword [rel server + Server.locked], 1
    jne .fail
    TYPE KEY_A
    TYPE KEY_B
    TYPE KEY_ENTER
    call poll
    cmp qword [rel server + Server.locked], 0
    jne .fail
    PASS

; Without input for the idle time it locks by itself
tg_idle_lock:
    sub rsp, 8
    call unlocked
    mov rdi, [rel greeter]
    mov esi, 1                          ; a nanosecond: due at once
    call greeter_set_idle
    call poll
    call poll
    LOCKED
    PASS

; While it is up the server's shortcuts do nothing: Super+2 shows no other
; workspace
tg_locked_keys:
    sub rsp, 8
    INJECT_KEY 125, 1
    INJECT_KEY 3, 1
    INJECT_KEY 3, 0
    INJECT_KEY 125, 0
    call poll
    cmp qword [rel server + Server.workspace], 0
    jne .fail
    PASS

; The kernel's users as a row of names, the chosen one on the field's
; colour; Left and Right choose; the password is checked as the chosen
; user's: mira has none, ravi's is "secret"
%define NAMES_Y   (FY - 2 * (GREETER_LABEL_H + GREETER_LABEL_GAP))
%define NAME_X(n) (FX + (n) * (GREETER_NAME_W + GREETER_NAME_GAP))
tg_users:
    sub rsp, 8
    mov rax, [rel greeter]
    cmp dword [rax + Greeter.user_count], 2
    jne .fail
    PIXEL NAME_X(0) + 1, NAMES_Y + 1, GREETER_FIELD
    PIXEL NAME_X(1) + 1, NAMES_Y + 1, GREETER_BG
    call login_reset
    mov rdi, [rel greeter]
    lea rsi, [rel login_verify]
    call greeter_set_verify
    call type_secret                    ; as mira: refused
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jnz .fail
    TYPE 106                            ; Right: ravi
    PIXEL NAME_X(0) + 1, NAMES_Y + 1, GREETER_BG
    PIXEL NAME_X(1) + 1, NAMES_Y + 1, GREETER_FIELD
    TYPE 105                            ; Left and Right again: ravi
    TYPE 106
    call type_secret
    TYPE KEY_ENTER
    mov rdi, [rel greeter]
    call greeter_done
    test eax, eax
    jz .fail
    call login_reset
    PASS

; A screen narrower than the field gets no greeter
tg_too_small:
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
    lea rsi, [rel arena]
    call greeter_start
    cmp rax, -(EINVAL)
    jne .fail
    cmp qword [rel server + Server.greeter], 0
    jne .fail
    PASS

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
greeter:        resq 1
alignb 16
heap:           resb HEAP_SIZE
