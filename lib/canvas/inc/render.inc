; ============================================================================
; Render Interface — Backend-Agnostic Renderer Interface
; ============================================================================

%ifndef __RENDER_INC__
%define __RENDER_INC__

%include "inc/backend.inc"

; Renderer Capabilities
%define RENDER_CAP_BLEND          (1 << 0)
%define RENDER_CAP_SCALE          (1 << 1)
%define RENDER_CAP_TRANSFORM      (1 << 2)
%define RENDER_CAP_DIRECT_SCANOUT (1 << 3)
%define RENDER_CAP_PLANES         (1 << 4)
%define RENDER_CAP_CURSOR_PLANE   (1 << 5)
%define RENDER_CAP_HDR            (1 << 6)
%define RENDER_CAP_COLOR_MGMT     (1 << 7)

; Renderer Function Table
struc RenderIface
    .begin_frame:      resq 1
    .render_surface:   resq 1
    .render_rect:      resq 1
    .end_frame:        resq 1
    .flush:            resq 1
    .caps:             resq 1
endstruc
%define RenderIface_size      48

; Frame Context (per-frame state)
struc FrameCtx
    .output:           resq 1
    .damage:           resq 1
    .render_list:      resq 1
    .framebuffer:      resq 1
    .stride:           resq 1
    .width:            resd 1
    .height:           resd 1
    .color_transform:  resq 1
endstruc
%define FrameCtx_size         64

; Present Info (returned by end_frame)
struc PresentInfo
    .kind:            resd 1
    .seq:             resq 1
    .time:            resq 1
    .refresh_ns:      resq 1
    .flags:           resd 1
endstruc
%define PresentInfo_size      32

; Present Kinds
%define PRESENT_KIND_VSYNC    0
%define PRESENT_KIND_IMMEDIATE 1
%define PRESENT_KIND_ASYNC    2

; Present Flags
%define PRESENT_FLAG_HW_COMPLETION  1
%define PRESENT_FLAG_ZERO_COPY      2
%define PRESENT_FLAG_ASYNC          4

%endif ; __RENDER_INC__
