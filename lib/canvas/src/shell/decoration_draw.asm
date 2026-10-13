; ============================================================================
; Decoration Draw — Server-Side Decoration Rendering
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"

; struct offsets (hoisted above use)
%define DecorationDrawState_size    48

section .text

struc DecorationDrawState
    .framebuffer:       resq 1
    .stride:            resq 1
    .width:             resd 1
    .height:            resd 1
    .titlebar_color:    resd 1
    .border_color:      resd 1
    .button_bg_color:   resd 1
    .button_fg_color:   resd 1
    .inactive_alpha:    resd 1
endstruc

; ---------------------------------------------------------------------------
; decoration_draw_init
; ---------------------------------------------------------------------------
global decoration_draw_init
decoration_draw_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Default theme colors (active)
    mov dword [rbx + DecorationDrawState.titlebar_color], 0xFF2D2D2D  ; Dark gray
    mov dword [rbx + DecorationDrawState.border_color], 0xFF1A1A1A    ; Darker gray
    mov dword [rbx + DecorationDrawState.button_bg_color], 0xFF3D3D3D ; Medium gray
    mov dword [rbx + DecorationDrawState.button_fg_color], 0xFFFFFFFF ; White
    mov dword [rbx + DecorationDrawState.inactive_alpha], 0x80808080  ; 50% alpha

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; decoration_draw_frame
;   Draw window frame (borders + titlebar + buttons)
;   IN:  rdi = decoration_draw_state*, rsi = decoration*, rdx = framebuffer
; ---------------------------------------------------------------------------
global decoration_draw_frame
decoration_draw_frame:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get toplevel geometry
    mov rax, [r12 + Decoration.toplevel]
    mov r14, [rax + Toplevel.surface]
    mov r15, [r14 + Surface.current]

    ; Get dimensions
    mov eax, [r15 + SurfaceState.width]
    mov r14d, eax
    mov eax, [r15 + SurfaceState.height]
    mov r15d, eax

    ; Get decoration metrics
    mov eax, [r12 + Decoration.titlebar_height]
    mov r12d, eax
    mov eax, [r12 + Decoration.border_width]
    mov r13d, eax

    ; Draw top border (titlebar)
    mov rdi, rdx
    mov rsi, [rbx + DecorationDrawState.titlebar_color]
    mov rdx, r14d
    mov rcx, r12d
    mov r8, r14d
    shl r8, 2
    call fill_solid

    ; Draw left border
    mov rdi, rdx
    add rdi, r12d
    shl r12d, 2
    add rdi, r12d
    mov rsi, [rbx + DecorationDrawState.border_color]
    mov rdx, r13d
    mov rcx, r15d
    sub rcx, r12d
    mov r8, r14d
    shl r8, 2
    call fill_solid

    ; Draw right border
    mov rdi, rdx
    mov eax, [r15 + SurfaceState.width]
    sub eax, r13d
    shl eax, 2
    add rdi, rax
    mov rsi, [rbx + DecorationDrawState.border_color]
    mov rdx, r13d
    mov rcx, r15d
    sub rcx, r12d
    mov r8, r14d
    shl r8, 2
    call fill_solid

    ; Draw bottom border
    mov rdi, rdx
    mov eax, [r15 + SurfaceState.height]
    sub eax, r13d
    imul eax, [r15 + SurfaceState.stride]
    add rdi, rax
    mov rsi, [rbx + DecorationDrawState.border_color]
    mov rdx, r14d
    mov rcx, r13d
    mov r8, r14d
    shl r8, 2
    call fill_solid

    ; Draw titlebar text
    ; TODO: Draw title text

    ; Draw buttons
    ; TODO: Draw close/maximize/minimize buttons

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; decoration_draw_button
;   Draw a single button
; ---------------------------------------------------------------------------
decoration_draw_button:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get button colors based on state
    mov eax, [r12 + DecorationButton.state]
    cmp eax, BUTTON_STATE_HOVER
    je .hover
    cmp eax, BUTTON_STATE_PRESSED
    je .pressed
    cmp eax, BUTTON_STATE_DISABLED
    je .disabled

.normal:
    mov r14, [rbx + DecorationDrawState.button_bg_color]
    mov r15, [rbx + DecorationDrawState.button_fg_color]
    jmp .draw

.hover:
    ; Slightly lighter
    mov eax, [rbx + DecorationDrawState.button_bg_color]
    add eax, 0x202020
    mov r14, rax
    mov r15, [rbx + DecorationDrawState.button_fg_color]
    jmp .draw

.pressed:
    ; Darker
    mov eax, [rbx + DecorationDrawState.button_bg_color]
    sub eax, 0x202020
    mov r14, rax
    mov r15, [rbx + DecorationDrawState.button_fg_color]
    jmp .draw

.disabled:
    ; Dimmed
    mov eax, [rbx + DecorationDrawState.button_bg_color]
    and eax, 0x80808080
    mov r14, rax
    mov eax, [rbx + DecorationDrawState.button_fg_color]
    and eax, 0x80808080
    mov r15, rax
    jmp .draw

.draw:
    ; Draw button background
    mov rdi, r13
    mov rsi, r14
    mov rdx, [r12 + DecorationButton.width]
    mov rcx, [r12 + DecorationButton.height]
    mov r8, [r12 + DecorationButton.width]
    shl r8, 2
    call fill_solid

    ; Draw icon
    ; TODO: Draw button icon (close X, maximize square, minimize line)

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; decoration_draw_titlebar_text
;   Draw title text on titlebar
; ---------------------------------------------------------------------------
decoration_draw_titlebar_text:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get title
    mov rax, [r12 + Decoration.toplevel]
    mov rax, [rax + Toplevel.title]
    test rax, rax
    jz .no_title

    ; TODO: Render text using font subsystem

.no_title:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; decoration_set_colors
;   Set custom colors for decoration drawing
; ---------------------------------------------------------------------------
global decoration_set_colors
decoration_set_colors:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov [rbx + DecorationDrawState.titlebar_color], esi
    mov [rbx + DecorationDrawState.border_color], edx
    mov [rbx + DecorationDrawState.button_bg_color], ecx
    mov [rbx + DecorationDrawState.button_fg_color], r8d
    mov [rbx + DecorationDrawState.inactive_alpha], r9d

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; decoration_set_inactive_alpha
;   Set alpha for inactive window decorations
; ---------------------------------------------------------------------------
global decoration_set_inactive_alpha
decoration_set_inactive_alpha:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + DecorationDrawState.inactive_alpha], esi
    xor rax, rax
    leave
    ret

section .data
global decoration_draw_version
decoration_draw_version: dq 0x010000
