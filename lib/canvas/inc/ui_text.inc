; ============================================================================
; ui_text.inc — One Line of Text into Pixels (src/text/ui_text.asm)
; ============================================================================

%ifndef UI_TEXT_INC
%define UI_TEXT_INC

; What ui_text_draw draws: text in a box at (x, y) of 32-bit BGRX pixels,
; only inside the clip (all in the target's coordinates)
struc UiText
    .pixels:        resq 1      ; the target's first row
    .stride:        resq 1      ; its bytes from one row to the next
    .x:             resd 1      ; the box
    .y:             resd 1
    .width:         resd 1
    .height:        resd 1
    .clip_x:        resd 1      ; what may change
    .clip_y:        resd 1
    .clip_w:        resd 1
    .clip_h:        resd 1
    .size:          resd 1      ; font size, pixels
    .colour:        resd 1      ; 0xRRGGBB
    .text:          resq 1      ; UTF-8
    .length:        resd 1      ; bytes
    .pad:           resd 1
endstruc

%endif
