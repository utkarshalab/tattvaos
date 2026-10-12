; ============================================================================
; Client Buffer Pool — Double-Buffering Pool (acquire/release)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

struc ClientBufPool {
    .conn:          resq 1
    .width:         resd 1
    .height:        resd 1
    .format:        resd 1
    .bufs:          resd 4
    .busy:          resb 4
    .count:         resd 1
}
%define ClientBufPool_size    48

global canvas_buffer_pool_create
canvas_buffer_pool_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov rdi, [rbx + ClientConn.arena]
    mov rsi, ClientBufPool_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rax + ClientBufPool.conn], rbx
    mov dword [rax + ClientBufPool.width], r12d
    mov dword [rax + ClientBufPool.height], edx
    mov dword [rax + ClientBufPool.format], ecx
    mov dword [rax + ClientBufPool.count], 0
    ret
.oom:
    RETURN_ERROR ENOMEM

global canvas_buffer_pool_acquire
canvas_buffer_pool_acquire:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    ; find free slot
    xor r12d, r12d
.find:
    cmp r12d, 4
    jae .create_new
    cmp byte [rbx + ClientBufPool.busy + r12], 0
    je .found
    inc r12d
    jmp .find
.found:
    mov byte [rbx + ClientBufPool.busy + r12], 1
    mov eax, [rbx + ClientBufPool.bufs + r12 * 4]
    test eax, eax
    jnz .have
.create_new:
    ; create buffer via server
    mov rdi, [rbx + ClientBufPool.conn]
    mov esi, [rbx + ClientBufPool.width]
    mov edx, [rbx + ClientBufPool.height]
    mov ecx, [rbx + ClientBufPool.format]
    call canvas_buffer_create
    test eax, eax
    jz .fail
    mov r12d, 0
    cmp dword [rbx + ClientBufPool.count], 4
    jae .have2
    mov r12d, [rbx + ClientBufPool.count]
    inc dword [rbx + ClientBufPool.count]
.have2:
    mov [rbx + ClientBufPool.bufs + r12 * 4], eax
    mov byte [rbx + ClientBufPool.busy + r12], 1
.have:
    ret
.fail:
    xor eax, eax
    ret

global canvas_buffer_pool_release
canvas_buffer_pool_release:
    PROLOGUE
    ASSERT_PTR rdi
    cmp esi, 4
    jae .fail
    mov byte [rdi + ClientBufPool.busy + rsi], 0
    xor rax, rax
    ret
.fail:
    RETURN_ERROR EINVAL

section .data
global canvas_buffer_pool_version
canvas_buffer_pool_version: dq 0x010000
