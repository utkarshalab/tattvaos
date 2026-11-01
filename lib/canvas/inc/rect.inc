; ============================================================================
; Rect — Rectangle Structure (x, y, width, height)
; ============================================================================

%ifndef __RECT_INC__
%define __RECT_INC__

section .text

; Rect struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; Rect struct
struc Rect
    .x:      resq 1
    .y:      resq 1
    .width:  resq 1
    .height: resq 1
    .x1:                      resd 1
    resb 4
    .x2:                      resd 1
    resb 4
    .y1:                      resd 1
    resb 4
    .y2:                      resd 1
endstruc

%endif ; __RECT_INC__