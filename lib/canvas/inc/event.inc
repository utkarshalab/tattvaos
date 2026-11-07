; ============================================================================
; Event — Input Event Structure and Types
; ============================================================================

%ifndef __EVENT_INC__
%define __EVENT_INC__

%define EVENT_SIZE    24

struc Event
    .type:  resd 1
    .time:  resq 1
    .a:     resd 1
    .b:     resd 1
    .c:     resd 1
endstruc

; Event Types
%define EVENT_NONE          0

; Keyboard Events
%define EVENT_KEY_PRESS     1
%define EVENT_KEY_RELEASE   2
%define EVENT_KEY_REPEAT    3

; Pointer Events
%define EVENT_POINTER_MOTION        10
%define EVENT_POINTER_BUTTON_PRESS  11
%define EVENT_POINTER_BUTTON_RELEASE 12
%define EVENT_POINTER_AXIS          13
%define EVENT_POINTER_ENTER         14
%define EVENT_POINTER_LEAVE         15

; Touch Events
%define EVENT_TOUCH_DOWN    20
%define EVENT_TOUCH_UP      21
%define EVENT_TOUCH_MOTION  22
%define EVENT_TOUCH_CANCEL  23
%define EVENT_TOUCH_FRAME   24

; Tablet Events
%define EVENT_TABLET_TOOL_PROXIMITY   30
%define EVENT_TABLET_TOOL_TIP         31
%define EVENT_TABLET_TOOL_BUTTON      32
%define EVENT_TABLET_PAD_BUTTON       33
%define EVENT_TABLET_PAD_RING         34
%define EVENT_TABLET_PAD_STRIP        35

; Keyboard Events (legacy)
%define INPUT_EVENT_KEY       1
%define INPUT_EVENT_REL       2
%define INPUT_EVENT_ABS       3
%define INPUT_EVENT_SYN       4

; Event Field Mapping:
; EVENT_KEY_PRESS/RELEASE:  a=keycode, b=keysym, c=modifiers
; EVENT_POINTER_MOTION:     a=x, b=y, c=surface
; EVENT_POINTER_BUTTON_PRESS/RELEASE: a=button, b=x, c=y
; EVENT_POINTER_AXIS:       a=axis, b=value, c=discrete
; EVENT_TOUCH_DOWN/UP/MOTION: a=slot, b=x, c=y
%define INPUT_EVENT_KEY       1
%define INPUT_EVENT_REL       2
%define INPUT_EVENT_ABS       3
%define INPUT_EVENT_SYN       4

; Modifier masks (cw_keyboard modifiers and text events)
%define MOD_SHIFT        (1 << 0)
%define MOD_CAPS         (1 << 1)
%define MOD_CTRL         (1 << 2)
%define MOD_ALT          (1 << 3)
%define MOD_SUPER        (1 << 4)
%define MOD_NUM          (1 << 5)
%define MOD_LOGO         (1 << 6)

; Raw input (RawInput.type): what a source hands input_submit
%define INPUT_KEY           1   ; code = keycode 0-255; value = 1 down, 0 up
%define INPUT_MOTION        2   ; code, value = dx, dy
%define INPUT_POSITION      3   ; code, value = x, y in output pixels
%define INPUT_BUTTON        4   ; code = 0 left, 1 right, 2 middle, up to 31;
                                ; value = 1 down, 0 up
%define INPUT_AXIS          5   ; code = 0 vertical, 1 horizontal; value =
                                ; signed steps, positive down or right
; Agreed with lib/input (KERNEL_NEEDS.md step 3 has the bits); dropped until
; touch (TCH-01) and pen (TCH-10) routing reads them
%define INPUT_TOUCH         6   ; a contact: slot, phase, confidence,
                                ; pressure, size; value = x | y << 16
%define INPUT_PEN           7   ; in range, tip, buttons, tool; x | y << 16
%define INPUT_PEN_AXES      8   ; pressure, distance; tilt x, y, rotation
%define INPUT_SWITCH        9   ; code = which switch; value = 1 on, 0 off
%define INPUT_DEVICE        10  ; code = added 0, removed 1, changed 2;
                                ; value = its capability bits

%endif ; __EVENT_INC__
