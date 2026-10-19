; ============================================================================
; Input System Definitions — Pointer, Keyboard, Touch, Tablet
; ============================================================================

%ifndef __INPUT_INC__
%define __INPUT_INC__

%include "inc/fixed.inc"
%include "inc/geometry.inc"

; ============================================================================
; Input Device Types
; ============================================================================
%define INPUT_TYPE_POINTER     0
%define INPUT_TYPE_KEYBOARD    1
%define INPUT_TYPE_TOUCH       2
%define INPUT_TYPE_TABLET      3
%define INPUT_TYPE_SWITCH      4

; ============================================================================
; Pointer Events
; ============================================================================
%define POINTER_EVENT_MOTION    0
%define POINTER_EVENT_BUTTON    1
%define POINTER_EVENT_AXIS      2
%define POINTER_EVENT_ENTER     3
%define POINTER_EVENT_LEAVE     4

%define POINTER_BUTTON_LEFT     0x110
%define POINTER_BUTTON_RIGHT    0x111
%define POINTER_BUTTON_MIDDLE   0x112
%define POINTER_BUTTON_BACK     0x113
%define POINTER_BUTTON_FORWARD  0x114

%define POINTER_AXIS_VERTICAL   0
%define POINTER_AXIS_HORIZONTAL 1

; ============================================================================
; Keyboard Events
; ============================================================================
%define KEYBOARD_EVENT_KEY      0
%define KEYBOARD_EVENT_MODIFIERS 1

%define KEY_STATE_RELEASED      0
%define KEY_STATE_PRESSED       1
%define KEY_STATE_REPEAT        2

; Modifier masks
%define MOD_SHIFT        (1 << 0)
%define MOD_CAPS         (1 << 1)
%define MOD_CTRL         (1 << 2)
%define MOD_ALT          (1 << 3)
%define MOD_SUPER        (1 << 4)
%define MOD_NUM          (1 << 5)
%define MOD_LOGO         (1 << 6)

; ============================================================================
; Touch Events
; ============================================================================
%define TOUCH_EVENT_DOWN       0
%define TOUCH_EVENT_UP         1
%define TOUCH_EVENT_MOTION     2
%define TOUCH_EVENT_CANCEL     3

%define TOUCH_MAX_SLOTS        10

; ============================================================================
; Tablet Events
; ============================================================================
%define TABLET_EVENT_AXIS      0
%define TABLET_EVENT_PROXIMITY 1
%define TABLET_EVENT_TIP       2
%define TABLET_EVENT_BUTTON    3

%define TABLET_TOOL_PEN        0
%define TABLET_TOOL_ERASER     1
%define TABLET_TOOL_BRUSH      2
%define TABLET_TOOL_PENCIL     3
%define TABLET_TOOL_AIRBRUSH   4
%define TABLET_TOOL_FINGER     5
%define TABLET_TOOL_MOUSE      6
%define TABLET_TOOL_LENS       7

%define TABLET_AXIS_X          0
%define TABLET_AXIS_Y          1
%define TABLET_AXIS_PRESSURE   2
%define TABLET_AXIS_DISTANCE   3
%define TABLET_AXIS_TILT_X     4
%define TABLET_AXIS_TILT_Y     5
%define TABLET_AXIS_ROTATION   6
%define TABLET_AXIS_SLIDER     7
%define TABLET_AXIS_WHEEL      8

; ============================================================================
; Input Device Struct
; ============================================================================
%define InputDevice_TYPE       0
%define InputDevice_NAME       8
%define InputDevice_SEAT       16
%define InputDevice_CAPS       24
%define InputDevice_DISPATCH   32
%define InputDevice_DESTROY    40
%define InputDevice_DATA       48
%define InputDevice_NEXT       56
%define InputDevice_SIZE       64

; Device capabilities
%define DEVICE_CAP_POINTER     (1 << 0)
%define DEVICE_CAP_KEYBOARD    (1 << 1)
%define DEVICE_CAP_TOUCH       (1 << 2)
%define DEVICE_CAP_TABLET      (1 << 3)
%define DEVICE_CAP_SWITCH      (1 << 3)

; ============================================================================
; Seat
; ============================================================================
%define SEAT_POINTER        0
%define SEAT_KEYBOARD       8
%define SEAT_TOUCH          16
%define SEAT_NAME           24
%define SEAT_CAPABILITIES   32
%define SEAT_POINTER_FOCUS  40
%define SEAT_KEYBOARD_FOCUS 48
%define SEAT_DEVICES        56
%define SEAT_SELECTION      64
%define SEAT_SIZE           72

; ============================================================================
; Pointer Constraint
; ============================================================================
%define CONSTRAINT_TYPE_LOCKED   0
%define CONSTRAINT_TYPE_CONFINED 1
%define CONSTRAINT_TYPE_REGION   2

%define CONSTRAINT_LIFETIME_PERSISTENT 0
%define CONSTRAINT_LIFETIME_ONESHOT    1

%endif ; __INPUT_INC__