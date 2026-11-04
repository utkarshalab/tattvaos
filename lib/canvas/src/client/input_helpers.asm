; ============================================================================
; Client Input Helpers — Reading cw_keyboard and cw_pointer Events
; ============================================================================
; Input events carry (time: ulong, surface: handle, a: uint, b: uint)
; (proto/canvas-input.cwp); these read a and b for the event they suit. Each
; takes rdi = ClientEvent*.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

%define EV_A    (ClientEvent.data + 12)
%define EV_B    (ClientEvent.data + 16)

section .text

; ---------------------------------------------------------------------------
; canvas_input_key_is_press
;   OUT: rax = 1 for a key event that presses or repeats, else 0
; ---------------------------------------------------------------------------
global canvas_input_key_is_press
canvas_input_key_is_press:
    xor eax, eax
    cmp dword [rdi + ClientEvent.type], CANVAS_EV_KEY
    jne .out
    cmp dword [rdi + EV_B], 0
    setne al
.out:
    ret

; ---------------------------------------------------------------------------
; canvas_input_key_keysym
;   OUT: rax = a key event's keycode
; ---------------------------------------------------------------------------
global canvas_input_key_keysym
canvas_input_key_keysym:
    mov eax, [rdi + EV_A]
    ret

; ---------------------------------------------------------------------------
; canvas_input_text
;   OUT: rax = a text event's character (Unicode)
; ---------------------------------------------------------------------------
global canvas_input_text
canvas_input_text:
    mov eax, [rdi + EV_A]
    ret

; ---------------------------------------------------------------------------
; canvas_input_pointer_pos
;   An enter or motion event's position in the surface
;   IN:  rsi = x out, rdx = y out
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global canvas_input_pointer_pos
canvas_input_pointer_pos:
    mov eax, [rdi + EV_A]
    mov [rsi], eax
    mov eax, [rdi + EV_B]
    mov [rdx], eax
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; canvas_input_pointer_buttons
;   A button event's button and state
;   OUT: rax = button (0 left, 1 right, 2 middle), rdx = 1 pressed, 0 released
; ---------------------------------------------------------------------------
global canvas_input_pointer_buttons
canvas_input_pointer_buttons:
    mov eax, [rdi + EV_A]
    mov edx, [rdi + EV_B]
    ret

section .data
global canvas_input_helpers_version
canvas_input_helpers_version: dq 0x020000
