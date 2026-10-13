; ============================================================================
; Backend Interface — Display Backend Abstraction
; ============================================================================

%ifndef __BACKEND_INC__
%define __BACKEND_INC__

; Backend Capabilities
%define BACKEND_CAP_HEADLESS      (1 << 0)
%define BACKEND_CAP_FB_LINEAR     (1 << 1)
%define BACKEND_CAP_NATIVE        (1 << 2)
%define BACKEND_CAP_REMOTE        (1 << 3)
%define BACKEND_CAP_PLANES        (1 << 4)
%define BACKEND_CAP_CURSOR_PLANE  (1 << 5)
%define BACKEND_CAP_VRR           (1 << 6)
%define BACKEND_CAP_HDR           (1 << 7)
%define BACKEND_CAP_DIRECT_SCANOUT (1 << 8)

; Backend State (opaque, per-backend)
struc Backend
    .init:           resq 1
    .deinit:         resq 1
    .modeset:        resq 1
    .flip:           resq 1
    .vblank_wait:    resq 1
    .hotplug:        resq 1
    .cursor:         resq 1
    .caps:           resq 1
    .state:          resq 1          ; Backend-specific state
    .outputs:        resq 1          ; List of outputs
    .output_count:   resq 1
    .arena:          resq 1
    .server:         resq 1
    .name:           resq 1
endstruc
%define Backend_size      96

; Output Structure
struc Output
    .id:              resq 1
    .name:            resq 1
    .backend:         resq 1
    .framebuffer:     resq 1
    .width:           resd 1
    .height:          resd 1
    .stride:          resq 1
    .scale:           resq 1
    .rotation:        resd 1
    .gamma_lut:       resq 1
    .icc_profile:     resq 1
    .vrr_enabled:     resb 1
    .current_mode:    resq 1
    .modes:           resq 1
    .position:        resq 1          ; Point*
    .frame_clock:     resq 1
    .damage:          resq 1
    .next:            resq 1
endstruc
%define Output_size         128

; Mode Structure
struc Mode
    .width:         resd 1
    .height:        resd 1
    .refresh_ns:    resq 1
    .flags:         resd 1
    .name:          resq 1
endstruc
%define Mode_size             32

; Mode Flags
%define MODE_FLAG_INTERLACED   (1 << 0)
%define MODE_FLAG_PREFERRED    (1 << 1)
%define MODE_FLAG_VRR          (1 << 2)

; Point Structure
struc Point
    .x: resd 1
    .y: resd 1
endstruc
%define Point_size            8

; Config Structure (for backend init)
struc Config
    .fb_base:       resq 1
    .fb_width:      resd 1
    .fb_height:     resd 1
    .fb_stride:     resd 1
    .fb_format:     resd 1
endstruc
%define Config_size           32

; Backend Function Pointers
%macro BACKEND_FUNCS 0
    .init:          resq 1
    .deinit:        resq 1
    .modeset:       resq 1
    .flip:          resq 1
    .vblank_wait:   resq 1
    .hotplug:       resq 1
    .cursor:        resq 1
%endmacro

%endif ; __BACKEND_INC__
