; ============================================================================
; Client Buffer Helpers — create/destroy/mmap helpers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_buffer_create
canvas_buffer_create:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + ClientConn.next_obj]
    inc dword [rbx + ClientConn.next_obj]
    ret

global canvas_buffer_destroy
canvas_buffer_destroy:
    PROLOGUE
    xor rax, rax
    ret

global canvas_buffer_mmap
canvas_buffer_mmap:
    PROLOGUE
    ; rdi=conn, rsi=buffer -> rax = cpu pointer
    ; TODO: resolve via server buffer table
    xor rax, rax
    ret

global canvas_buffer_stride
canvas_buffer_stride:
    PROLOGUE
    ; TODO: query stride
    mov eax, 0
    ret

section .data
global canvas_buffer_helpers_version
canvas_buffer_helpers_version: dq 0x010000
