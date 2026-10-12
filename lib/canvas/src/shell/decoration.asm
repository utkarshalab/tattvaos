; ============================================================================
; Decoration — Client/Server-Side Decoration Negotiation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Decoration {
    .toplevel:          resq 1
    .mode:              resd 1
    .theme:             resq 1
    .buttons:           resq 1
    .button_count:      resd 1
    .titlebar_height:   resd 1
    .border_width:      resd 1
    .draw_callback:     resq 1
}
%define Decoration_size    56

%define DECORATION_NONE       0
%define DECORATION_CLIENT     1
%define DECORATION_SERVER     2
%define DECORATION_SERVER_PREFERRED 3

%define DECORATION_BUTTON_CLOSE      0
%define DECORATION_BUTTON_MAXIMIZE   1
%define DECORATION_BUTTON_MINIMIZE   2
%define DECORATION_BUTTON_MENU       3

%define BUTTON_STATE_NORMAL     0
%define BUTTON_STATE_HOVER      1
%define BUTTON_STATE_PRESSED    2
%define BUTTON_STATE_DISABLED   3

; ---------------------------------------------------------------------------
; decoration_init
; ---------------------------------------------------------------------------
global decoration_init
decoration_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.decoration_theme], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; decoration_negotiate
;   Negotiate decoration mode with client
;   IN:  rdi = server*, rsi = toplevel*, rdx = client_preferred_mode
;   OUT: rax = negotiated_mode
; ---------------------------------------------------------------------------
global decoration_negotiate
decoration_negotiate:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Server preference: server-side decorations
    mov rax, DECORATION_SERVER

    ; Check client preference
    cmp r13d, DECORATION_CLIENT
    je .client_prefers_client
    cmp r13d, DECORATION_SERVER
    je .client_prefers_server
    cmp r13d, DECORATION_SERVER_PREFERRED
    je .server_preferred

    ; Default to server-side
    ret

.client_prefers_client:
    ; Client wants client-side - allow if no server policy against it
    mov rax, DECORATION_CLIENT
    ret

.client_prefers_server:
    ; Client wants server-side - good
    mov rax, DECORATION_SERVER
    ret

.server_preferred:
    ; Client prefers server but allows client fallback
    mov rax, DECORATION_SERVER
    ret

; ---------------------------------------------------------------------------
; decoration_create
;   Create decoration for toplevel
; ---------------------------------------------------------------------------
global decoration_create
decoration_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate decoration
    mov rdi, [rbx + Server.arena]
    mov rsi, Decoration_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Decoration.toplevel], r12
    mov dword [rbx + Decoration.mode], r13d
    mov qword [rbx + Decoration.theme], 0
    mov qword [rbx + Decoration.buttons], 0
    mov dword [rbx + Decoration.button_count], 0
    mov dword [rbx + Decoration.titlebar_height], 32
    mov dword [rbx + Decoration.border_width], 2
    mov qword [rbx + Decoration.draw_callback], 0

    ; Create default buttons (close, maximize, minimize)
    call decoration_create_buttons

    ; Attach to toplevel
    mov qword [r12 + Toplevel.decoration], rbx

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; decoration_create_buttons
; ---------------------------------------------------------------------------
decoration_create_buttons:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Close button
    call decoration_button_create
    test rax, rax
    jz .fail
    mov [rbx + Decoration.buttons], rax
    inc dword [rbx + Decoration.button_count]

    ; Maximize button
    call decoration_button_create
    test rax, rax
    jz .fail
    mov r12, [rbx + Decoration.buttons]
    mov [rax + DecorationButton.next], r12
    mov [rbx + Decoration.buttons], rax
    inc dword [rbx + Decoration.button_count]

    ; Minimize button
    call decoration_button_create
    test rax, rax
    jz .fail
    mov r12, [rbx + Decoration.buttons]
    mov [rax + DecorationButton.next], r12
    mov [rbx + Decoration.buttons], rax
    inc dword [rbx + Decoration.button_count]

    ret

.fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; decoration_button_create
; ---------------------------------------------------------------------------
decoration_button_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Allocate button
    mov rdi, [rbx + Decoration.toplevel]
    mov rdi, [rdi + Toplevel.shell]
    mov rdi, [rdi + Server.arena]
    mov rsi, DecorationButton_size
    call arena_alloc
    test rax, rax
    jz .oom

    mov rbx, rax
    mov qword [rbx + DecorationButton.toplevel], rdi
    mov dword [rbx + DecorationButton.type], 0
    mov dword [rbx + DecorationButton.state], BUTTON_STATE_NORMAL
    mov dword [rbx + DecorationButton.x], 0
    mov dword [rbx + DecorationButton.y], 0
    mov dword [rbx + DecorationButton.width], 28
    mov dword [rbx + DecorationButton.height], 28
    mov qword [rbx + DecorationButton.next], 0
    mov qword [rbx + DecorationButton.icon], 0

    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; decoration_destroy
; ---------------------------------------------------------------------------
global decoration_destroy
decoration_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Free buttons
    mov rax, [rbx + Decoration.buttons]
    test rax, rax
    jz .done
    ; TODO: Free button chain

.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; decoration_set_mode
; ---------------------------------------------------------------------------
global decoration_set_mode
decoration_set_mode:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Decoration.mode], esi
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; decoration_set_theme
; ---------------------------------------------------------------------------
global decoration_set_theme
decoration_set_theme:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Decoration.theme], r12

    ; Reload button icons
    ; TODO

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; decoration_get_geometry
;   Get decoration geometry (titlebar rect, button rects)
; ---------------------------------------------------------------------------
global decoration_get_geometry
decoration_get_geometry:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Titlebar rect
    mov eax, [rbx + Decoration.toplevel]
    mov r13, [rax + Toplevel.surface]
    mov eax, [r13 + Surface.current + SurfaceState.width]
    mov [rsi + 0], eax
    mov dword [rsi + 4], 0
    mov [rsi + 8], eax
    mov eax, [rbx + Decoration.titlebar_height]
    mov [rsi + 12], eax

    ; Button rects
    ; TODO: Calculate button positions

    xor rax, rax
    ret

section .data

%define Decoration_toplevel       0
%define Decoration_mode           8
%define Decoration_theme          16
%define Decoration_buttons        24
%define Decoration_button_count   32
%define Decoration_titlebar_height 36
%define Decoration_border_width   40
%define Decoration_draw_callback  48
%define Decoration_size           56

%define DecorationButton_toplevel  0
%define DecorationButton_type      8
%define DecorationButton_state     12
%define DecorationButton_x         16
%define DecorationButton_y         20
%define DecorationButton_width     24
%define DecorationButton_height    28
%define DecorationButton_next      32
%define DecorationButton_icon      40
%define DecorationButton_size      48

global decoration_version
decoration_version: dq 0x010000