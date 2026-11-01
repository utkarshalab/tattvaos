; ============================================================================
; Compositor Core Definitions — Composition, Damage, Output, Surface State
; ============================================================================

%ifndef __COMPOSITOR_INC__
%define __COMPOSITOR_INC__

%include "inc/fixed.inc"
%include "inc/geometry.inc"

; ============================================================================
; Damage Region
; ============================================================================
%define DAMAGE_SIZE       32

; ============================================================================
; Output
; ============================================================================
%define OUTPUT_DAMAGE          112
%define OUTPUT_FRAME_CLOCK     232
%define OUTPUT_SIZE            264

; Output DPMS states
%define DPMS_ON         0
%define DPMS_STANDBY    1
%define DPMS_SUSPEND    2
%define DPMS_OFF        3

; Output rotation
%define ROTATE_0        0
%define ROTATE_90       1
%define ROTATE_180      2
%define ROTATE_270      3

; ============================================================================
; Surface State
; ============================================================================
%define SURFACE_DAMAGE       8
%define SURFACE_BUF_X        24
%define SURFACE_BUF_Y        32
%define SURFACE_INPUT        36
%define SURFACE_OPAQUE       44
%define SURFACE_TRANSFORM    64
%define SURFACE_SCALE        72
%define SURFACE_FRAME_CBS    80
%define SURFACE_SIZE         104

%define SURFACE_STATE_BUFFER 0
%define SURFACE_STATE_DAMAGE 8
%define SURFACE_STATE_PENDING 16

; Transform enum
%define TRANSFORM_NORMAL       0
%define TRANSFORM_90           1
%define TRANSFORM_180          2
%define TRANSFORM_270          3
%define TRANSFORM_FLIPPED      4
%define TRANSFORM_FLIPPED_90   5
%define TRANSFORM_FLIPPED_180  6
%define TRANSFORM_FLIPPED_270  7

; ============================================================================
; Frame Clock
; ============================================================================
%define FRAME_CLOCK_CALLBACKS    0
%define FRAME_CLOCK_NEXT_VBLANK  8
%define FRAME_CLOCK_REFRESH_NS   16
%define FRAME_CLOCK_SIZE         24

; ============================================================================
; Compositor
; ============================================================================
%define COMPOSITOR_SIZE          64

; ============================================================================
; Render List Entry
; ============================================================================
%define RENDER_ENTRY_SURFACE   0
%define RENDER_ENTRY_X         8
%define RENDER_ENTRY_Y         16
%define RENDER_ENTRY_Z         24
%define RENDER_ENTRY_ALPHA     28
%define RENDER_ENTRY_TRANSFORM 32
%define RENDER_ENTRY_CLIP      40
%define RENDER_ENTRY_NEXT      48
%define RENDER_ENTRY_SIZE      56

; ============================================================================
; Frame Callback
; ============================================================================
%define FRAME_CB_SURFACE    0
%define FRAME_CB_SEQ        8
%define FRAME_CB_TIMESTAMP  16
%define FRAME_CB_NEXT       24
%define FRAME_CB_SIZE       32

%endif ; __COMPOSITOR_INC__