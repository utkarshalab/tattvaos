; ============================================================================
; taskbar.inc — the Built-in Taskbar's Look and State
; ============================================================================
; src/desktop/taskbar.asm draws with these; tests/unit/test_taskbar.asm
; checks against them. Colours are 32-bit BGRX, written as 0xAARRGGBB.

%ifndef TASKBAR_INC
%define TASKBAR_INC

%define TASKBAR_BG          0xFF181C28  ; the bar
%define TASKBAR_DIM         0xFF3A3F50  ; a minimized window's block
%define TASKBAR_INK         0xFFD0D4E0  ; the stripe over the active window

; Along the bottom edge, the output's width; it keeps its height from
; maximized windows
%define TASKBAR_H           32
%define TASKBAR_PAD         4           ; first block from the left, and the
                                        ; blocks from the top and bottom
%define TASKBAR_ENTRY_W     120
%define TASKBAR_GAP         4
%define TASKBAR_STRIPE      3           ; the active block's top stripe
%define TASKBAR_MAX         32          ; windows it keeps track of
%define TASKBAR_WS_W        20          ; a workspace square, at the right end
%define TASKBAR_WS_COUNT    4           ; squares drawn (the server's WORKSPACES)

; One window it shows
struc TaskbarEntry
    .id:            resd 1      ; the window list's id
    .states:        resd 1      ; maximized 1, fullscreen 2, minimized 4
    .color:         resd 1      ; from its app id
    .workspace:     resd 1
endstruc

; The taskbar itself; channel.inc must come first
struc Taskbar
    .server:        resq 1
    .conn:          resq 1
    .pixels:        resq 1
    .width:         resd 1
    .stride:        resd 1
    .buffer:        resd 1
    .surface:       resd 1
    .active:        resd 1      ; the id with the keyboard, 0: none
    .count:         resd 1
    .pointer_x:     resd 1      ; on the bar, from enter and motion
    .dirty:         resd 1
    .workspace:     resd 1      ; the one shown
    .ws_pad:        resd 1
    .pair:          resb ChannelPair_size
    alignb 8
    .event:         resb 148    ; a ClientEvent (inc/canvas_client.inc)
    .entries:       resb 512    ; TASKBAR_MAX TaskbarEntry records
endstruc

%if TASKBAR_MAX * 16 != 512
    %error "Taskbar: the entries buffer above must follow TASKBAR_MAX"
%endif

%endif
