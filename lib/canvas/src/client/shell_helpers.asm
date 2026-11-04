; ============================================================================
; Client Shell Helpers — cw_toplevel, cw_popup, cw_layer (proto/canvas-shell.cwp)
; ============================================================================
; Windows, popups and layers, each named by its surface. Windows and popups
; need the shell capability, layers the layer capability. Window states and
; size limits are not in the protocol yet: those return -ENOSYS.

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

; Not in the protocol yet
global canvas_toplevel_set_state
global canvas_toplevel_set_min_size
global canvas_toplevel_set_max_size
canvas_toplevel_set_state:
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
