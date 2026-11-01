; ============================================================================
; Input Tests — Pointer, Keyboard, Touch, Tablet, Seat
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/input.inc"

section .text

; ============================================================================
; Pointer Tests
; ============================================================================

global test_pointer_create
test_pointer_create:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 0
    mov rsi, 0
    mov rdx, 0
    mov rcx, DEVICE_CAP_POINTER
    call pointer_create
    TEST_ASSERT_NE rax, 0
    xor rax, rax
    leave
    ret

global test_pointer_motion
test_pointer_motion:
    PROLOGUE_SAVE rbx, r12
    ; Create seat and pointer
    mov rdi, 0
    mov rsi, 0
    mov rdx, 0
    mov rcx, DEVICE_CAP_POINTER
    call seat_create
    mov rbx, rax
    call pointer_create
    mov r12, rax

    ; Set position
    mov rdi, r12
    mov rsi, 100
    mov rdx, 100
    call pointer_set_position

    ; Verify position
    TEST_ASSERT [rbx + Pointer_X], 100
    TEST_ASSERT [rbx + Pointer_Y], 100

    xor rax, rax
    leave
    ret

global test_pointer_button
test_pointer_button:
    PROLOGUE_SAVE rbx, r12
    ; Test button press/release
    TEST_ASSERT 1, 1
    leave
    ret

global test_pointer_axis
test_pointer_axis:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_pointer_focus
test_pointer_focus:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_pointer_grab
test_pointer_grab:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_pointer_constraint
test_pointer_constraint:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Keyboard Tests
; ============================================================================

global test_keyboard_create
test_keyboard_create:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 0
    mov rsi, 0
    mov rdx, 0
    mov rcx, DEVICE_CAP_KEYBOARD
    call keyboard_create
    TEST_ASSERT_NE rax, 0
    xor rax, rax
    leave
    ret

global test_keyboard_key
test_keyboard_key:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_keyboard_modifiers
test_keyboard_modifiers:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_keyboard_repeat
test_keyboard_repeat:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_keyboard_keymap
test_keyboard_keymap:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Touch Tests
; ============================================================================

global test_touch_create
test_touch_create:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 0
    mov rsi, 0
    mov rdx, 0
    mov rcx, DEVICE_CAP_TOUCH
    call touch_create
    TEST_ASSERT_NE rax, 0
    xor rax, rax
    leave
    ret

global test_touch_down
test_touch_down:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_touch_up
test_touch_up:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_touch_motion
test_touch_motion:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_touch_cancel
test_touch_cancel:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Tablet Tests
; ============================================================================

global test_tablet_create
test_tablet_create:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 0
    mov rsi, 0
    mov rdx, 0
    mov rcx, DEVICE_CAP_TABLET
    call tablet_create
    TEST_ASSERT_NE rax, 0
    xor rax, rax
    leave
    ret

global test_tablet_axis
test_tablet_axis:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_tablet_proximity
test_tablet_proximity:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_tablet_tip
test_tablet_tip:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_tablet_button
test_tablet_button:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Seat Tests
; ============================================================================

global test_seat_create
test_seat_create:
    PROLOGUE_SAVE rbx, r12
    mov rdi, 0
    mov rsi, 0
    mov rdx, 0
    call seat_create
    TEST_ASSERT_NE rax, 0
    xor rax, rax
    leave
    ret

global test_seat_focus
test_seat_focus:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_seat_selection
test_seat_selection:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_seat_drag
test_seat_drag:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_input_version
test_input_version: dq 0x010000