; ============================================================================
; Decoration Management — Server-Side Titlebars, Borders, Buttons
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/rect.inc"

extern arena_alloc
extern toplevel_destroy
extern toplevel_schedule_configure

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
    mov qword [rax + Decoration.toplevel], rbx
    mov dword [rax + Decoration.mode], DECORATION_MODE_SERVER

    ; Get theme from server
    mov r13, [rbx + Toplevel.shell]
    mov r13, [r13 + Shell.theme]
    mov qword [r12 + Decoration.theme], r13

    ; Create standard buttons: close, maximize, minimize
    call .create_standard_buttons

    ; Set default dimensions
    mov r13, [r12 + Decoration.theme]
    mov eax, [r13 + THEME_TITLEBAR_H]
    mov dword [r12 + Decoration.titlebar_h], eax
    mov eax, [r13 + THEME_BORDER_W]
    mov dword [r12 + Decoration.border_w], eax

    ; Link to toplevel
    mov qword [rbx + Toplevel.decoration], r12

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
    mov dword [r12 + Decoration.button_count], 3
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
    mov rdx, [r12 + Decoration.buttons]
    mov [rax + DECOR_BTN_NEXT], rdx
    mov [r12 + Decoration.buttons], rax

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
    mov r12, [rbx + Decoration.buttons]
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
    mov dword [rbx + Decoration.mode], esi
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
    mov eax, [rdi + Decoration.titlebar_h]
    leave
    ret

; ============================================================================
; decoration_get_border_width
;   Get border width
; ============================================================================
global decoration_get_border_width
decoration_get_border_width:
    PROLOGUE
    mov eax, [rdi + Decoration.border_w]
    leave
    ret

; ============================================================================
; decoration_hit_test
;   Hit test for decoration
;   IN:  rdi = decoration*, rsi = x, rdx = y
;   OUT: rax = button type, 100 titlebar, 200 .. 203 left, right, top, bottom
;        border, 0 client area
; ============================================================================
global decoration_hit_test
decoration_hit_test:
    ASSERT_PTR rdi
    ; The titlebar: a button, or its background
    cmp edx, [rdi + Decoration.titlebar_h]
    jge .borders
    mov r8, [rdi + Decoration.buttons]
    mov ecx, [rdi + Decoration.button_count]
.button:
    test ecx, ecx
    jz .titlebar
    test r8, r8
    jz .titlebar
    mov eax, esi                        ; inside rect x, y, w, h (i32)?
    sub eax, [r8 + DECOR_BTN_RECT]
    jl .next_button
    cmp eax, [r8 + DECOR_BTN_RECT + 8]
    jge .next_button
    mov eax, edx
    sub eax, [r8 + DECOR_BTN_RECT + 4]
    jl .next_button
    cmp eax, [r8 + DECOR_BTN_RECT + 12]
    jge .next_button
    movzx eax, byte [r8 + DECOR_BTN_TYPE]
    ret
.next_button:
    mov r8, [r8 + DECOR_BTN_NEXT]
    dec ecx
    jmp .button
.titlebar:
    mov eax, 100
    ret

.borders:
    mov r8, [rdi + Decoration.toplevel]
    mov ecx, [rdi + Decoration.border_w]
    mov eax, 200                        ; left
    cmp esi, ecx
    jl .out
    mov r9d, [r8 + Toplevel.width]
    sub r9d, ecx
    mov eax, 201                        ; right
    cmp esi, r9d
    jge .out
    mov r9d, [rdi + Decoration.titlebar_h]
    add r9d, ecx
    mov eax, 202                        ; top, under the titlebar
    cmp edx, r9d
    jl .out
    mov r9d, [r8 + Toplevel.height]
    sub r9d, ecx
    mov eax, 203                        ; bottom
    cmp edx, r9d
    jge .out
    xor eax, eax                        ; client area
.out:
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
    mov r15, [rbx + Decoration.theme]
    mov r15, [r15 + Theme.colors]

    ; Get dimensions
    mov eax, [rbx + Decoration.toplevel]
    mov r12, rax
    mov r13d, [r12 + Toplevel.width]
    mov r14d, [r12 + Toplevel.height]
    mov r15d, [rbx + Decoration.titlebar_h]
    mov r13d, [rbx + Decoration.border_w]

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
    mov rax, [rbx + Decoration.toplevel]
    call toplevel_destroy
    jmp .done

.maximize:
    ; Toggle maximize
    mov rax, [rbx + Decoration.toplevel]
    mov eax, [rax + Toplevel.state]
    test eax, TOPLEVEL_STATE_MAXIMIZED
    jz .do_maximize

    ; Restore
    mov eax, [rax + Toplevel.state]
    and eax, ~TOPLEVEL_STATE_MAXIMIZED
    mov dword [rax + Toplevel.pending_state], eax
    jmp .schedule

.do_maximize:
    mov eax, [rax + Toplevel.state]
    or eax, TOPLEVEL_STATE_MAXIMIZED
    mov dword [rax + Toplevel.pending_state], eax

.schedule:
    mov rax, [rbx + Decoration.toplevel]
    call toplevel_schedule_configure

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.minimize:
    ; Minimize - set state
    mov rax, [rbx + Decoration.toplevel]
    mov eax, [rax + Toplevel.state]
    or eax, TOPLEVEL_STATE_MINIMIZED
    mov dword [rax + Toplevel.pending_state], eax
    call toplevel_schedule_configure
    jmp .done

section .data
global decoration_version
decoration_version: dq 0x010000
