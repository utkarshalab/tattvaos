; ============================================================================
; Canvas Protocol Definitions — Wire Format, Opcodes, Message Types
; ============================================================================

%ifndef __PROTOCOL_INC__
%define __PROTOCOL_INC__

; ============================================================================
; Protocol Version
; ============================================================================
%define PROTOCOL_VERSION_MAJOR  1
%define PROTOCOL_VERSION_MINOR  0
%define PROTOCOL_VERSION        ((PROTOCOL_VERSION_MAJOR << 16) | PROTOCOL_VERSION_MINOR)

; ============================================================================
; Message Header (16 bytes)
; ============================================================================
%define MESSAGE_HEADER_SIZE     16
%define MESSAGE_SIZE_OFFSET     0      ; uint32
%define MESSAGE_OPCODE_OFFSET   4      ; uint16
%define MESSAGE_FLAGS_OFFSET    6      ; uint16
%define MESSAGE_SENDER_OFFSET   8      ; uint32 (client_id)
%define MESSAGE_SEQUENCE_OFFSET 12     ; uint32

; Message flags
%define MESSAGE_FLAG_REPLY      (1 << 0)
%define MESSAGE_FLAG_EVENT      (1 << 1)
%define MESSAGE_FLAG_ERROR      (1 << 2)
%define MESSAGE_FLAG_NEEDS_ACK  (1 << 3)
%define MESSAGE_FLAG_HAS_FDS    (1 << 4)
%define MESSAGE_FLAG_COMPRESSED (1 << 5)

; ============================================================================
; Object IDs
; ============================================================================
%define OBJECT_ID_NULL          0
%define OBJECT_ID_DISPLAY       1
%define OBJECT_ID_SURFACE       2
%define OBJECT_ID_REGION        3
%define OBJECT_ID_CALLBACK      4
%define OBJECT_ID_SEAT          5
%define OBJECT_ID_POINTER       6
%define OBJECT_ID_KEYBOARD      7
%define OBJECT_ID_TOUCH         7
%define OBJECT_ID_OUTPUT        8
%define OBJECT_ID_REGION        9
%define OBJECT_ID_BUFFER        10
%define OBJECT_ID_DATA_SOURCE   11
%define OBJECT_ID_SHELL_SURFACE 12
%define OBJECT_ID_LAYER_SURFACE 13
%define OBJECT_ID_POPUP         14
%define OBJECT_ID_TEXT_INPUT    15
%define OBJECT_ID_DATA_DEVICE   16
%define OBJECT_ID_DRAG          17
%define OBJECT_ID_LAYER         18
%define OBJECT_ID_LAYER_SHELL   19
%define OBJECT_ID_TEXT_INPUT    20

; ============================================================================
; Interface IDs
; ============================================================================
%define INTERFACE_DISPLAY       1
%define INTERFACE_SURFACE       2
%define INTERFACE_REGION        3
%define INTERFACE_CALLBACK      4
%define INTERFACE_SEAT          5
%define INTERFACE_POINTER       6
%define INTERFACE_KEYBOARD      7
%define INTERFACE_TOUCH         7
%define INTERFACE_OUTPUT        8
%define INTERFACE_REGION        9
%define INTERFACE_BUFFER        10
%define INTERFACE_DATA_SOURCE   11
%define INTERFACE_SHELL_SURFACE 12
%define INTERFACE_LAYER_SURFACE 13
%define INTERFACE_POPUP         14
%define INTERFACE_TEXT_INPUT    15
%define INTERFACE_DATA_DEVICE   16
%define INTERFACE_DRAG          17
%define INTERFACE_LAYER         18
%define INTERFACE_LAYER_SHELL   19
%define INTERFACE_TEXT_INPUT    20

; ============================================================================
; Display Opcodes (1-255)
; ============================================================================
%define DISPLAY_SYNC            1
%define DISPLAY_GET_REGISTRY    2
%define DISPLAY_CREATE_SURFACE  3
%define DISPLAY_CREATE_REGION   3
%define DISPLAY_CREATE_SEAT     4

; ============================================================================
; Surface Opcodes (1-255)
; ============================================================================
%define SURFACE_DESTROY         1
%define SURFACE_ATTACH          2
%define SURFACE_DAMAGE          3
%define SURFACE_FRAME           4
%define SURFACE_SET_OPAQUE      4
%define SURFACE_SET_INPUT       5
%define SURFACE_COMMIT          6
%define SURFACE_SET_BUFFER_TRANSFORM 7
%define SURFACE_SET_BUFFER_SCALE 8
%define SURFACE_DAMAGE_BUFFER   9
%define SURFACE_OFFSET          10

; ============================================================================
; Region Opcodes
; ============================================================================
%define REGION_DESTROY          1
%define REGION_ADD              2
%define REGION_SUBTRACT         3

; ============================================================================
; Callback Opcodes
; ============================================================================
%define CALLBACK_DESTROY        1
%define CALLBACK_DONE           1

; ============================================================================
; Seat Opcodes
; ============================================================================
%define SEAT_GET_POINTER        1
%define SEAT_GET_KEYBOARD       2
%define SEAT_GET_TOUCH          3

; ============================================================================
; Pointer Opcodes
; ============================================================================
%define POINTER_SET_CURSOR      1
%define POINTER_RELEASE         2

; ============================================================================
; Keyboard Opcodes
; ============================================================================
%define KEYBOARD_RELEASE        1
%define KEYBOARD_KEY            2
%define KEYBOARD_MODIFIERS      3
%define KEYBOARD_REPEAT_INFO    3

; ============================================================================
; Touch Opcodes
; ============================================================================
%define TOUCH_DOWN              1
%define TOUCH_UP                2
%define TOUCH_MOTION            2
%define TOUCH_CANCEL            3
%define TOUCH_FRAME             4

; ============================================================================
; Output Opcodes
; ============================================================================
%define OUTPUT_RELEASE          1
%define OUTPUT_MODE             2

; ============================================================================
; Shell Surface Opcodes
; ============================================================================
%define SHELL_SURFACE_SET_TITLE       1
%define SHELL_SURFACE_SET_CLASS       2
%define SHELL_SURFACE_SET_TRANSIENT   2
%define SHELL_SURFACE_SET_FULLSCREEN  3
%define SHELL_SURFACE_SET_POPUP       3
%define SHELL_SURFACE_SET_MAXIMIZED   4
%define SHELL_SURFACE_SET_MINIMIZED   5
%define SHELL_SURFACE_ACK_CONFIGURE   6

; ============================================================================
; Layer Surface Opcodes
; ============================================================================
%define LAYER_SURFACE_DESTROY     1
%define LAYER_SURFACE_SET_LAYER   1
%define LAYER_SURFACE_SET_SIZE    2
%define LAYER_SURFACE_SET_ANCHOR  3
%define LAYER_SURFACE_SET_EXCLUSIVE_ZONE 3
%define LAYER_SURFACE_SET_KEYBOARD_INTERACTIVITY 4
%define LAYER_SURFACE_SET_MARGIN  5

; ============================================================================
; Popup Opcodes
; ============================================================================
%define POPUP_DESTROY           1
%define POPUP_SET_POSITION      1
%define POPUP_SET_SIZE          2
%define POPUP_SET_CONSTRAIN     3

; ============================================================================
; Data Device Opcodes
; ============================================================================
%define DATA_DEVICE_START_DRAG     1
%define DATA_DEVICE_SET_SELECTION  2
%define DATA_DEVICE_RELEASE        3

; ============================================================================
; Data Source Opcodes
; ============================================================================
%define DATA_SOURCE_OFFER       1
%define DATA_SOURCE_DESTROY     2
%define DATA_SOURCE_SET_ACTIONS 2
%define DATA_SOURCE_SEND        3

; ============================================================================
; Drag Opcodes
; ============================================================================
%define DRAG_DESTROY            1
%define DRAG_ACTION             2
%define DRAG_DROP               2
%define DRAG_CANCEL             3

; ============================================================================
; Text Input Opcodes
; ============================================================================
%define TEXT_INPUT_ENABLE       1
%define TEXT_INPUT_DISABLE      2
%define TEXT_INPUT_COMMIT       1
%define TEXT_INPUT_PREEDIT      2
%define TEXT_INPUT_DELETE_SURROUNDING 3
%define TEXT_INPUT_KEYSYM       4
%define TEXT_INPUT_SET_CURSOR   4
%define TEXT_INPUT_SET_CONTENT_TYPE 4
%define TEXT_INPUT_SET_CONTENT_HINT 5
%define TEXT_INPUT_SET_SURROUNDING 6
%define TEXT_INPUT_RESET        6
%define TEXT_INPUT_KEYSYM       5

; ============================================================================
; Text Input Events (Server -> Client)
; ============================================================================
%define TEXT_INPUT_EVENT_ENTER         1
%define TEXT_INPUT_EVENT_LEAVE         2
%define TEXT_INPUT_EVENT_PREEDIT       3
%define TEXT_INPUT_EVENT_COMMIT        4
%define TEXT_INPUT_EVENT_DELETE        5
%define TEXT_INPUT_EVENT_KEYSYM        6
%define TEXT_INPUT_EVENT_CURSOR        7
%define TEXT_INPUT_EVENT_PREEDIT_START 8
%define TEXT_INPUT_EVENT_PREEDIT_END   9

; ============================================================================
; Shell Events (Server -> Client)
; ============================================================================
%define SHELL_EVENT_CONFIGURE      1
%define SHELL_EVENT_CLOSE          2
%define SHELL_EVENT_CLOSED         2
%define SHELL_EVENT_CONFIGURE_DONE 3
%define SHELL_EVENT_CLOSE_COMPLETE 4

; ============================================================================
; Layer Shell Events
; ============================================================================
%define LAYER_SHELL_EVENT_CONFIGURE    1
%define LAYER_SHELL_EVENT_CLOSED       2

; ============================================================================
; Layer Events
; ============================================================================
%define LAYER_EVENT_CONFIGURE    1
%define LAYER_EVENT_CLOSED       2

; ============================================================================
; Popup Events
; ============================================================================
%define POPUP_EVENT_CONFIGURE    1
%define POPUP_EVENT_DONE         2

; ============================================================================
; Seat Events (Server -> Client)
; ============================================================================
%define SEAT_EVENT_POINTER_ENTER    1
%define SEAT_EVENT_POINTER_LEAVE    2
%define SEAT_EVENT_POINTER_MOTION   2
%define SEAT_EVENT_POINTER_BUTTON   3
%define SEAT_EVENT_POINTER_AXIS     3
%define SEAT_EVENT_KEYBOARD_ENTER   4
%define SEAT_EVENT_KEYBOARD_LEAVE   5
%define SEAT_EVENT_KEYBOARD_KEY     6
%define SEAT_EVENT_KEYBOARD_MODIFIERS 6
%define SEAT_EVENT_TOUCH_DOWN       7
%define SEAT_EVENT_TOUCH_UP         8
%define SEAT_EVENT_TOUCH_MOTION     8
%define SEAT_EVENT_TOUCH_CANCEL     9
%define SEAT_EVENT_TOUCH_FRAME      10

; ============================================================================
; Pointer Events
; ============================================================================
%define POINTER_EVENT_ENTER     1
%define POINTER_EVENT_LEAVE     2
%define POINTER_EVENT_MOTION    3
%define POINTER_EVENT_BUTTON    4
%define POINTER_EVENT_AXIS      5
%define POINTER_EVENT_AXIS_SOURCE 5
%define POINTER_EVENT_AXIS_DISCRETE 6
%define POINTER_EVENT_AXIS_STOP 7
%define POINTER_EVENT_AXIS_DISCRETE 8

; ============================================================================
; Keyboard Events
; ============================================================================
%define KEYBOARD_EVENT_KEY        1
%define KEYBOARD_EVENT_MODIFIERS  2
%define KEYBOARD_EVENT_REPEAT_INFO 3

; ============================================================================
; Touch Events
; ============================================================================
%define TOUCH_EVENT_DOWN       1
%define TOUCH_EVENT_UP         2
%define TOUCH_EVENT_MOTION     3
%define TOUCH_EVENT_CANCEL     4
%define TOUCH_EVENT_FRAME      4

; ============================================================================
; Data Device Events
; ============================================================================
%define DATA_DEVICE_EVENT_OFFER        1
%define DATA_DEVICE_EVENT_ENTER        2
%define DATA_DEVICE_EVENT_LEAVE        3
%define DATA_DEVICE_EVENT_MOTION       3
%define DATA_DEVICE_EVENT_DROP         4
%define DATA_DEVICE_EVENT_SELECTION    5
%define DATA_DEVICE_EVENT_DATA_SOURCE  6
%define DATA_DEVICE_EVENT_ACTION       6

; ============================================================================
; Data Source Events
; ============================================================================
%define DATA_SOURCE_EVENT_TARGET      1
%define DATA_SOURCE_EVENT_SEND        2
%define DATA_SOURCE_EVENT_CANCELLED   3
%define DATA_SOURCE_EVENT_DND_DROP    3
%define DATA_SOURCE_EVENT_DND_FINISH  4
%define DATA_SOURCE_EVENT_ACTION      4

; ============================================================================
; Drag Events
; ============================================================================
%define DRAG_EVENT_OFFER        1
%define DRAG_EVENT_ENTER        2
%define DRAG_EVENT_LEAVE        3
%define DRAG_EVENT_MOTION       3
%define DRAG_EVENT_DROP         4
%define DRAG_EVENT_ACTION       5

; ============================================================================
; Text Input Events
; ============================================================================
%define TEXT_INPUT_EVENT_ENTER          1
%define TEXT_INPUT_EVENT_LEAVE          2
%define TEXT_INPUT_EVENT_PREEDIT_STRING 3
%define TEXT_INPUT_EVENT_COMMIT_STRING  4
%define TEXT_INPUT_EVENT_DELETE_SURROUNDING 4
%define TEXT_INPUT_EVENT_KEYSYM         5
%define TEXT_INPUT_EVENT_CURSOR         6
%define TEXT_INPUT_EVENT_PREEDIT_START  7
%define TEXT_INPUT_EVENT_PREEDIT_END    8

; ============================================================================
; Errors
; ============================================================================
%define ERROR_INVALID_OBJECT      1
%define ERROR_INVALID_METHOD     2
%define ERROR_INVALID_ARGUMENT   3
%define ERROR_INVALID_FORMAT     4
%define ERROR_NO_MEMORY          5
%define ERROR_IMPLEMENTATION     6
%define ERROR_OBJECT_DESTROYED   7
%define ERROR_POST_REJECTED      8
%define ERROR_OBJECT_DEAD        9

; ============================================================================
; Message Helper Macros
; ============================================================================

%macro MSG_HEADER 4
    %1:  dw %2              ; size
         dw %3              ; opcode
         dw %4              ; flags
         dd %5              ; sender_id
         dd 0               ; sequence (filled by sender)
%endmacro

%macro MSG_EVENT 3
    ; event: size, opcode, flags, sender_id
    dw %1 + MESSAGE_HEADER_SIZE
    dw %2
    dw %3
    dd %4
    dd 0
%endmacro

%endif ; __PROTOCOL_INC__