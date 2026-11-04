; ============================================================================
; Client Shell Helpers — cw_toplevel requests (proto/canvas-shell.cwp)
; ============================================================================
; A window is named by its surface. They need the shell capability. Popups,
; layers, window states and size limits are not in the protocol yet: those
; return -ENOSYS.

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

; Not in the protocol yet
global canvas_toplevel_set_state
global canvas_toplevel_set_min_size
global canvas_toplevel_set_max_size
global canvas_popup_create
global canvas_layer_create
canvas_toplevel_set_state:
canvas_toplevel_set_min_size:
canvas_toplevel_set_max_size:
canvas_popup_create:
canvas_layer_create:
    mov rax, -(ENOSYS)
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

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
