; =============================================================================
; Utkarsha OS — lib/input/input.inc
; =============================================================================
; Event records, device information and constants shared by every part of
; lib/input. The event record is the 24-byte record canvas already reads
; (lib/canvas/docs/KERNEL_NEEDS.md, step 3); the device information is the
; layout in lib/canvas/docs/utkarsha-contract.md §3.8.
; =============================================================================

%ifndef LIB_INPUT_INPUT_INC
%define LIB_INPUT_INPUT_INC

; ---- Event types (input_event.type) -----------------------------------------
; 1-5 are what canvas reads today. 6-10 are proposed in ROADMAP.md §5.2 and
; are not sent until canvas accepts them.
%define INPUT_KEY           1   ; code = keycode 0-255; value = 1 down, 0 up
%define INPUT_MOTION        2   ; code = dx; value = dy
%define INPUT_POSITION      3   ; code = x; value = y
%define INPUT_BUTTON        4   ; code = 0 left, 1 right, 2 middle; value = 1/0
%define INPUT_AXIS          5   ; code = 0 vertical, 1 horizontal; value = steps
%define INPUT_TOUCH         6
%define INPUT_PEN           7
%define INPUT_PEN_AXES      8
%define INPUT_SWITCH        9
%define INPUT_DEVICE        10

struc input_event
    .type:      resd 1
    .code:      resd 1
    .value:     resd 1
    .device:    resd 1
    .time:      resq 1          ; monotonic ns; 0 lets the receiver stamp it
endstruc                        ; 24 bytes

; ---- Device information (ut_input_device_info) --------------------------------
%define INPUT_BUS_USB       3
%define INPUT_BUS_PS2       4
%define INPUT_BUS_I2C       5
%define INPUT_BUS_PLATFORM  6
%define INPUT_BUS_BLUETOOTH 7
%define INPUT_BUS_VIRTUAL   8

%define INPUT_CAP_KEYBOARD  (1 << 0)
%define INPUT_CAP_POINTER   (1 << 1)
%define INPUT_CAP_TOUCH     (1 << 2)
%define INPUT_CAP_TABLET    (1 << 3)

struc input_dev_info
    .id:        resd 1
    .pad0:      resd 1
    .name:      resq 1          ; NUL-terminated
    .bus:       resd 1          ; INPUT_BUS_*
    .vendor:    resw 1
    .product:   resw 1
    .version:   resw 1
    .pad1:      resw 3
    .caps:      resq 1          ; INPUT_CAP_*
    .max_x:     resd 1
    .max_y:     resd 1
    .res_x:     resd 1          ; units per mm
    .res_y:     resd 1
endstruc                        ; 56 bytes

; ---- Internal device record ----------------------------------------------------
%define INPUT_MAX_DEVICES   32
%define INPUT_NAME_MAX      32  ; bytes, including the NUL

%define INPUT_DEV_PRESENT   (1 << 0)
%define INPUT_DEV_GRABBED   (1 << 1)

struc input_dev
    .info:      resb input_dev_info_size    ; first, so &dev == &info
    .flags:     resd 1
    .events:    resd 1                      ; events posted
    .name:      resb INPUT_NAME_MAX
endstruc

; ---- Event ring ------------------------------------------------------------------
%define INPUT_RING_LEN      256 ; a power of two

; ---- Errors (negative in RAX) --------------------------------------------------------
%define INPUT_EIO           5
%define INPUT_EBUSY         16
%define INPUT_ENODEV        19
%define INPUT_EINVAL        22
%define INPUT_ENOSPC        28

; ---- Keycodes used by the drivers ---------------------------------------------------
%define KEY_CAPSLOCK        58
%define KEY_NUMLOCK         69
%define KEY_SCROLLLOCK      70
%define KEY_PAUSE           119

%endif ; LIB_INPUT_INPUT_INC
