; ============================================================================
; Event — Input Event Structure and Types
; ============================================================================

%ifndef __EVENT_INC__
%define __EVENT_INC__

%define EVENT_SIZE    24

struc Event {
    .type:  resd 1
    .time:  resq 1
    .a:     resd 1
    .b:     resd 1
    .c:     resd 1
}

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

%endif ; __EVENT_INC__