; ============================================================================
; Client Shell Helpers — cw_toplevel, cw_popup, cw_layer (proto/canvas-shell.cwp)
; ============================================================================
; Windows, popups and layers, each named by its surface, and the window
; list, which names windows by id. Windows and popups need the shell
; capability, layers the layer capability, the window list the windows
; capability. Size limits are not in the protocol yet: those return -ENOSYS.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern canvas_send

section .text

; ---------------------------------------------------------------------------
; canvas_toplevel_create
;   Make a surface a window; a configure event follows
;   IN:  rdi = conn, esi = surface
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_create
canvas_toplevel_create:
    mov edx, TOPLEVEL_CREATE
    jmp surface_request

; ---------------------------------------------------------------------------
; canvas_toplevel_destroy
;   IN:  rdi = conn, esi = surface
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_destroy
canvas_toplevel_destroy:
    mov edx, TOPLEVEL_DESTROY
    jmp surface_request

; ---------------------------------------------------------------------------
; canvas_toplevel_ack_configure
;   IN:  rdi = conn, esi = surface, edx = the configure's serial
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_ack_configure
canvas_toplevel_ack_configure:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, CWP_OBJ_TOPLEVEL
    mov edx, TOPLEVEL_ACK_CONFIGURE
    mov rcx, rsp
    mov r8d, 8
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_toplevel_set_title
; canvas_toplevel_set_app_id
;   IN:  rdi = conn, esi = surface, rdx = UTF-8 bytes, ecx = length
;   OUT: rax = 0, -EINVAL if longer than WINDOW_NAME_MAX, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_set_title
canvas_toplevel_set_title:
    mov r8d, TOPLEVEL_SET_TITLE
    jmp name_request

global canvas_toplevel_set_app_id
canvas_toplevel_set_app_id:
    mov r8d, TOPLEVEL_SET_APP_ID
    jmp name_request

; ---------------------------------------------------------------------------
; canvas_popup_create
;   A popup at (x, y) on its parent; it gets done when the parent goes
;   IN:  rdi = conn, esi = surface, edx = parent surface, ecx = x, r8d = y
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_popup_create
canvas_popup_create:
    mov r9d, (CWP_OBJ_POPUP << 16) | POPUP_CREATE
    jmp four_request

; ---------------------------------------------------------------------------
; canvas_layer_create
;   A layer; a configure event with its size follows
;   IN:  rdi = conn, esi = surface, edx = layer (CANVAS_LAYER_*),
;        ecx = anchors (CANVAS_ANCHOR_*), r8d = margin
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_layer_create
canvas_layer_create:
    mov r9d, (CWP_OBJ_LAYER << 16) | LAYER_CREATE
    jmp four_request

; ---------------------------------------------------------------------------
; canvas_popup_destroy
; canvas_layer_destroy
;   IN:  rdi = conn, esi = surface
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_popup_destroy
canvas_popup_destroy:
    sub rsp, 24
    mov [rsp], esi
    mov esi, CWP_OBJ_POPUP
    mov edx, POPUP_DESTROY
    jmp one_request

global canvas_layer_destroy
canvas_layer_destroy:
    sub rsp, 24
    mov [rsp], esi
    mov esi, CWP_OBJ_LAYER
    mov edx, LAYER_DESTROY
    jmp one_request

; ---------------------------------------------------------------------------
; canvas_toplevel_set_state
;   Ask for maximized and fullscreen set or cleared as the bits say
;   IN:  rdi = conn, esi = surface, edx = CANVAS_STATE_* bits
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_set_state
canvas_toplevel_set_state:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov edx, TOPLEVEL_UNSET_MAXIMIZED
    test r13d, CANVAS_STATE_MAXIMIZED
    jz .max
    mov edx, TOPLEVEL_SET_MAXIMIZED
.max:
    call surface_request
    test rax, rax
    js .out
    mov rdi, rbx
    mov esi, r12d
    mov edx, TOPLEVEL_UNSET_FULLSCREEN
    test r13d, CANVAS_STATE_FULLSCREEN
    jz .full
    mov edx, TOPLEVEL_SET_FULLSCREEN
.full:
    call surface_request
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; canvas_toplevel_set_minimized
;   IN:  rdi = conn, esi = surface
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_set_minimized
canvas_toplevel_set_minimized:
    mov edx, TOPLEVEL_SET_MINIMIZED
    jmp surface_request

; ---------------------------------------------------------------------------
; canvas_toplevel_set_decorated
;   A title bar drawn by the server, or none
;   IN:  rdi = conn, esi = surface, edx = 1 on, 0 off
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_toplevel_set_decorated
canvas_toplevel_set_decorated:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, CWP_OBJ_TOPLEVEL
    mov edx, TOPLEVEL_SET_DECORATED
    mov rcx, rsp
    mov r8d, 8
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_layer_set_exclusive
;   Keep a strip along the layer's edge from maximized windows
;   IN:  rdi = conn, esi = surface, edx = its width (0: none)
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_layer_set_exclusive
canvas_layer_set_exclusive:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, CWP_OBJ_LAYER
    mov edx, LAYER_SET_EXCLUSIVE
    mov rcx, rsp
    mov r8d, 8
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_layer_set_output
;   Put the layer on another output: the nth, 0 the first
;   IN:  rdi = conn, esi = surface, edx = the output's number
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_layer_set_output
canvas_layer_set_output:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, CWP_OBJ_LAYER
    mov edx, LAYER_SET_OUTPUT
    mov rcx, rsp
    mov r8d, 8
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_window_list_subscribe
;   window events for every window, then activated, then every change
;   IN:  rdi = conn
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_window_list_subscribe
canvas_window_list_subscribe:
    sub rsp, 24
    mov esi, CWP_OBJ_WINDOW_LIST
    mov edx, WINDOW_LIST_SUBSCRIBE
    mov rcx, rsp
    xor r8d, r8d
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_window_activate, canvas_window_close, canvas_window_minimize
;   IN:  rdi = conn, esi = the window's id (from a window event)
;   OUT: rax = 0, negative error
; canvas_window_set_maximized
;   IN:  rdi = conn, esi = id, edx = 1 maximized, 0 not
; ---------------------------------------------------------------------------
global canvas_window_activate
canvas_window_activate:
    mov r9d, WINDOW_LIST_ACTIVATE
    jmp id_request

global canvas_window_close
canvas_window_close:
    mov r9d, WINDOW_LIST_CLOSE
    jmp id_request

global canvas_window_minimize
canvas_window_minimize:
    mov r9d, WINDOW_LIST_MINIMIZE
    jmp id_request

global canvas_window_set_maximized
canvas_window_set_maximized:
    mov r9d, WINDOW_LIST_SET_MAXIMIZED
    jmp id_request

; ---------------------------------------------------------------------------
; canvas_window_list_set_workspace
;   IN:  rdi = conn, esi = the workspace to show
; canvas_window_move_to_workspace
;   IN:  rdi = conn, esi = a window's id, edx = the workspace
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_window_list_set_workspace
canvas_window_list_set_workspace:
    mov r9d, WINDOW_LIST_SET_WORKSPACE
    jmp id_request

global canvas_window_move_to_workspace
canvas_window_move_to_workspace:
    mov r9d, WINDOW_LIST_MOVE_TO_WORKSPACE
    jmp id_request

; Not in the protocol yet
global canvas_toplevel_set_min_size
global canvas_toplevel_set_max_size
canvas_toplevel_set_min_size:
canvas_toplevel_set_max_size:
    mov rax, -(ENOSYS)
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; Four dwords (esi, edx, ecx, r8d); r9d = interface << 16 | request.
four_request:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov esi, r9d
    shr esi, 16
    movzx edx, r9w
    mov rcx, rsp
    mov r8d, 16
    call canvas_send
    add rsp, 24
    ret

; The surface already at [rsp], 24 bytes reserved: the rest of a one-dword
; request; esi = interface, edx = request.
one_request:
    mov rcx, rsp
    mov r8d, 4
    call canvas_send
    add rsp, 24
    ret

; A cw_window_list request: (id, edx); r9d = the request.
id_request:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, CWP_OBJ_WINDOW_LIST
    mov edx, r9d
    mov rcx, rsp
    mov r8d, 8                          ; (id, value)
    cmp edx, WINDOW_LIST_SET_MAXIMIZED
    je .send
    cmp edx, WINDOW_LIST_MOVE_TO_WORKSPACE
    je .send
    mov r8d, 4                          ; (id) or (index)
.send:
    call canvas_send
    add rsp, 24
    ret

; A request carrying only the surface.
; rdi = conn, esi = surface, edx = request -> rax
surface_request:
    sub rsp, 24
    mov [rsp], esi
    mov esi, CWP_OBJ_TOPLEVEL
    mov rcx, rsp
    mov r8d, 4
    call canvas_send
    add rsp, 24
    ret

; (surface, length, bytes).
; rdi = conn, esi = surface, rdx = bytes, ecx = length, r8d = request -> rax
name_request:
    cmp ecx, WINDOW_NAME_MAX
    ja .too_long
    push rbx
    sub rsp, 80                         ; 8 + WINDOW_NAME_MAX, rounded
    mov ebx, r8d
    mov [rsp], esi
    mov [rsp + 4], ecx
    mov r8d, ecx
    add r8d, 8                          ; the payload's bytes
    mov r9, rdi
    lea rdi, [rsp + 8]
    mov rsi, rdx
    mov ecx, ecx
    rep movsb
    mov rdi, r9
    mov esi, CWP_OBJ_TOPLEVEL
    mov edx, ebx
    mov rcx, rsp
    call canvas_send
    add rsp, 80
    pop rbx
    ret
.too_long:
    mov rax, -(EINVAL)
    ret

section .data
global canvas_shell_helpers_version
canvas_shell_helpers_version: dq 0x020000
