; ============================================================================
; GPU Ring — Command Ring Allocation, Submission, Doorbell
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define GpuRing_size    64
%define GPU_RING_DEFAULT_DW   4096  ; 16KB

section .text

struc GpuRing
    .gpu:           resq 1
    .type:          resd 1
    .buf_cpu:       resq 1
    .buf_dma:       resq 1
    .size_dw:       resd 1
    .wptr:          resd 1
    .rptr_shadow:   resd 1
    .doorbell:      resq 1
    .fence_next:    resq 1
endstruc


; ---------------------------------------------------------------------------
; gpu_ring_init
;   IN: rdi = server*, rsi = gpu*, rdx = ring type
; ---------------------------------------------------------------------------
global gpu_ring_init
gpu_ring_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, GpuRing_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov qword [r14 + GpuRing.gpu], r12
    mov dword [r14 + GpuRing.type], r13d
    mov dword [r14 + GpuRing.size_dw], GPU_RING_DEFAULT_DW
    mov dword [r14 + GpuRing.wptr], 0
    mov dword [r14 + GpuRing.rptr_shadow], 0
    mov qword [r14 + GpuRing.doorbell], 0
    mov qword [r14 + GpuRing.fence_next], 1
    ; DMA-coherent buffer
    mov rdi, GPU_RING_DEFAULT_DW
    shl rdi, 2
    mov rsi, 4096
    call tv_dma_alloc
    test rax, rax
    js .oom
    mov [r14 + GpuRing.buf_cpu], rax
    mov [r14 + GpuRing.buf_dma], rdx
    ; attach to gpu
    cmp r13d, 0
    je .gfx
    cmp r13d, 1
    je .compute
    mov [r12 + GpuDevice.ring_sdma], r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.gfx:
    mov [r12 + GpuDevice.ring_gfx], r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.compute:
    mov [r12 + GpuDevice.ring_compute], r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gpu_ring_write
;   Append dwords to ring (no wrap check beyond capacity)
;   IN: rdi = ring*, rsi = dwords*, rdx = count
; ---------------------------------------------------------------------------
global gpu_ring_write
gpu_ring_write:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r14d, [rbx + GpuRing.wptr]
    mov eax, [rbx + GpuRing.size_dw]
    cmp r13, rax
    ja .full
.write:
    test r13, r13
    jz .done
    mov ecx, [rbx + GpuRing.size_dw]
    sub ecx, r14d
    cmp r13, rcx
    jbe .contig
    ; split write (wrap)
    mov rdi, [rbx + GpuRing.buf_cpu]
    lea rdi, [rdi + r14 * 4]
    mov rsi, r12
    mov rdx, rcx
    shl rdx, 2
    call memcopy
    shl rcx, 2
    add r12, rcx
    sub r13, rcx
    shr rcx, 2
    xor r14d, r14d
    jmp .write
.contig:
    mov rdi, [rbx + GpuRing.buf_cpu]
    lea rdi, [rdi + r14 * 4]
    mov rsi, r12
    mov rdx, r13
    shl rdx, 2
    call memcopy
    add r14d, r13d
    mov eax, [rbx + GpuRing.size_dw]
    cmp r14d, eax
    jb .store
    xor r14d, r14d
.store:
    mov [rbx + GpuRing.wptr], r14d
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gpu_ring_submit
;   Ring doorbell, return fence seq
; ---------------------------------------------------------------------------
global gpu_ring_submit
gpu_ring_submit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov eax, [rbx + GpuRing.wptr]
    mov rdx, [rbx + GpuRing.doorbell]
    test rdx, rdx
    jz .no_doorbell
    mov [rdx], eax
.no_doorbell:
    mov rax, [rbx + GpuRing.fence_next]
    inc qword [rbx + GpuRing.fence_next]
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; gpu_ring_wait_empty
; ---------------------------------------------------------------------------
global gpu_ring_wait_empty
gpu_ring_wait_empty:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ; poll rptr shadow with timeout
    mov ecx, 1000000
.poll:
    mov eax, [rbx + GpuRing.rptr_shadow]
    cmp eax, [rbx + GpuRing.wptr]
    je .empty
    ; TODO: update rptr_shadow from MMIO
    dec ecx
    jnz .poll
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12
    ret
.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global gpu_ring_version
gpu_ring_version: dq 0x010000
