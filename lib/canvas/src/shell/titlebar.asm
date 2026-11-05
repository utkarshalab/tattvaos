; ============================================================================
; Title Bar — Server-Drawn Decorations for Windows That Ask
; ============================================================================
; A window with cw_toplevel.set_decorated gets a bar TITLEBAR_H high right
; above it and as wide as its buffer, with three square buttons at its right
; end: minimize, maximize, close. None while it is fullscreen. The compositor
; draws the bar just before the window, so it stacks with it; input asks
; titlebar_part what a point is on. The window's title is written on the bar
; in the embedded font, left of the buttons. The bar of the window with the
; keyboard is brighter; titlebar_focus_changed redraws the two bars a focus
; change touches.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/ui_text.inc"

extern handle_resolve
extern region_add_rect
extern rect_intersect
extern sw_render_rect
extern ui_text_draw

%define BAR_COLOR       0xFF2C3248      ; a window without the keyboard
%define BAR_ACTIVE      0xFF3E4C78      ; the one with it
%define CLOSE_COLOR     0xFFC04848
%define MAXIMIZE_COLOR  0xFF54A24B
%define MINIMIZE_COLOR  0xFFC0A040
%define TITLE_COLOR     0xD0D4E0
%define TITLE_SIZE      13
%define TITLE_PAD       8               ; the title from the bar's left edge

; A button's left edge from the bar's right edge: the nth from the right
%define BUTTON_FROM_RIGHT(n) ((n) * (TITLEBAR_BUTTON + TITLEBAR_MARGIN) + TITLEBAR_BUTTON + TITLEBAR_MARGIN)

section .text

; ---------------------------------------------------------------------------
; titlebar_rect
;   Where a surface's bar is, if it has one now
;   IN:  rdi = surface*, rsi = rect* (x, y, width, height) to fill
;   OUT: rax = 1 with the rect filled, 0 if it has no bar
; ---------------------------------------------------------------------------
global titlebar_rect
titlebar_rect:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    mov r13, [rbx + Surface.window]
    test r13, r13
    jz .out
    cmp dword [r13 + Window.kind], ROLE_TOPLEVEL
    jne .none
    cmp dword [r13 + Window.decorated], 0
    je .none
    test dword [r13 + Window.state], WINDOW_FULLSCREEN
    jnz .none
    mov rsi, [rbx + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .none                            ; nothing shown, no bar
    mov rdi, [r13 + Window.server]
    mov rdi, [rdi + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .none
    mov ecx, [rbx + Surface.current + SurfaceState.buf_x]
    mov [r12], ecx
    mov ecx, [rbx + Surface.current + SurfaceState.buf_y]
    sub ecx, TITLEBAR_H
    mov [r12 + 4], ecx
    mov ecx, [rax + Buffer.width]
    mov [r12 + 8], ecx
    mov dword [r12 + 12], TITLEBAR_H
    mov eax, 1
    jmp .out
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; titlebar_part
;   What a point on the output is on, of a surface's bar
;   IN:  rdi = surface*, esi = x, edx = y
;   OUT: rax = TITLEBAR_BAR, _CLOSE, _MAXIMIZE, _MINIMIZE, 0 if not on it
; ---------------------------------------------------------------------------
global titlebar_part
titlebar_part:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; the bar
    mov ebx, esi
    mov r12d, edx
    mov rsi, rsp
    call titlebar_rect
    test eax, eax
    jz .out
    xor eax, eax
    mov ecx, ebx                        ; x across the bar
    sub ecx, [rsp]
    js .out
    cmp ecx, [rsp + 8]
    jae .out
    mov edx, r12d                       ; y down it
    sub edx, [rsp + 4]
    js .out
    cmp edx, TITLEBAR_H
    jae .out
    mov eax, TITLEBAR_BAR
    cmp edx, TITLEBAR_MARGIN            ; the buttons' row
    jb .out
    cmp edx, TITLEBAR_MARGIN + TITLEBAR_BUTTON
    jae .out
    mov r8d, [rsp + 8]
    sub r8d, ecx                        ; from the right edge
%macro BUTTON 2                         ; nth from the right, part
    cmp r8d, BUTTON_FROM_RIGHT(%1)
    ja %%no
    cmp r8d, BUTTON_FROM_RIGHT(%1) - TITLEBAR_BUTTON
    jbe %%no
    mov eax, %2
    jmp .out
%%no:
%endmacro
    BUTTON 0, TITLEBAR_CLOSE
    BUTTON 1, TITLEBAR_MAXIMIZE
    BUTTON 2, TITLEBAR_MINIMIZE
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; titlebar_focus_changed
;   The keyboard moved: the bars of the window it left and the one it went
;   to need redrawing, their colours changing
;   IN:  rdi = server*, rsi = surface* it left (0: none), rdx = surface* it
;        went to (0: none)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global titlebar_focus_changed
titlebar_focus_changed:
    PROLOGUE_SAVE rbx
    sub rsp, 24                         ; a bar; 16-byte aligned
    mov rbx, rdx
    mov rdi, rsi
    call damage_bar
    mov rdi, rbx
    call damage_bar
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx

; A surface's bar, if it has one, into its output's damage. Called from
; titlebar_focus_changed's frame: the rect goes at its rsp.
; rdi = surface or 0
damage_bar:
    test rdi, rdi
    jz .out
    mov rax, [rdi + Surface.output]
    test rax, rax
    jz .out                             ; not on an output: nothing shown
    push rax                            ; 16-byte aligned
    lea rsi, [rsp + 16]                 ; titlebar_focus_changed's rsp
    call titlebar_rect
    pop rcx
    test eax, eax
    jz .out
    mov rdi, [rcx + Output.damage]
    lea rsi, [rsp + 8]
    jmp region_add_rect
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; titlebar_render
;   A surface's bar and buttons, inside a clip rectangle
;   IN:  rdi = frame context, rsi = surface*, rdx = clip rect*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global titlebar_render
titlebar_render:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 56 + UiText_size           ; bar, a button, clipped, the title
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, rsp
    call titlebar_rect
    test eax, eax
    jz .out
    mov esi, BAR_COLOR
    mov rax, [r12 + Surface.window]
    mov rax, [rax + Window.server]
    mov rax, [rax + Server.input_seat]
    test rax, rax
    jz .colour
    cmp [rax + InputSeat.keyboard_focus], r12
    jne .colour
    mov esi, BAR_ACTIVE
.colour:
    mov rdi, rsp
    call paint
    call draw_title
%macro DRAW_BUTTON 2                    ; nth from the right, colour
    mov eax, [rsp + 8]
    sub eax, BUTTON_FROM_RIGHT(%1)
    js %%skip                           ; a bar too narrow for it
    add eax, [rsp]
    mov [rsp + 16], eax
    mov eax, [rsp + 4]
    add eax, TITLEBAR_MARGIN
    mov [rsp + 20], eax
    mov dword [rsp + 24], TITLEBAR_BUTTON
    mov dword [rsp + 28], TITLEBAR_BUTTON
    lea rdi, [rsp + 16]
    mov esi, %2
    call paint
%%skip:
%endmacro
    DRAW_BUTTON 0, CLOSE_COLOR
    DRAW_BUTTON 1, MAXIMIZE_COLOR
    DRAW_BUTTON 2, MINIMIZE_COLOR
.out:
    xor eax, eax
    add rsp, 56 + UiText_size
    EPILOGUE_RESTORE rbx, r12, r13

; The window's title on the bar, left of the buttons, inside the clip.
; rbx = frame context, r12 = surface, r13 = clip; titlebar_render's rsp holds
; the bar, its rsp + 56 the UiText
%define TITLE_AT    (8 + 56)            ; past the return address
draw_title:
    mov rax, [r12 + Surface.window]
    mov ecx, [rax + Window.title_len]
    test ecx, ecx
    jz .done
    lea rdx, [rsp + TITLE_AT]
    mov [rdx + UiText.length], ecx
    lea rcx, [rax + Window.title]
    mov [rdx + UiText.text], rcx
    mov rax, [rbx + FrameCtx.framebuffer]
    mov [rdx + UiText.pixels], rax
    mov rax, [rbx + FrameCtx.stride]
    mov [rdx + UiText.stride], rax
    mov eax, [rsp + 8]                  ; the bar
    add eax, TITLE_PAD
    mov [rdx + UiText.x], eax
    mov eax, [rsp + 8 + 4]
    mov [rdx + UiText.y], eax
    mov eax, [rsp + 8 + 8]
    sub eax, TITLE_PAD + BUTTON_FROM_RIGHT(2) + TITLEBAR_MARGIN
    jle .done                           ; no room left of the buttons
    mov [rdx + UiText.width], eax
    mov dword [rdx + UiText.height], TITLEBAR_H
    mov eax, [r13]                      ; the clip
    mov [rdx + UiText.clip_x], eax
    mov eax, [r13 + 4]
    mov [rdx + UiText.clip_y], eax
    mov eax, [r13 + 8]
    mov [rdx + UiText.clip_w], eax
    mov eax, [r13 + 12]
    mov [rdx + UiText.clip_h], eax
    mov dword [rdx + UiText.size], TITLE_SIZE
    mov dword [rdx + UiText.colour], TITLE_COLOR
    mov rdi, rdx
    sub rsp, 8                          ; 16-byte aligned
    call ui_text_draw
    add rsp, 8
.done:
    ret

; A rectangle of one colour, the part inside the clip.
; rdi = rect, esi = colour; rbx = frame context, r13 = clip, called from
; titlebar_render's frame (the clipped rect goes at its rsp + 32)
%define CLIPPED (8 + 8 + 32)            ; past r14 and the return address
paint:
    push r14                            ; 16-byte aligned again
    mov r14d, esi
    mov rsi, rdi
    lea rdi, [rsp + CLIPPED]
    mov rdx, r13
    call rect_intersect
    test rax, rax
    jnz .out                            ; nothing of it inside
    mov rdi, rbx
    lea rsi, [rsp + CLIPPED]
    mov edx, r14d
    call sw_render_rect
.out:
    pop r14
    ret
