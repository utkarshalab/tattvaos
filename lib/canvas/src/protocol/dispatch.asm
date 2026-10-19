; ============================================================================
; Canvas Protocol Handlers — Dispatch, Client Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/protocol.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; protocol_dispatch
;   Main protocol dispatch entry point
; ============================================================================
global protocol_dispatch
protocol_dispatch:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; client connection
    mov r12, rsi       ; message
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate message
    call wire_validate_message
    test rax, rax
    jnz .invalid

    ; Get object ID from message
    mov r13, [r12 + MESSAGE_SENDER_OFFSET]

    ; Resolve object
    mov rdi, [rbx + ClientConn_SERVER_CHAN]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .bad_object

    ; Get interface
    mov r12, [rax + Object_INTERFACE_ID]
    mov r14d, word [rbx + MESSAGE_OPCODE_OFFSET]

    ; Dispatch
    call protocol_dispatch_interface

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.bad_object:
    mov rax, -ENOENT
    EPILOGUE_RESTORE rbx
    ret

.invalid:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; protocol_dispatch_interface
;   Dispatch to interface-specific handler
; ============================================================================
protocol_dispatch_interface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; object
    mov r12d, esi      ; interface
    mov r13d, edx      ; opcode

    ; Interface dispatch table
    cmp r12, INTERFACE_DISPLAY
    je .display
    cmp r12, INTERFACE_SURFACE
    je .surface
    cmp r12, INTERFACE_SEAT
    je .seat
    cmp r12, INTERFACE_POINTER
    je .pointer
    cmp r12, INTERFACE_KEYBOARD
    je .keyboard
    cmp r12, INTERFACE_TOUCH
    je .touch
    cmp r12, INTERFACE_OUTPUT
    je .output
    cmp r12, INTERFACE_SHELL_SURFACE
    je .shell_surface
    cmp r12, INTERFACE_LAYER_SURFACE
    je .layer_surface
    cmp r12, INTERFACE_POPUP
    je .popup
    cmp r12, INTERFACE_DATA_DEVICE
    je .data_device
    cmp r12, INTERFACE_DATA_SOURCE
    je .data_source
    cmp r12, INTERFACE_DRAG
    je .drag
    cmp r12, INTERFACE_TEXT_INPUT
    je .text_input
    cmp r12, INTERFACE_LAYER_SURFACE
    je .layer_surface
    cmp r12, INTERFACE_LAYER
    je .layer
    cmp r12, INTERFACE_LAYER_SHELL
    je .layer_shell
    cmp r12, INTERFACE_REGION
    je .region
    cmp r12, INTERFACE_CALLBACK
    je .callback
    cmp r12, INTERFACE_BUFFER
    je .buffer
    cmp r12, INTERFACE_DATA_SOURCE
    je .data_source
    cmp r12, INTERFACE_DATA_DEVICE
    je .data_device
    cmp r12, INTERFACE_DRAG
    je .drag

    ; Unknown interface
    mov rax, -ENOTSUP
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; Interface request dispatchers
; ============================================================================

.display:
    ; Display requests
    cmp r13d, DISPLAY_SYNC
    je .display_sync
    cmp r13d, DISPLAY_GET_REGISTRY
    je .display_get_registry
    cmp r13d, DISPLAY_CREATE_SURFACE
    je .display_create_surface
    ; ... other display requests
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.display_sync:
    ; Send sync callback
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.display_get_registry:
    ; Send registry globals
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.display_create_surface:
    ; Create surface object
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.surface:
    cmp r13d, SURFACE_DESTROY
    je .surface_destroy
    cmp r13d, SURFACE_ATTACH
    je .surface_attach
    cmp r13d, SURFACE_DAMAGE
    je .surface_damage
    cmp r13d, SURFACE_FRAME
    je .surface_frame
    cmp r13d, SURFACE_COMMIT
    je .surface_commit
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.surface_destroy:
    call surface_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.surface_attach:
    ; Attach buffer
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.surface_damage:
    call surface_damage
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.surface_frame:
    ; Frame callback
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.surface_commit:
    call commit_surface
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.seat:
    cmp r13d, SEAT_GET_POINTER
    je .seat_get_pointer
    cmp r13d, SEAT_GET_KEYBOARD
    je .seat_get_keyboard
    cmp r13d, SEAT_GET_TOUCH
    je .seat_get_touch
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.seat_get_pointer:
    call seat_get_pointer
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.seat_get_keyboard:
    call seat_get_keyboard
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.seat_get_touch:
    call seat_get_touch
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.pointer:
    cmp r13d, POINTER_SET_CURSOR
    je .pointer_set_cursor
    cmp r13d, POINTER_RELEASE
    je .pointer_release
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.pointer_set_cursor:
    ; Set cursor surface
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.pointer_release:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.keyboard:
    cmp r13d, KEYBOARD_RELEASE
    je .keyboard_release
    cmp r13d, KEYBOARD_KEY
    je .keyboard_key
    cmp r13d, KEYBOARD_MODIFIERS
    je .keyboard_modifiers
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.keyboard_release:
    call keyboard_release
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.keyboard_key:
    call keyboard_key
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.keyboard_modifiers:
    call keyboard_modifiers
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.touch:
    cmp r13d, TOUCH_DOWN
    je .touch_down
    cmp r13d, TOUCH_UP
    je .touch_up
    cmp r13d, TOUCH_MOTION
    je .touch_motion
    cmp r13d, TOUCH_CANCEL
    je .touch_cancel
    cmp r13d, TOUCH_FRAME
    je .touch_frame
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.touch_down:
    call touch_down
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.touch_up:
    call touch_up
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.touch_motion:
    call touch_motion
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.touch_cancel:
    call touch_cancel
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.touch_frame:
    call touch_frame
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.output:
    cmp r13d, OUTPUT_RELEASE
    je .output_release
    cmp r13d, OUTPUT_MODE
    je .output_mode
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.output_release:
    call output_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.output_mode:
    call output_set_mode
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.shell_surface:
    cmp r13d, SHELL_SURFACE_SET_TITLE
    je .ss_set_title
    cmp r13d, SHELL_SURFACE_SET_CLASS
    je .ss_set_class
    cmp r13d, SHELL_SURFACE_SET_TRANSIENT
    je .ss_set_transient
    cmp r13d, SHELL_SURFACE_SET_FULLSCREEN
    je .ss_set_fullscreen
    cmp r13d, SHELL_SURFACE_SET_POPUP
    je .ss_set_popup
    cmp r13d, SHELL_SURFACE_SET_MAXIMIZED
    je .ss_set_maximized
    cmp r13d, SHELL_SURFACE_SET_MINIMIZED
    je .ss_set_minimized
    cmp r13d, SHELL_SURFACE_ACK_CONFIGURE
    je .ss_ack_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_title:
    ; Set title
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_class:
    ; Set class
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_transient:
    ; Set transient
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_fullscreen:
    call shell_fullscreen_toplevel
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_popup:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_maximized:
    call shell_maximize_toplevel
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ss_set_minimized:
    xor rax, rax
    EPILOGURE_RESTORE rbx
    ret

.ss_ack_configure:
    ; Acknowledge configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.layer_surface:
    cmp r13d, LAYER_SURFACE_DESTROY
    je .ls_destroy
    cmp r13d, LAYER_SURFACE_SET_LAYER
    je .ls_set_layer
    cmp r13d, LAYER_SURFACE_SET_SIZE
    je .ls_set_size
    cmp r13d, LAYER_SURFACE_SET_ANCHOR
    je .ls_set_anchor
    cmp r13d, LAYER_SURFACE_SET_EXCLUSIVE_ZONE
    je .ls_set_exclusive_zone
    cmp r13d, LAYER_SURFACE_SET_KEYBOARD_INTERACTIVITY
    je .ls_set_keyboard_interactivity
    cmp r13d, LAYER_SURFACE_SET_MARGIN
    je .ls_set_margin
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_destroy:
    call layer_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_set_layer:
    call layer_set_layer
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_set_size:
    call layer_set_size
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_set_anchor:
    call layer_set_anchor
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_set_exclusive_zone:
    call layer_set_exclusive_zone
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_set_keyboard_interactivity:
    call layer_set_keyboard_interactivity
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ls_set_margin:
    call layer_set_margin
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.popup:
    cmp r13d, POPUP_DESTROY
    je .popup_destroy
    cmp r13d, POPUP_SET_POSITION
    je .popup_set_position
    cmp r13d, POPUP_SET_SIZE
    je .popup_set_size
    cmp r13d, POPUP_SET_CONSTRAIN
    je .popup_set_constrain
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.popup_destroy:
    call popup_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.popup_set_position:
    call popup_set_position
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.popup_set_size:
    call popup_set_size
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.popup_set_constrain:
    call popup_set_constrain
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.data_device:
    cmp r13d, DATA_DEVICE_START_DRAG
    je .dd_start_drag
    cmp r13d, DATA_DEVICE_SET_SELECTION
    je .dd_set_selection
    cmp r13d, DATA_DEVICE_RELEASE
    je .dd_release
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.dd_start_drag:
    call dnd_start
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.dd_set_selection:
    call seat_set_selection
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.dd_release:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.data_source:
    cmp r13d, DATA_SOURCE_OFFER
    je .ds_offer
    cmp r13d, DATA_SOURCE_DESTROY
    je .ds_destroy
    cmp r13d, DATA_SOURCE_SET_ACTIONS
    je .ds_set_actions
    cmp r13d, DATA_SOURCE_SEND
    je .ds_send
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ds_offer:
    call data_source_offer
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ds_destroy:
    call data_source_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ds_set_actions:
    call data_source_set_actions
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ds_send:
    call data_source_send
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.drag:
    cmp r13d, DRAG_DESTROY
    je .drag_destroy
    cmp r13d, DRAG_ACTION
    je .drag_action
    cmp r13d, DRAG_DROP
    je .drag_drop
    cmp r13d, DRAG_CANCEL
    je .drag_cancel
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.drag_destroy:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.drag_action:
    call dnd_action
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.drag_drop:
    call dnd_drop
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.drag_cancel:
    call dnd_cancel
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.text_input:
    cmp r13d, TEXT_INPUT_ENABLE
    je .ti_enable
    cmp r13d, TEXT_INPUT_DISABLE
    je .ti_disable
    cmp r13d, TEXT_INPUT_COMMIT
    je .ti_commit
    cmp r13d, TEXT_INPUT_PREEDIT
    je .ti_preedit
    cmp r13d, TEXT_INPUT_DELETE_SURROUNDING
    je .ti_delete_surrounding
    cmp r13d, TEXT_INPUT_KEYSYM
    je .ti_keysym
    cmp r13d, TEXT_INPUT_SET_CURSOR
    je .ti_set_cursor
    cmp r13d, TEXT_INPUT_SET_CONTENT_TYPE
    je .ti_set_content_type
    cmp r13d, TEXT_INPUT_SET_CONTENT_HINT
    je .ti_set_content_hint
    cmp r13d, TEXT_INPUT_SET_SURROUNDING
    je .ti_set_surrounding
    cmp r13d, TEXT_INPUT_RESET
    je .ti_reset
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_enable:
    call text_input_enable
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_disable:
    call text_input_disable
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_commit:
    call text_input_commit
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_preedit:
    call text_input_set_preedit
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_delete_surrounding:
    call text_input_delete_surrounding
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_keysym:
    call text_input_keysym
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_set_cursor:
    call text_input_set_cursor
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_set_content_type:
    call text_input_set_content_type
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_set_content_hint:
    call text_input_set_content_hint
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_set_surrounding:
    call text_input_set_surrounding_text
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.ti_reset:
    call text_input_reset
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.layer_surface:
    ; Handled in layer_surface
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.layer:
    cmp r13d, LAYER_EVENT_CONFIGURE
    je .layer_configure
    cmp r13d, LAYER_EVENT_CLOSED
    je .layer_closed
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.layer_configure:
    call layer_configure
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.layer_closed:
    call layer_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.layer_shell:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.region:
    cmp r13d, REGION_DESTROY
    je .region_destroy
    cmp r13d, REGION_ADD
    je .region_add
    cmp r13d, REGION_SUBTRACT
    je .region_subtract
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.region_destroy:
    call region_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.region_add:
    call region_add
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.region_subtract:
    call region_subtract
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.callback:
    cmp r13d, CALLBACK_DESTROY
    je .callback_destroy
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.callback_destroy:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.buffer:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.data_source:
    ; Handled in data_source
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.data_device:
    ; Handled in data_device
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.drag:
    ; Handled in drag
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.region:
    ; Handled in region
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.callback:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.section .data
global protocol_dispatch_version
protocol_dispatch_version: dq 0x010000
