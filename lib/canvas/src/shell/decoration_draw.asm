; ============================================================================
; Decoration Draw — Server-Side Decoration Rendering
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/color.inc"
%include "inc/shell.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

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
;   Draw a single button
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
    call fill_solid
    ; Draw a centered control mark.
    mov eax,[r12]
    add eax,4
    mov ecx,[r12+4]
    mov edx,[r12+12]
    shr edx,1
    add ecx,edx
    imul rcx,r9
    lea rdi,[r13+rcx]
    lea rdi,[rdi+rax*4]
    mov rsi,r15
    mov edx,[r12+8]
    sub edx,8
    cmp edx,1
    jge .mark_width
    mov edx,1
.mark_width:
    mov ecx,2
    mov r8,r9
    call fill_solid
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
