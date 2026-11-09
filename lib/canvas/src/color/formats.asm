; ============================================================================
; Pixel Format Descriptors
; ============================================================================
; The descriptors inc/color.inc names, defined once (FND-03): each object
; that included it used to carry its own weak copy.

%define COLOR_FORMATS_IMPL
%include "inc/color.inc"

section .rodata

global fmt_bgra8888
fmt_bgra8888:
    dd DRM_FORMAT_BGRA8888
    dq 0                    ; modifier
    db FMT_BPP_BGRA8888
    db FMT_BYTES_BGRA8888
    db 1                    ; premul
    db 0
    times 13 db 0

global fmt_bgr8888
fmt_bgr8888:
    dd DRM_FORMAT_BGR8888
    dq 0
    db FMT_BPP_BGR8888
    db FMT_BYTES_BGR8888
    db 0                    ; not premul (opaque)
    db 0
    times 13 db 0

global fmt_rgb565
fmt_rgb565:
    dd DRM_FORMAT_RGB565
    dq 0
    db FMT_BPP_RGB565
    db FMT_BYTES_RGB565
    db 0
    db 0
    times 13 db 0

section .data
global formats_version
formats_version: dq 0x010000
