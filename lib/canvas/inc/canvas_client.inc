; ============================================================================
; Canvas Client ABI — Public Client Library Interface (canvas_client.o)
; Pure assembly, no libc; links statically into client images
; ============================================================================
; A connection is one memory region: ClientConn at its start, the buffer
; table, the clipboard, the wire state (ClientWire at CLIENT_WIRE), then the
; heap. Requests go out on the channel pair's client-to-server ring; replies
; and events come back on the other. A call that needs a reply waits for it,
; turning the connection's pump while nothing has come: in canvasd's own
; process that is server_poll, elsewhere the program yields.

%ifndef __CANVAS_CLIENT_INC__
%define __CANVAS_CLIENT_INC__

%include "inc/struct_offsets.inc"
%include "inc/events.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"

; Opaque handles: conn is a pointer; surfaces and buffers are the server's
; u32 handles

; Capability bits wanted at connect: the same bits as CAP_* in inc/caps.inc
%define CLIENT_CAP_DISPLAY     (1 << 0)
%define CLIENT_CAP_BUFFER      (1 << 1)
%define CLIENT_CAP_SURFACE     (1 << 2)
%define CLIENT_CAP_PRESENT     (1 << 3)
%define CLIENT_CAP_SHELL       (1 << 11)
%define CLIENT_CAP_LAYER       (1 << 12)
%define CLIENT_CAP_DATA        (1 << 13)

; Commit flags
%define CLIENT_COMMIT_TRANSACTION  (1 << 0)

; The connection region
%define CLIENT_REGION_SIZE     1048576
%define CLIENT_BUFFER_TABLE    256      ; ClientBuffer records
%define CLIENT_BUFFER_MAX      128
%define CLIENT_WIRE            49152    ; ClientWire
%define CLIENT_HEAP_OFFSET     65536
%define CLIENT_EVENTS          64       ; events held while a call waits
%define CLIENT_CALL_TURNS      100000   ; pump turns before a call gives up

; Event types, as canvas_event_type gives them: interface << 16 | event
%define CANVAS_EV_CAPS          (CWP_OBJ_DISPLAY << 16 | DISPLAY_EVENT_CAPS)
%define CANVAS_EV_ERROR         (CWP_OBJ_DISPLAY << 16 | DISPLAY_EVENT_ERROR)
%define CANVAS_EV_FRAME_DONE    (CWP_OBJ_SURFACE << 16 | SURFACE_EVENT_FRAME_DONE)
%define CANVAS_EV_POINTER_ENTER (CWP_OBJ_POINTER << 16 | POINTER_EV_ENTER)
%define CANVAS_EV_POINTER_LEAVE (CWP_OBJ_POINTER << 16 | POINTER_EV_LEAVE)
%define CANVAS_EV_MOTION        (CWP_OBJ_POINTER << 16 | POINTER_EV_MOTION)
%define CANVAS_EV_BUTTON        (CWP_OBJ_POINTER << 16 | POINTER_EV_BUTTON)
%define CANVAS_EV_AXIS          (CWP_OBJ_POINTER << 16 | POINTER_EV_AXIS)
%define CANVAS_EV_KEY_ENTER     (CWP_OBJ_KEYBOARD << 16 | KEYBOARD_EV_ENTER)
%define CANVAS_EV_KEY_LEAVE     (CWP_OBJ_KEYBOARD << 16 | KEYBOARD_EV_LEAVE)
%define CANVAS_EV_KEY           (CWP_OBJ_KEYBOARD << 16 | KEYBOARD_EV_KEY)
%define CANVAS_EV_MODIFIERS     (CWP_OBJ_KEYBOARD << 16 | KEYBOARD_EV_MODIFIERS)
%define CANVAS_EV_TEXT          (CWP_OBJ_KEYBOARD << 16 | KEYBOARD_EV_TEXT)
%define CANVAS_EV_CONFIGURE     (CWP_OBJ_TOPLEVEL << 16 | TOPLEVEL_EVENT_CONFIGURE)
%define CANVAS_EV_CLOSE         (CWP_OBJ_TOPLEVEL << 16 | TOPLEVEL_EVENT_CLOSE)
%define CANVAS_EV_POPUP_DONE    (CWP_OBJ_POPUP << 16 | POPUP_EVENT_DONE)
%define CANVAS_EV_LAYER_CONFIGURE (CWP_OBJ_LAYER << 16 | LAYER_EVENT_CONFIGURE)

; cw_layer.create's layer and anchors
%define CANVAS_LAYER_BACKGROUND 0
%define CANVAS_LAYER_BOTTOM     1
%define CANVAS_LAYER_TOP        2
%define CANVAS_LAYER_OVERLAY    3
%define CANVAS_ANCHOR_TOP       1
%define CANVAS_ANCHOR_BOTTOM    2
%define CANVAS_ANCHOR_LEFT      4
%define CANVAS_ANCHOR_RIGHT     8
%define CANVAS_ANCHOR_ALL       15

; An event: its type and payload as the server sent it, up to 48 bytes.
; Input events start (time: ulong, surface: handle), so canvas_event_time
; reads data[0].
struc ClientEvent
    .type:      resd 1
    .length:    resd 1
    .data:      resb 48
endstruc

; A buffer the server made for this connection
struc ClientBuffer
    .id:        resd 1
    .width:     resd 1
    .height:    resd 1
    .format:    resd 1
    .stride:    resd 1
    .pad:       resd 1
    .pixels:    resq 1
endstruc

; The wire state, at CLIENT_WIRE in the region
struc ClientWire
    .pump:      resq 1          ; rdi = pump_arg; 0: yield instead
    .pump_arg:  resq 1
    .head:      resd 1          ; held events: next to give out
    .tail:      resd 1          ; next free
    .dropped:   resd 1          ; events lost while held events were full
    .pad:       resd 1
    .in_hdr:    resb 16         ; MsgHdr of the message last read
    .out_hdr:   resb 16
    .in_msg:    resb 256        ; its payload
    .reply:     resb 256        ; the last call's answer
    .arena:     resb Arena_size
    alignb 8
    .events:    resb 3584       ; CLIENT_EVENTS ClientEvents
endstruc

; Present info (mirrors render.inc)
struc ClientPresentInfo
    .kind:            resd 1
    .seq:             resq 1
    .time:            resq 1
    .refresh_ns:      resq 1
    .flags:           resd 1
endstruc

%endif ; __CANVAS_CLIENT_INC__
