; ============================================================================
; Software Cursor — the Pointer Drawn by the Compositor
; ============================================================================
; An arrow, its tip at the pointer, drawn last in each damaged rectangle of
; each output, over everything (CMP-03): on whichever outputs it is over,
; across an edge too. Moving the pointer damages where the arrow was and
; where it is (sw_cursor_moved). It is drawn only while Compositor.cursor_on
; is set: canvasd sets it; tests and a hardware cursor leave it off. Typing
; hides it (sw_cursor_hide, PTR-14) until the pointer next moves.
;
;   X
;   XX
;   X.X
;   X..X
;   X...X
;   X....X
;   X.....X
;   X......X
;   X.......X
;   X........X
;   X.....XXXXX
;   X..X..X
;   X.X X..X
;   XX  X..X
;   X    X..X
;        X..X
;         XX
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

%define ARROW_W     11
%define ARROW_H     17
%define ARROW_INK   0xFF000000
%define ARROW_FILL  0xFFFFFFFF

section .text

; ---------------------------------------------------------------------------
; sw_cursor_render
;   The arrow, the part inside the clip
;   IN:  rdi = frame context, rsi = clip rect*, rdx = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_cursor_render
sw_cursor_render:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40                         ; the arrow's rect, the part shown
    mov rbx, rdi
    mov rax, [rdx + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    cmp qword [rax + Compositor.cursor_hidden], 0
    jne .done
    mov rax, [rdx + Server.input_seat]
    test rax, rax
    jz .done
    mov r12d, [rax + InputSeat.x]       ; the tip
    mov r13d, [rax + InputSeat.y]
    mov [rsp], r12d
    mov [rsp + 4], r13d
    mov dword [rsp + 8], ARROW_W
    mov dword [rsp + 12], ARROW_H
    lea rdi, [rsp + 16]
    mov rdx, rsi
    mov rsi, rsp
    call rect_intersect
    test rax, rax
    jnz .done                           ; none of it in the clip
    mov r14d, [rsp + 20]                ; the first row shown
.row:
    mov eax, [rsp + 20]
    add eax, [rsp + 28]
    cmp r14d, eax
    jge .done
    mov eax, r14d
    sub eax, r13d
    lea rcx, [rel arrow_ink]
    movzx r8d, word [rcx + rax * 2]
    lea rcx, [rel arrow_fill]
    movzx r9d, word [rcx + rax * 2]
    movsxd rax, r14d                    ; the row's first pixel
    imul rax, [rbx + FrameCtx.stride]
    add rax, [rbx + FrameCtx.framebuffer]
    mov r15d, [rsp + 16]                ; the first column shown
.column:
    mov ecx, [rsp + 16]
    add ecx, [rsp + 24]
    cmp r15d, ecx
    jge .next_row
    mov ecx, r15d
    sub ecx, r12d
    movsxd rdx, r15d
    bt r8d, ecx
    jnc .not_ink
    mov dword [rax + rdx * 4], ARROW_INK
    jmp .next_column
.not_ink:
    bt r9d, ecx
    jnc .next_column
    mov dword [rax + rdx * 4], ARROW_FILL
.next_column:
    inc r15d
    jmp .column
.next_row:
    inc r14d
    jmp .row
.done:
    xor eax, eax
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; sw_cursor_moved
;   The pointer moved: where the arrow was and where it is are redrawn
;   IN:  rdi = server*, esi, edx = where it was, ecx, r8d = where it is
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_cursor_moved
sw_cursor_moved:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 24                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12d, ecx
    mov r13d, r8d
    mov rax, [rbx + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    mov qword [rax + Compositor.cursor_hidden], 0   ; a move shows it
    mov [rsp], esi
    mov [rsp + 4], edx
    mov dword [rsp + 8], ARROW_W
    mov dword [rsp + 12], ARROW_H
    mov rdi, rbx
    mov rsi, rsp
    call compositor_damage_rect
    mov [rsp], r12d
    mov [rsp + 4], r13d
    mov rdi, rbx
    mov rsi, rsp
    call compositor_damage_rect
.done:
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; sw_cursor_hide
;   Typing: the arrow goes, where it was redrawn, until the pointer moves
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_cursor_hide
sw_cursor_hide:
    sub rsp, 24                         ; a rect; 16-byte aligned
    mov rax, [rdi + Server.compositor]
    test rax, rax
    jz .done
    cmp qword [rax + Compositor.cursor_on], 0
    je .done
    cmp qword [rax + Compositor.cursor_hidden], 0
    jne .done                           ; gone already
    mov qword [rax + Compositor.cursor_hidden], 1
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .done
    mov ecx, [rax + InputSeat.x]
    mov [rsp], ecx
    mov ecx, [rax + InputSeat.y]
    mov [rsp + 4], ecx
    mov dword [rsp + 8], ARROW_W
    mov dword [rsp + 12], ARROW_H
    mov rsi, rsp
    call compositor_damage_rect
.done:
    xor eax, eax
    add rsp, 24
    ret

section .rodata
align 2
arrow_ink:      dw 0x0001, 0x0003, 0x0005, 0x0009, 0x0011, 0x0021, 0x0041, 0x0081, 0x0101, 0x0201, 0x07C1, 0x0049, 0x0095, 0x0093, 0x0121, 0x0120, 0x00C0
arrow_fill:     dw 0x0000, 0x0000, 0x0002, 0x0006, 0x000E, 0x001E, 0x003E, 0x007E, 0x00FE, 0x01FE, 0x003E, 0x0036, 0x0062, 0x0060, 0x00C0, 0x00C0, 0x0000

section .data
global sw_cursor_version
sw_cursor_version: dq 0x010000
