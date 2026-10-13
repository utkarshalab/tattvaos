; ============================================================================
; Client Input Helpers — Keyboard/Pointer Event Conveniences
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_input_key_is_press
canvas_input_key_is_press:
    PROLOGUE
    ASSERT_PTR rdi
    cmp dword [rdi + ClientEvent.type], 1
    sete al
    movzx rax, al
    leave
    ret

global canvas_input_key_keysym
canvas_input_key_keysym:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + ClientEvent.a]
    leave
    ret

global canvas_input_pointer_pos
canvas_input_pointer_pos:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rdx
    mov eax, [rdi + ClientEvent.a]
    mov [rsi], eax
    mov eax, [rdi + ClientEvent.b]
    mov [rdx], eax
    xor rax, rax
    leave
    ret

global canvas_input_pointer_buttons
canvas_input_pointer_buttons:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + ClientEvent.c]
    leave
    ret

section .data
global canvas_input_helpers_version
canvas_input_helpers_version: dq 0x010000
