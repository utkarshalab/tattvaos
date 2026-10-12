; ============================================================================
; Client Shell Helpers — Toplevel/Popup/Layer Conveniences
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_toplevel_create
canvas_toplevel_create:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + ClientConn.next_obj]
    inc dword [rbx + ClientConn.next_obj]
    ret

global canvas_toplevel_set_title
canvas_toplevel_set_title:
    PROLOGUE
    xor rax, rax
    ret

global canvas_toplevel_set_app_id
canvas_toplevel_set_app_id:
    PROLOGUE
    xor rax, rax
    ret

global canvas_toplevel_set_state
canvas_toplevel_set_state:
    PROLOGUE
    xor rax, rax
    ret

global canvas_toplevel_set_min_size
canvas_toplevel_set_min_size:
    PROLOGUE
    xor rax, rax
    ret

global canvas_toplevel_set_max_size
canvas_toplevel_set_max_size:
    PROLOGUE
    xor rax, rax
    ret

global canvas_popup_create
canvas_popup_create:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + ClientConn.next_obj]
    inc dword [rbx + ClientConn.next_obj]
    ret

global canvas_layer_create
canvas_layer_create:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + ClientConn.next_obj]
    inc dword [rbx + ClientConn.next_obj]
    ret

section .data
global canvas_shell_helpers_version
canvas_shell_helpers_version: dq 0x010000
