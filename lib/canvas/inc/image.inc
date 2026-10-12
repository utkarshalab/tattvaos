; ============================================================================
; Image — Shared Image Decoder Definitions (sniff, formats)
; ============================================================================

%ifndef __IMAGE_INC__
%define __IMAGE_INC__

; Supported formats
%define IMAGE_FMT_UNKNOWN   0
%define IMAGE_FMT_PNG       1
%define IMAGE_FMT_JPEG      2
%define IMAGE_FMT_GIF       3
%define IMAGE_FMT_BMP       4
%define IMAGE_FMT_SVG       5

; PixBuf field offsets (mirrors pixbuf.asm layout)
%define PixBuf_width     0
%define PixBuf_height    8
%define PixBuf_stride    16
%define PixBuf_format    24
%define PixBuf_data      32
%define PixBuf_size      40
%define PixBuf_refcount  48
%define PixBuf_arena     56

; DRM formats (subset, mirrors color.inc)
%ifndef DRM_FORMAT_BGRA8888
%define DRM_FORMAT_BGR8888      0x34325242
%define DRM_FORMAT_BGRA8888     0x41524742
%define DRM_FORMAT_RGB565       0x35364247
%define DRM_FORMAT_XRGB2101010  0x33305258
%endif

%endif ; __IMAGE_INC__
