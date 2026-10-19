; ============================================================================
; Rect — Rectangle Structure (x, y, width, height)
; ============================================================================

%ifndef __RECT_INC__
%define __RECT_INC__

; struct offsets (hoisted above use)
%define Rect_SIZE 32

section .text

; Rect struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

%define Rect_x 0
%define Rect_y 8
%define Rect_width 16
%define Rect_height 24

; Rect struct
struc Rect
    .x:      resq 1
    .y:      resq 1
    .width:  resq 1
    .height: resq 1
endstruc

%endif ; __RECT_INC__