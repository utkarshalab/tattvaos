; ============================================================================
; Client Buffer Helpers — create/destroy/mmap helpers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

%define CLIENT_BUFFER_COUNT  80
%define CLIENT_BUFFER_TABLE  256
%define CLIENT_BUFFER_MAX    128
%define CLIENT_BUFFER_SIZE   48
%define CB_ID                0
%define CB_WIDTH             4
%define CB_HEIGHT            8
%define CB_FORMAT            12
%define CB_STRIDE            16
%define CB_BYTES             24
%define CB_DATA              32
%define CB_REGION            40

global canvas_buffer_create
canvas_buffer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    test r12d, r12d
    jz .create_fail
    test r13d, r13d
    jz .create_fail
    mov rax, [rbx + CLIENT_BUFFER_COUNT]
    cmp rax, CLIENT_BUFFER_MAX
    jae .create_fail
    imul rdx, rax, CLIENT_BUFFER_SIZE
    lea rdx, [rbx + rdx + CLIENT_BUFFER_TABLE]
    mov eax, r12d
    imul rax, r13
    jo .create_fail
    shl rax, 2
    jo .create_fail
    mov [rdx + CB_BYTES], rax
    mov rdi, rax
    add rdi, 4095
    and rdi, -4096
    xor esi, esi
    push rdx
    call tv_mem_alloc
    pop rdx
    test rax, rax
    js .create_fail
    mov [rdx + CB_DATA], rax
    mov [rdx + CB_REGION], r8
    mov eax, [rbx + ClientConn.next_obj]
    inc dword [rbx + ClientConn.next_obj]
    mov [rdx + CB_ID], eax
    mov [rdx + CB_WIDTH], r12d
    mov [rdx + CB_HEIGHT], r13d
    mov [rdx + CB_FORMAT], r14d
    mov ecx, r12d
    shl ecx, 2
    mov [rdx + CB_STRIDE], ecx
    inc qword [rbx + CLIENT_BUFFER_COUNT]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.create_fail:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

global canvas_buffer_destroy
canvas_buffer_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    call canvas_find_buffer
    test rax, rax
    jz .not_found
    mov rdi, [rax + CB_REGION]
    push rax
    call tv_mem_free
    pop rdx
    test rax, rax
    js .destroy_out
    mov dword [rdx + CB_ID], 0
.destroy_out:
    EPILOGUE_RESTORE rbx, r12
    ret
.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

global canvas_buffer_mmap
canvas_buffer_mmap:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    call canvas_find_buffer
    test rax, rax
    jz .mmap_out
    mov rax, [rax + CB_DATA]
.mmap_out:
    EPILOGUE_RESTORE rbx, r12
    ret

global canvas_buffer_stride
canvas_buffer_stride:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    call canvas_find_buffer
    test rax, rax
    jz .stride_out
    mov eax, [rax + CB_STRIDE]
.stride_out:
    EPILOGUE_RESTORE rbx, r12
    ret

canvas_find_buffer:
    xor ecx, ecx
    mov rdx, [rbx + CLIENT_BUFFER_COUNT]
.find_loop:
    cmp rcx, rdx
    jae .find_none
    imul rax, rcx, CLIENT_BUFFER_SIZE
    lea rax, [rbx + rax + CLIENT_BUFFER_TABLE]
    cmp [rax + CB_ID], r12d
    je .find_done
    inc rcx
    jmp .find_loop
.find_none:
    xor eax, eax
.find_done:
    ret

section .data
global canvas_buffer_helpers_version
canvas_buffer_helpers_version: dq 0x010000
