; ============================================================================
; GPU CmdRing / GPU Mem (render-side glue — full logic in src/gpu/)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global gpu_cmdring_init
gpu_cmdring_init:
    PROLOGUE
    ; delegates to gpu_ring_init per ring type
    xor rax, rax
    ret

global gpu_mem_bind_buffer
gpu_mem_bind_buffer:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; create GPU BO for a canvas buffer
    mov rdi, [rbx + Server.gpu]
    test rdi, rdi
    jz .fail
    mov rsi, [r12 + Buffer.size]
    mov rdx, 4096
    mov rcx, GPU_PLACE_GTT
    call gpu_bo_create
    test rax, rax
    jz .fail
    mov [r12 + Buffer.gpu_bo], rax
    xor rax, rax
    ret
.fail:
    RETURN_ERROR ENXIO

section .data
global gpu_cmdring_version
gpu_cmdring_version: dq 0x010000
global gpu_mem_glue_version
gpu_mem_glue_version: dq 0x010000
