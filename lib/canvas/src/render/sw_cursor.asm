; ============================================================================
; Software Cursor — the Pointer Drawn by the Compositor
; ============================================================================
; The pointer's shape, its tip at the pointer, drawn last in each damaged
; rectangle of each output, over everything (CMP-03): on whichever outputs
; it is over, across an edge too, each at its own size, its scale rounded to
; 1x or 2x (PTR-11). The shape is the one the client of the surface under the
; pointer asked for (cw_pointer.set_shape, Surface.cursor_shape), the arrow
; anywhere else. Moving the pointer damages a box round where it was and
; where it is that any shape at 2x fits in (sw_cursor_moved). It is drawn
; only while Compositor.cursor_on is set: canvasd sets it; tests and a
; hardware cursor leave it off. Typing hides it (sw_cursor_hide, PTR-14)
; until the pointer next moves.
;
;   default, the tip at column 0, row 0:
;     X
;     XX
;     X.X
;     X..X
;     X...X
;     X....X
;     X.....X
;     X......X
;     X.......X
;     X........X
;     X.....XXXXX
;     X..X..X
;     X.X X..X
;     XX  X..X
;     X    X..X
;          X..X
;           XX
;   text, the tip at column 3, row 7:
;     XXXXXXX
;     X..X..X
;     XXX.XXX
;       X.X
;       X.X
;       X.X
;       X.X
;       X.X
;       X.X
;       X.X
;       X.X
;       X.X
;     XXX.XXX
;     X..X..X
;     XXXXXXX
;   crosshair, the tip at column 6, row 6:
;          XXX
;          X.X
;          X.X
;          X.X
;          X.X
;     XXXXXX.XXXXXX
;     X...........X
;     XXXXXX.XXXXXX
;          X.X
;          X.X
;          X.X
;          X.X
;          XXX
;
; X is the black outline, . the white fill. Row n of each mask is bit c for
; column c.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern compositor_damage_rect
extern rect_intersect

%define SHAPE_COUNT 3
%define SHAPE_SIZE  24                  ; w, h, tip x, tip y, the two masks
%define CURSOR_INK  0xFF000000
%define CURSOR_FILL 0xFFFFFFFF
%define BOX_BEFORE  32                  ; the box round the pointer, at 2x:
%define BOX_SIZE    80                  ; any tip within 16, any shape 40 big

section .text

; ---------------------------------------------------------------------------
; sw_cursor_render
;   The pointer's shape, the part inside the clip
;   IN:  rdi = frame context, rsi = clip rect*, rdx = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
%define L_RECT      0                   ; the shape's rect, the part shown
%define L_SHOWN     16
%define L_SHIFT     32                  ; 0 at 1x, 1 at 2x
%define L_INK       40                  ; the shape's masks
%define L_FILL      48
global sw_cursor_render
sw_cursor_render:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 56                         ; locals; 16-byte aligned
    mov rbx, rdi
    mov rax, [rdx + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    cmp qword [rax + Compositor.cursor_hidden], 0
    jne .done
    mov r8, [rdx + Server.input_seat]
    test r8, r8
    jz .done
    xor eax, eax                        ; the shape: the surface under it asks
    mov rcx, [r8 + InputSeat.pointer_focus]
    test rcx, rcx
    jz .shape
    mov rax, [rcx + Surface.cursor_shape]
    cmp rax, SHAPE_COUNT
    jb .shape
    xor eax, eax
.shape:
    imul rax, rax, SHAPE_SIZE
    lea r9, [rel shapes]
    add r9, rax
    mov eax, [r9 + 16]
    lea rcx, [rel shapes]
    add rax, rcx
    mov [rsp + L_INK], rax
    mov eax, [r9 + 20]
    add rax, rcx
    mov [rsp + L_FILL], rax
    xor ecx, ecx                        ; its size here: the output's scale,
    mov rax, [rbx + FrameCtx.output]    ; rounded, 1x or 2x
    test rax, rax
    jz .sized
    cmp qword [rax + Output.pixel_fb], 0
    jne .sized                          ; drawn logical, scaled after
    mov rax, [rax + Output.scale]
    add rax, 0x8000
    shr rax, 16
    cmp rax, 2
    jb .sized
    mov ecx, 1
.sized:
    mov [rsp + L_SHIFT], ecx
    mov r12d, [r8 + InputSeat.x]        ; its top left, from the tip
    mov eax, [r9 + 8]
    shl eax, cl
    sub r12d, eax
    mov r13d, [r8 + InputSeat.y]
    mov eax, [r9 + 12]
    shl eax, cl
    sub r13d, eax
    mov [rsp + L_RECT], r12d
    mov [rsp + L_RECT + 4], r13d
    mov eax, [r9]
    shl eax, cl
    mov [rsp + L_RECT + 8], eax
    mov eax, [r9 + 4]
    shl eax, cl
    mov [rsp + L_RECT + 12], eax
    lea rdi, [rsp + L_SHOWN]
    mov rdx, rsi
    lea rsi, [rsp + L_RECT]
    call rect_intersect
    test rax, rax
    jnz .done                           ; none of it in the clip
    mov r14d, [rsp + L_SHOWN + 4]       ; the first row shown
.row:
    mov eax, [rsp + L_SHOWN + 4]
    add eax, [rsp + L_SHOWN + 12]
    cmp r14d, eax
    jge .done
    mov eax, r14d                       ; its row of the masks
    sub eax, r13d
    mov ecx, [rsp + L_SHIFT]
    shr eax, cl
    mov rcx, [rsp + L_INK]
    movzx r8d, word [rcx + rax * 2]
    mov rcx, [rsp + L_FILL]
    movzx r9d, word [rcx + rax * 2]
    movsxd r10, r14d                    ; the row's first pixel
    imul r10, [rbx + FrameCtx.stride]
    add r10, [rbx + FrameCtx.framebuffer]
    mov r15d, [rsp + L_SHOWN]           ; the first column shown
.column:
    mov eax, [rsp + L_SHOWN]
    add eax, [rsp + L_SHOWN + 8]
    cmp r15d, eax
    jge .next_row
    mov eax, r15d                       ; its column of the masks
    sub eax, r12d
    mov ecx, [rsp + L_SHIFT]
    shr eax, cl
    movsxd rdx, r15d
    bt r8d, eax
    jnc .not_ink
    mov dword [r10 + rdx * 4], CURSOR_INK
    jmp .next_column
.not_ink:
    bt r9d, eax
    jnc .next_column
    mov dword [r10 + rdx * 4], CURSOR_FILL
.next_column:
    inc r15d
    jmp .column
.next_row:
    inc r14d
    jmp .row
.done:
    xor eax, eax
    add rsp, 56
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; rdi = server, esi = x, edx = y: the box round a pointer there redrawn
damage_box:
    sub rsp, 24                         ; a rect; 16-byte aligned
    sub esi, BOX_BEFORE
    sub edx, BOX_BEFORE
    mov [rsp], esi
    mov [rsp + 4], edx
    mov dword [rsp + 8], BOX_SIZE
    mov dword [rsp + 12], BOX_SIZE
    mov rsi, rsp
    call compositor_damage_rect
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; sw_cursor_moved
;   The pointer moved: round where it was and where it is is redrawn, and
;   it shows if typing hid it
;   IN:  rdi = server*, esi, edx = where it was, ecx, r8d = where it is
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_cursor_moved
sw_cursor_moved:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12d, ecx
    mov r13d, r8d
    mov rax, [rbx + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    mov qword [rax + Compositor.cursor_hidden], 0   ; a move shows it
    call damage_box
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call damage_box
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; sw_cursor_redraw
;   The shape may have changed (a client asked for another): redrawn where
;   the pointer is
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_cursor_redraw
sw_cursor_redraw:
    mov rax, [rdi + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .done
    mov esi, [rax + InputSeat.x]
    mov edx, [rax + InputSeat.y]
    jmp damage_box
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; sw_cursor_hide
;   Typing: the pointer goes, where it was redrawn, until it moves
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_cursor_hide
sw_cursor_hide:
    mov rax, [rdi + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    cmp qword [rax + Compositor.cursor_hidden], 0
    jne .done                           ; gone already
    mov qword [rax + Compositor.cursor_hidden], 1
    jmp sw_cursor_redraw
.done:
    xor eax, eax
    ret

section .rodata
align 4
shapes:                                 ; SHAPE_SIZE each, by cw_pointer.shape
    dd 11, 17, 0, 0, default_ink - shapes, default_fill - shapes
    dd 7, 15, 3, 7, text_ink - shapes, text_fill - shapes
    dd 13, 13, 6, 6, crosshair_ink - shapes, crosshair_fill - shapes
align 2
default_ink:       dw 0x0001, 0x0003, 0x0005, 0x0009, 0x0011, 0x0021, 0x0041, 0x0081, 0x0101, 0x0201, 0x07C1, 0x0049, 0x0095, 0x0093, 0x0121, 0x0120, 0x00C0
default_fill:      dw 0x0000, 0x0000, 0x0002, 0x0006, 0x000E, 0x001E, 0x003E, 0x007E, 0x00FE, 0x01FE, 0x003E, 0x0036, 0x0062, 0x0060, 0x00C0, 0x00C0, 0x0000
text_ink:          dw 0x007F, 0x0049, 0x0077, 0x0014, 0x0014, 0x0014, 0x0014, 0x0014, 0x0014, 0x0014, 0x0014, 0x0014, 0x0077, 0x0049, 0x007F
text_fill:         dw 0x0000, 0x0036, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0008, 0x0036, 0x0000
crosshair_ink:     dw 0x00E0, 0x00A0, 0x00A0, 0x00A0, 0x00A0, 0x1FBF, 0x1001, 0x1FBF, 0x00A0, 0x00A0, 0x00A0, 0x00A0, 0x00E0
crosshair_fill:    dw 0x0000, 0x0040, 0x0040, 0x0040, 0x0040, 0x0040, 0x0FFE, 0x0040, 0x0040, 0x0040, 0x0040, 0x0040, 0x0000

section .data
global sw_cursor_version
sw_cursor_version: dq 0x020000
