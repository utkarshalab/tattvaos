; ============================================================================
; cwp_ops.inc — Request and Event Numbers, Shared by Server and Clients
; ============================================================================
; A message's hdr.obj is the interface (CWP_OBJ_* in cwp.inc) and hdr.opcode
; the index of the request or event in that interface, as the proto/*.cwp
; files list them.

%ifndef __CWP_OPS_INC__
%define __CWP_OPS_INC__

; cw_display (canvas-core.cwp)
%define DISPLAY_SYNC                1
%define DISPLAY_GET_VERSION         2
%define DISPLAY_EVENT_CAPS          0
%define DISPLAY_EVENT_ERROR         1

; cw_buffer
%define BUFFER_CREATE               0
%define BUFFER_DESTROY              1

; cw_surface
%define SURFACE_CREATE              0
%define SURFACE_DESTROY             1
%define SURFACE_ATTACH              2
%define SURFACE_DAMAGE              3
%define SURFACE_FRAME_CALLBACK      11
%define SURFACE_COMMIT              12
%define SURFACE_EVENT_FRAME_DONE    0

; cw_pointer, cw_keyboard (canvas-input.cwp)
%define POINTER_EV_ENTER         0
%define POINTER_EV_LEAVE         1
%define POINTER_EV_MOTION        2
%define POINTER_EV_BUTTON        3
%define POINTER_EV_AXIS          4
%define KEYBOARD_EV_ENTER        0
%define KEYBOARD_EV_LEAVE        1
%define KEYBOARD_EV_KEY          2
%define KEYBOARD_EV_MODIFIERS    3
%define KEYBOARD_EV_TEXT         4

; cw_toplevel (canvas-shell.cwp)
%define TOPLEVEL_CREATE             0
%define TOPLEVEL_DESTROY            1
%define TOPLEVEL_SET_TITLE          2
%define TOPLEVEL_SET_APP_ID         3
%define TOPLEVEL_ACK_CONFIGURE      4
%define TOPLEVEL_SET_MAXIMIZED      5
%define TOPLEVEL_UNSET_MAXIMIZED    6
%define TOPLEVEL_SET_FULLSCREEN     7
%define TOPLEVEL_UNSET_FULLSCREEN   8
%define TOPLEVEL_SET_MINIMIZED      9
%define TOPLEVEL_EVENT_CONFIGURE    0
%define TOPLEVEL_EVENT_CLOSE        1

; cw_popup
%define POPUP_CREATE                0
%define POPUP_DESTROY               1
%define POPUP_EVENT_DONE            0

; cw_layer
%define LAYER_CREATE                0
%define LAYER_DESTROY               1
%define LAYER_SET_EXCLUSIVE         2
%define LAYER_EVENT_CONFIGURE       0

; cw_window_list
%define WINDOW_LIST_SUBSCRIBE       0
%define WINDOW_LIST_ACTIVATE        1
%define WINDOW_LIST_CLOSE           2
%define WINDOW_LIST_MINIMIZE        3
%define WINDOW_LIST_SET_MAXIMIZED   4
%define WINDOW_LIST_EVENT_WINDOW    0
%define WINDOW_LIST_EVENT_REMOVED   1
%define WINDOW_LIST_EVENT_ACTIVATED 2

%endif
