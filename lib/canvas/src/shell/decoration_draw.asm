; ============================================================================
; Decoration Draw — Server-Side Decoration Rendering
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/shell.inc"
%include "inc/struct_offsets.inc"
%include "inc/pixbuf.inc"
%include "inc/externs.inc"

extern canvas_icon_draw

; the built-in icon for each button type (BTN_CLOSE .. BTN_MENU)
%define DECOR_ICON_TYPES    4

section .rodata
decor_icon_close:       db "x"
decor_icon_maximize:    db "square"
decor_icon_minimize:    db "minus"
decor_icon_menu:        db "menu"
align 8
decor_icons:
    dq decor_icon_close, 1
    dq decor_icon_maximize, 6
    dq decor_icon_minimize, 5
    dq decor_icon_menu, 4
decor_three_quarters:   dq 0.75
decor_half:             dq 0.5
decor_one:              dq 1.0

section .text

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
    mov dword [rbx + DecorationDrawState_titlebar_color], 0xFF2D2D2D  ; Dark gray
    mov dword [rbx + DecorationDrawState_border_color], 0xFF1A1A1A    ; Darker gray
    mov dword [rbx + DecorationDrawState_button_bg_color], 0xFF3D3D3D ; Medium gray
    mov dword [rbx + DecorationDrawState_button_fg_color], 0xFFFFFFFF ; White
    mov dword [rbx + DecorationDrawState_inactive_alpha], 0x80808080  ; 50% alpha

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

    mov rax,[r12 + Decoration.toplevel]
    test rax,rax
    jz .invalid
    mov r14d,[rax + Toplevel.width]
    mov r15d,[rax + Toplevel.height]
    test r14d,r14d
    jz .invalid
    test r15d,r15d
    jz .invalid
    mov r10,[rbx + DecorationDrawState.stride]
    test r10,r10
    jnz .stride_ok
    mov r10d,r14d
    shl r10,2
.stride_ok:
    mov r11d,[r12 + Decoration.titlebar_height]
    cmp r11d,r15d
    cmova r11d,r15d
    mov r9d,[r12 + Decoration.border_width]

    mov rdi,r13
    mov esi,[rbx + DecorationDrawState.titlebar_color]
    mov edx,r14d
    mov ecx,r11d
    mov r8,r10
    call fill_solid
    test r9d,r9d
    jz .title
    mov rdi,r13
    mov esi,[rbx + DecorationDrawState.border_color]
    mov edx,r9d
    mov ecx,r15d
    mov r8,r10
    call fill_solid
    mov eax,r14d
    sub eax,r9d
    lea rdi,[r13+rax*4]
    mov esi,[rbx + DecorationDrawState.border_color]
    mov edx,r9d
    mov ecx,r15d
    mov r8,r10
    call fill_solid
    mov eax,r15d
    sub eax,r9d
    imul rax,r10
    lea rdi,[r13+rax]
    mov esi,[rbx + DecorationDrawState.border_color]
    mov edx,r14d
    mov ecx,r9d
    mov r8,r10
    call fill_solid

.title:
    ; Compact built-in 3x7 glyph marks keep titles visible without requiring
    ; a loaded external font during early shell startup.
    mov rax,[r12 + Decoration.toplevel]
    mov r15,[rax + Toplevel.title]
    test r15,r15
    jz .buttons
    mov r14d,8
.char:
    movzx eax,byte [r15]
    test al,al
    jz .buttons
    mov rdx,[r12 + Decoration.toplevel]
    mov edx,[rdx + Toplevel.width]
    lea ecx,[r14+4]
    cmp ecx,edx
    jae .buttons
    cmp al,' '
    je .char_next
    mov edx,r14d
    lea rdi,[r13+rdx*4]
    lea rdi,[rdi+r10*8]
    mov esi,[rbx + DecorationDrawState.button_fg_color]
    mov edx,3
    mov ecx,7
    mov r8,r10
    call fill_solid
.char_next:
    add r14d,5
    inc r15
    jmp .char

.buttons:
    mov r15,[r12 + Decoration.buttons]
    mov r14d,[r12 + Decoration.button_count]
.button_loop:
    test r15,r15
    jz .ok
    test r14d,r14d
    jz .ok
    mov r11d,[r12 + Decoration.titlebar_height]
    sub r11d,4
    cmp r11d,4
    jae .button_size_ok
    mov r11d,4
.button_size_ok:
    mov eax,r11d
    add eax,2
    imul eax,r14d
    mov rdx,[r12 + Decoration.toplevel]
    mov edx,[rdx + Toplevel.width]
    sub edx,2
    sub edx,eax
    mov [r15],edx
    mov dword [r15+4],2
    mov [r15+8],r11d
    mov [r15+12],r11d
    mov rdi,rbx
    mov rsi,r15
    mov rdx,r13
    call decoration_draw_button
    mov r15,[r15+40]
    dec r14d
    jmp .button_loop
.ok:

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; ---------------------------------------------------------------------------
; decoration_draw_button
;   Draw a single button: its background, then its type's icon (x, square,
;   minus, menu from the built-in pack) at 3/4 of its height, centred, in
;   the foreground colour.
;   IN:  rdi = decoration_draw_state*, rsi = button, rdx = framebuffer
; ---------------------------------------------------------------------------
global decoration_draw_button
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
    mov r14, [rbx + DecorationDrawState_button_bg_color]
    mov r15, [rbx + DecorationDrawState_button_fg_color]
    jmp .draw

.hover:
    mov r14, [rbx + DecorationDrawState_button_bg_color]
    mov r15, [rbx + DecorationDrawState_button_fg_color]
    jmp .draw

.pressed:
    mov r14, [rbx + DecorationDrawState_button_bg_color]
    mov r15, [rbx + DecorationDrawState_button_fg_color]
    jmp .draw

.disabled:
    mov r14, [rbx + DecorationDrawState_button_bg_color]
    mov r15, [rbx + DecorationDrawState_button_fg_color]
    jmp .draw

.draw:
    mov eax,[r12]
    mov ecx,[r12+4]
    mov edx,[r12+8]
    mov r8d,[r12+12]
    test edx,edx
    jle .invalid
    test r8d,r8d
    jle .invalid
    mov r9,[rbx + DecorationDrawState.stride]
    test r9,r9
    jnz .have_stride
    mov r9d,[rbx + DecorationDrawState.width]
    shl r9,2
.have_stride:
    imul rcx,r9
    lea rdi,[r13+rcx]
    lea rdi,[rdi+rax*4]
    mov rsi,r14
    mov ecx,r8d
    mov r8,r9
    push r9
    sub rsp,8
    call fill_solid
    add rsp,8
    pop r9
    ; the icon
    mov eax,[r12 + DecorationButton.type]
    cmp eax,DECOR_ICON_TYPES
    jae .no_icon
    ; the framebuffer as a PixBuf (rows down to the button's bottom at least)
    sub rsp,PixBuf_SIZE
    mov ecx,[rbx + DecorationDrawState.width]
    mov [rsp + PixBuf_width],rcx
    mov ecx,[rbx + DecorationDrawState.height]
    mov edx,[r12+4]
    add edx,[r12+12]
    cmp ecx,edx
    cmovb ecx,edx
    mov [rsp + PixBuf_height],rcx
    mov [rsp + PixBuf_stride],r9
    mov qword [rsp + PixBuf_format],0
    mov [rsp + PixBuf_data],r13
    imul rcx,r9
    mov [rsp + PixBuf_size],rcx
    mov qword [rsp + PixBuf_refcount],1
    mov qword [rsp + PixBuf_arena],0
    ; the square: 3/4 of the button's height, centred in the button
    cvtsi2sd xmm2,dword [r12+12]
    mulsd xmm2,[rel decor_three_quarters]
    cvtsi2sd xmm0,dword [r12+8]
    subsd xmm0,xmm2
    mulsd xmm0,[rel decor_half]
    cvtsi2sd xmm3,dword [r12]
    addsd xmm0,xmm3
    cvtsi2sd xmm1,dword [r12+12]
    subsd xmm1,xmm2
    mulsd xmm1,[rel decor_half]
    cvtsi2sd xmm3,dword [r12+4]
    addsd xmm1,xmm3
    movsd xmm3,[rel decor_one]
    lea rdx,[rel decor_icons]
    shl eax,4
    mov rsi,[rdx + rax]
    mov edx,[rdx + rax + 8]
    mov rdi,rsp
    mov ecx,r15d
    call canvas_icon_draw
    add rsp,PixBuf_SIZE
.no_icon:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global decoration_draw_version
decoration_draw_version: dq 0x010000
