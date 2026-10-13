; ============================================================================
; Client Surface Helpers — create/destroy/attach/damage/commit/frame
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_surface_create
canvas_surface_create:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + ClientConn.next_obj]
    inc dword [rbx + ClientConn.next_obj]
    EPILOGUE_RESTORE rbx
    ret

global canvas_surface_destroy
canvas_surface_destroy:
    PROLOGUE
    xor rax, rax
    leave
    ret

global canvas_surface_attach
canvas_surface_attach:
    PROLOGUE
    xor rax, rax
    leave
    ret

global canvas_surface_damage
canvas_surface_damage:
    PROLOGUE
    xor rax, rax
    leave
    ret

global canvas_surface_commit
canvas_surface_commit:
    PROLOGUE
    xor rax, rax
    leave
    ret

global canvas_frame_request
canvas_frame_request:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global canvas_surface_helpers_version
canvas_surface_helpers_version: dq 0x010000
