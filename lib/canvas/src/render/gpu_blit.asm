; ============================================================================
; GPU Blit — 2D Copy/Fill via SDMA Ring
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; gpu_blit_copy
;   IN: rdi=gpu*, rsi=dst_dma, rdx=src_dma, rcx=bytes
; ---------------------------------------------------------------------------
global gpu_blit_copy
gpu_blit_copy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + GpuDevice.ring_sdma]
    test r12, r12
    jz .fail
    mov rdi, r12
    call gfx9_emit_copy
    test rax, rax
    jnz .fail
    mov rdi, r12
    call gpu_ring_submit
    ; TODO: track fence seq
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; gpu_blit_fill
; ---------------------------------------------------------------------------
global gpu_blit_fill
gpu_blit_fill:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + GpuDevice.ring_sdma]
    test r12, r12
    jz .fail
    mov rdi, r12
    call gfx9_emit_fill
    test rax, rax
    jnz .fail
    mov rdi, r12
    call gpu_ring_submit
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global gpu_blit_version
gpu_blit_version: dq 0x010000
