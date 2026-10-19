; ============================================================================
; Pixbuf — Pixel Buffer Reference
; ============================================================================

%ifndef __PIXBUF_INC__
%define __PIXBUF_INC__

; struct offsets (hoisted above use)
%define PixBuf_SIZE 48

section .text

; Pixbuf struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

%define PixBuf_width 0
%define PixBuf_height 8
%define PixBuf_format 16
%define PixBuf_stride 24
%define PixBuf_data 32
%define PixBuf_size 40
%define PixBuf_refcount 48

%endif ; __PIXBUF_INC__