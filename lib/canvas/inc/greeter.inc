; ============================================================================
; greeter.inc — What the Login Screen Looks Like
; ============================================================================
; src/session/greeter.asm draws with these; tests/host/ubf_run.asm checks the
; first frame against them. Colours are 32-bit BGRX, written as 0xAARRGGBB.

%ifndef GREETER_INC
%define GREETER_INC

%define GREETER_BG          0xFF1E2233  ; the whole screen
%define GREETER_FIELD       0xFF2C3248  ; inside the password field
%define GREETER_BORDER      0xFF5A6488  ; the field's edge
%define GREETER_FAILED      0xFFC04848  ; the edge after a wrong password
%define GREETER_INK         0xFFD0D4E0  ; dots and the caret

; The field is centred: x = (width - GREETER_FIELD_W) / 2, the same for y.
; A screen smaller than the field gets no greeter.
%define GREETER_FIELD_W     360
%define GREETER_FIELD_H     48
%define GREETER_EDGE        2           ; border thickness
%define GREETER_PAD         16          ; first dot from the field's left
%define GREETER_DOT         10          ; a dot is a square this big
%define GREETER_DOT_STEP    20          ; from one dot to the next
%define GREETER_DOTS        16          ; dots that fit; more typed shows 16
%define GREETER_CARET_W     2
%define GREETER_CARET_H     24

%define GREETER_MAX         64          ; characters kept

; Its states
%define GREETER_SHOWN           3
%define GREETER_DONE            4

; The greeter itself; channel.inc must come first
struc Greeter
    .server:        resq 1
    .verify:        resq 1      ; rdi = text, esi = length -> rax 0 if right
    .conn:          resq 1      ; its client library connection
    .pixels:        resq 1
    .state:         resd 1
    .buffer:        resd 1
    .surface:       resd 1
    .width:         resd 1
    .height:        resd 1
    .stride:        resd 1
    .field_x:       resd 1
    .field_y:       resd 1
    .len:           resd 1
    .failed:        resd 1
    .dirty:         resd 1
    .pad:           resd 1
    .pair:          resb ChannelPair_size
    alignb 8
    .event:         resb 144    ; a ClientEvent (inc/canvas_client.inc)
    .text:          resb 64     ; GREETER_MAX: sizes are literal for
endstruc                        ; make field-width-check

%if GREETER_MAX != 64
    %error "Greeter: the text buffer above must follow GREETER_MAX"
%endif

%endif
