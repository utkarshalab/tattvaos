; ============================================================================
; Decoration Management — Server-Side Titlebars, Borders, Buttons
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; decoration_create_for_toplevel
;   Create server-side decoration for toplevel
; ============================================================================
global decoration_create_for_toplevel
decoration_create_for_toplevel:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi  ; toplevel*
    ASSERT_PTR rbx

    ; Allocate decoration struct
    mov rdi, 64  ; DECORATION_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax  ; decoration

    ; Initialize decoration
    mov qword [rax + DECORATION_TOPLEVEL], rbx
    mov dword [rax + DECORATION_MODE], DECORATION_MODE_SERVER

    ; Get theme from server
    mov r13, [rbx + TOPLEVEL_SHELL]
    mov r13, [r13 + SHELL_THEME]
    mov qword [r12 + DECORATION_THEME], r13

    ; Create standard buttons: close, maximize, minimize
    call .create_standard_buttons

    ; Set default dimensions
    mov r13, [r12 + DECORATION_THEME]
    mov eax, [r13 + THEME_TITLEBAR_H]
    mov dword [r12 + DECORATION_TITLEBAR_H], eax
    mov eax, [r13 + THEME_BORDER_W]
    mov dword [r12 + DECORATION_BORDER_W], eax

    ; Link to toplevel
    mov qword [rbx + TOPLEVEL_DECORATION], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.create_standard_buttons:
    ; Create close button
    call .create_button
    mov byte [rax + DECOR_BTN_TYPE], BTN_CLOSE

    ; Create maximize button
    call .create_button
    mov byte [rax + DECOR_BTN_TYPE], BTN_MAXIMIZE

    ; Create minimize button
    call .create_button
    mov byte [rax + DECOR_BTN_TYPE], BTN_MINIMIZE

    ; Set button count to 3
    mov dword [r12 + DECORATION_BUTTON_COUNT], 3
    ret

.create_button:
    ; Allocate button
    mov rdi, 40  ; DECOR_BTN_SIZE
    call arena_alloc
    test rax, rax
    jz .btn_oom

    ; Initialize button
    mov dword [rax + DECOR_BTN_STATE], BTN_NORMAL
    mov qword [rax + DECOR_BTN_CALLBACK], 0
    mov qword [rax + DECOR_BTN_USER_DATA], 0

    ; Add to decoration's button list
    mov rdx, [r12 + DECORATION_BUTTONS]
    mov [rax + DECOR_BTN_NEXT], rdx
    mov [r12 + DECORATION_BUTTONS], rax

    ret

.btn_oom:
    xor rax, rax
    ret

; ============================================================================
; decoration_destroy
;   Destroy decoration
; ============================================================================
global decoration_destroy
decoration_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Free buttons
    mov r12, [rbx + DECORATION_BUTTONS]
.btn_loop:
    test r12, r12
    jz .btns_done
    mov rax, [r12 + DECOR_BTN_NEXT]
    ; Arena handles free
    mov r12, rax
    jmp .btn_loop
.btns_done:

    ; Arena handles struct
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; decoration_set_mode
;   Set decoration mode (server/client/none)
; ============================================================================
global decoration_set_mode
decoration_set_mode:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp esi, DECORATION_MODE_SERVER
    je .valid
    cmp esi, DECORATION_MODE_CLIENT
    je .valid
    cmp esi, DECORATION_MODE_NONE
    je .valid
    mov rax, -EINVAL
    leave
    ret

.valid:
    mov dword [rbx + DECORATION_MODE], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; decoration_get_titlebar_height
;   Get titlebar height
; ============================================================================
global decoration_get_titlebar_height
decoration_get_titlebar_height:
    PROLOGUE
    mov eax, [rdi + DECORATION_TITLEBAR_H]
    leave
    ret

; ============================================================================
; decoration_get_border_width
;   Get border width
; ============================================================================
global decoration_get_border_width
decoration_get_border_width:
    PROLOGUE
    mov eax, [rdi + DECORATION_BORDER_W]
    leave
    ret

; ============================================================================
; decoration_hit_test
;   Hit test for decoration (returns which part was hit)
; ============================================================================
global decoration_hit_test
decoration_hit_test:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi  ; x
    mov r13d, edx  ; y
    ASSERT_PTR rbx

    ; Check titlebar
    mov eax, [rbx + DECORATION_TITLEBAR_H]
    cmp r13d, eax
    jge .check_border

    ; In titlebar area - check buttons
    mov r12, [rbx + DECORATION_BUTTONS]
    mov r13d, [rbx + DECORATION_BUTTON_COUNT]
.btn_loop:
    test r13d, r13d
    jz .titlebar_bg
    push r13
    mov r13, [r12 + DECOR_BTN_RECT]
    mov r14d, [r13 + Rect_x]
    mov r15d, [r13 + Rect_y]
    mov r14d, [r13 + Rect_width]
    mov r15d, [r13 + Rect_height]
    pop r13

    ; Check if hit
    mov eax, r12d
    sub eax, r14d
    cmp eax, r14d
    jge .not_this_btn
    mov eax, r13d
    sub eax, r15d
    cmp eax, r15d
    jge .not_this_btn

    ; Hit button - return type
    movzx eax, byte [r12 + DECOR_BTN_TYPE]
    jmp .hit

.not_this_btn:
    mov r12, [r12 + DECOR_BTN_NEXT]
    dec r13d
    jmp .btn_loop

.titlebar_bg:
    mov eax, 100  ; Titlebar background
    jmp .hit

.check_border:
    ; Check borders
    mov eax, [rbx + DECORATION_BORDER_W]
    mov r12d, [rbx + DECORATION_TOPLEVEL]
    mov r13, [r12 + TOPLEVEL_WIDTH]
    mov r14d, [r12 + TOPLEVEL_HEIGHT]

    ; Left border
    cmp r12d, eax
    jge .check_right
    mov eax, 200  ; Left border
    jmp .hit

.check_right:
    sub r13d, eax
    cmp r12d, r13d
    jl .check_top
    mov eax, 201  ; Right border
    jmp .hit

.check_top:
    mov eax, [rbx + DECORATION_TITLEBAR_H]
    add eax, [rbx + DECORATION_BORDER_W]
    cmp r13d, eax
    jge .check_bottom
    mov eax, 202  ; Top border
    jmp .hit

.check_bottom:
    sub r13d, [rbx + DECORATION_BORDER_W]
    cmp r13d, r14d
    jl .client
    mov eax, 203  ; Bottom border
    jmp .hit

.client:
    mov eax, 0  ; Client area

.hit:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; decoration_render
;   Render decoration to pixbuf
; ============================================================================
global decoration_render
decoration_render:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi  ; pixbuf
    mov r13d, edx ; x offset
    mov r14d, ecx ; y offset
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get theme colors
    mov r15, [rbx + DECORATION_THEME]
    mov r15, [r15 + THEME_COLORS]

    ; Get dimensions
    mov eax, [rbx + DECORATION_TOPLEVEL]
    mov r12, rax
    mov r13d, [r12 + TOPLEVEL_WIDTH]
    mov r14d, [r12 + TOPLEVEL_HEIGHT]
    mov r15d, [rbx + DECORATION_TITLEBAR_H]
    mov r13d, [rbx + DECORATION_BORDER_W]

    ; Render titlebar background
    call .render_rect
    ; Render buttons
    call .render_buttons
    ; Render borders
    call .render_borders

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.render_rect:
    ; Render rectangle helper
    ret

.render_buttons:
    ret

.render_borders:
    ret

; ============================================================================
; decoration_button_callback
;   Handle button click
; ============================================================================
global decoration_button_callback
decoration_button_callback:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi  ; button type
    ASSERT_PTR rbx

    cmp r12d, BTN_CLOSE
    je .close
    cmp r12d, BTN_MAXIMIZE
    je .maximize
    cmp r12d, BTN_MINIMIZE
    je .minimize

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.close:
    ; Close toplevel
    mov rax, [rbx + DECORATION_TOPLEVEL]
    call toplevel_destroy
    jmp .done

.maximize:
    ; Toggle maximize
    mov rax, [rbx + DECORATION_TOPLEVEL]
    mov eax, [rax + TOPLEVEL_STATE]
    test eax, TOPLEVEL_STATE_MAXIMIZED
    jz .do_maximize

    ; Restore
    mov eax, [rax + TOPLEVEL_STATE]
    and eax, ~TOPLEVEL_STATE_MAXIMIZED
    mov dword [rax + TOPLEVEL_PENDING_STATE], eax
    jmp .schedule

.do_maximize:
    mov eax, [rax + TOPLEVEL_STATE]
    or eax, TOPLEVEL_STATE_MAXIMIZED
    mov dword [rax + TOPLEVEL_PENDING_STATE], eax

.schedule:
    mov rax, [rbx + DECORATION_TOPLEVEL]
    call toplevel_schedule_configure

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.minimize:
    ; Minimize - set state
    mov rax, [rbx + DECORATION_TOPLEVEL]
    mov eax, [rax + TOPLEVEL_STATE]
    or eax, TOPLEVEL_STATE_MINIMIZED
    mov dword [rax + TOPLEVEL_PENDING_STATE], eax
    call toplevel_schedule_configure
    jmp .done

section .data
global decoration_version
decoration_version: dq 0x010000