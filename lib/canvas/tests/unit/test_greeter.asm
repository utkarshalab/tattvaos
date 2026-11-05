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
extern greeter_set_verify
extern greeter_start
extern ui_text_init
extern greeter_step
extern server_init
extern server_poll
extern virtual_input_inject

%define HEAP_SIZE (8 * 1024 * 1024)
%define WIDTH     400
%define HEIGHT    120                 ; room for the label

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
    mov rcx, [rel server + Server.outputs]
    mov rcx, [rcx + Output.surfaces]
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
    mov rcx, [rel server + Server.outputs]
    cmp qword [rcx + Output.surfaces], 0
    jne .fail
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
