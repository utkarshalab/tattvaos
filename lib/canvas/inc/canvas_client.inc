; ============================================================================
; Canvas Client ABI — Public Client Library Interface (canvas_client.o)
; Pure assembly, no libc; links statically into client images
; ============================================================================

%ifndef __CANVAS_CLIENT_INC__
%define __CANVAS_CLIENT_INC__

; Opaque handles (all u64 client-side, validated server-side)
; conn: u64, surface/buffer/toplevel/etc: u32 generation-tagged

; Capability bits wanted at connect (subset of inc/caps.inc)
%define CLIENT_CAP_DISPLAY     (1 << 0)
%define CLIENT_CAP_BUFFER      (1 << 1)
%define CLIENT_CAP_SURFACE     (1 << 2)
%define CLIENT_CAP_PRESENT     (1 << 3)
%define CLIENT_CAP_SHELL       (1 << 10)
%define CLIENT_CAP_DATA        (1 << 13)

; Commit flags
%define CLIENT_COMMIT_TRANSACTION  (1 << 0)

; Event struct (24 bytes, mirrors inc/event.inc)
struc ClientEvent
    .type:  resd 1
    .time:  resq 1
    .a:     resd 1
    .b:     resd 1
    .c:     resd 1
endstruc
%define ClientEvent_size    24

; Present info (mirrors render.inc)
struc ClientPresentInfo
    .kind:            resd 1
    .seq:             resq 1
    .time:            resq 1
    .refresh_ns:      resq 1
    .flags:           resd 1
endstruc
%define ClientPresentInfo_size  32

%endif ; __CANVAS_CLIENT_INC__
