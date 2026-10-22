; ============================================================================
; Color & Pixel Format Definitions
; Primary: 32-bit BGRA premultiplied alpha
; ============================================================================

%ifndef __COLOR_INC__
%define __COLOR_INC__

; ---------------------------------------------------------------------------
; DRM FourCC Format Codes (subset)
; ---------------------------------------------------------------------------
%define DRM_FORMAT_BGR8888      0x34325242  ; 'BGR4' - 32-bit BGRX
%define DRM_FORMAT_BGRA8888     0x41524742  ; 'BGRA' - 32-bit BGRA premul
%define DRM_FORMAT_RGB565       0x35364247  ; 'RGB565'
%define DRM_FORMAT_XRGB2101010  0x33305258  ; 'XRGB' - 10-bit
%define DRM_FORMAT_XBGR2101010  0x33304258  ; 'XBGR' - 10-bit

; ---------------------------------------------------------------------------
; Format Properties
; ---------------------------------------------------------------------------
%define FMT_BPP_BGRA8888        32
%define FMT_BPP_BGR8888         32
%define FMT_BPP_RGB565          16
%define FMT_BPP_XRGB2101010     32

%define FMT_BYTES_BGRA8888      4
%define FMT_BYTES_BGR8888       4
%define FMT_BYTES_RGB565        2
%define FMT_BYTES_XRGB2101010   4

; ---------------------------------------------------------------------------
; Channel Masks (BGRA8888)
; ---------------------------------------------------------------------------
%define CHAN_B_MASK             0x000000FF
%define CHAN_G_MASK             0x0000FF00
%define CHAN_R_MASK             0x00FF0000
%define CHAN_A_MASK             0xFF000000

%define CHAN_B_SHIFT            0
%define CHAN_G_SHIFT            8
%define CHAN_R_SHIFT            16
%define CHAN_A_SHIFT            24

; ---------------------------------------------------------------------------
; Premultiplied Alpha Helpers
; ---------------------------------------------------------------------------

; Premultiply color by alpha
; IN:  eax = BGRA pixel, edx = alpha (0-255)
; OUT: eax = premultiplied pixel
%macro PREMUL_PIXEL 0
    push rbx
    mov ebx, eax
    and ebx, CHAN_B_MASK
    imul ebx, edx
    shr ebx, 8
    mov ecx, eax
    shr ecx, 8
    and ecx, CHAN_G_MASK
    imul ecx, edx
    shr ecx, 8
    mov edx, eax
    shr edx, 16
    and edx, CHAN_R_MASK
    imul edx, edx
    shr edx, 8
    and eax, CHAN_A_MASK
    or eax, ebx
    or eax, ecx
    or eax, edx
    pop rbx
%endmacro

; Unpremultiply (for reading back)
; IN:  eax = premultiplied BGRA
; OUT: eax = unpremultiplied BGRA
%macro UNPREMUL_PIXEL 0
    push rbx
    mov ebx, eax
    shr ebx, 24
    test ebx, ebx
    jz .done
    cmp ebx, 255
    je .done
    ; Unpremultiply each channel
    mov ecx, eax
    and ecx, CHAN_B_MASK
    mov edx, 255
    div ebx
    mov ecx, eax
    mov edx, eax
    shr edx, 8
    and edx, CHAN_G_MASK
    div ebx
    mov edx, eax
    shr edx, 16
    and edx, CHAN_R_MASK
    div ebx
    shl eax, 24
    or eax, edx
    or eax, ecx
.done:
    pop rbx
%endmacro

; ---------------------------------------------------------------------------
; Color Constants (Premultiplied BGRA)
; ---------------------------------------------------------------------------
%define COLOR_TRANSPARENT       0x00000000
%define COLOR_BLACK             0xFF000000
%define COLOR_WHITE             0xFFFFFFFF
%define COLOR_RED               0xFF0000FF
%define COLOR_GREEN             0xFF00FF00
%define COLOR_BLUE              0xFFFF0000
%define COLOR_YELLOW            0xFF00FFFF
%define COLOR_CYAN              0xFFFFFF00
%define COLOR_MAGENTA           0xFFFF00FF
%define COLOR_GRAY              0xFF808080
%define COLOR_DARK_GRAY         0xFF404040
%define COLOR_LIGHT_GRAY        0xFFC0C0C0

; ---------------------------------------------------------------------------
; Pixel Format Description (for negotiation)
; ---------------------------------------------------------------------------
struc PixelFormat
    .format:      resd 1      ; DRM fourcc
    .modifier:    resq 1      ; DRM format modifier
    .bpp:         resb 1      ; bits per pixel
    .bytes:       resb 1      ; bytes per pixel
    .premul:      resb 1      ; 1 = premultiplied alpha
    .reserved:    resb 13
endstruc

%define PixelFormat_size 32

; ---------------------------------------------------------------------------
; Standard Format Descriptors
; ---------------------------------------------------------------------------

section .rodata

global fmt_bgra8888:data weak
fmt_bgra8888:
    dd DRM_FORMAT_BGRA8888
    dq 0                    ; modifier
    db FMT_BPP_BGRA8888
    db FMT_BYTES_BGRA8888
    db 1                    ; premul
    db 0
    times 13 db 0

global fmt_bgr8888:data weak
fmt_bgr8888:
    dd DRM_FORMAT_BGR8888
    dq 0
    db FMT_BPP_BGR8888
    db FMT_BYTES_BGR8888
    db 0                    ; not premul (opaque)
    db 0
    times 13 db 0

global fmt_rgb565:data weak
fmt_rgb565:
    dd DRM_FORMAT_RGB565
    dq 0
    db FMT_BPP_RGB565
    db FMT_BYTES_RGB565
    db 0
    db 0
    times 13 db 0

%endif ; __COLOR_INC__
