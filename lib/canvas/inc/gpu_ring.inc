; ============================================================================
; GPU Ring — the command ring's layout (src/gpu/gpu_ring.asm owns it)
; ============================================================================

%ifndef GPU_RING_INC
%define GPU_RING_INC

%define GPU_RING_DEFAULT_DW   4096  ; 16KB

struc GpuRing
    .gpu:           resq 1
    .buf_cpu:       resq 1          ; the ring, size_dw dwords
    .buf_dma:       resq 1
    .doorbell:      resq 1          ; 0: none (completion is immediate)
    .fence_next:    resq 1
    .type:          resd 1          ; 0 gfx, 1 compute, 2 sdma
    .size_dw:       resd 1
    .wptr:          resd 1          ; in dwords, 0 .. size_dw - 1
    .rptr_shadow:   resd 1
endstruc

%endif
