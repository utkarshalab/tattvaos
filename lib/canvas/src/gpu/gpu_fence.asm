; ============================================================================
; GPU Fence — Timeline Semaphores Backed by Ring Sequence Numbers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc GpuFenceMgr {
    .gpu:           resq 1
    .signaled_gfx:  resq 1
    .signaled_compute: resq 1
    .signaled_sdma: resq 1
}
%define GpuFenceMgr_size    32

; ---------------------------------------------------------------------------
; gpu_fence_init
; ---------------------------------------------------------------------------
global gpu_fence_init
gpu_fence_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, GpuFenceMgr_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + GpuFenceMgr.gpu], r12
    mov qword [rbx + GpuFenceMgr.signaled_gfx], 0
    mov qword [rbx + GpuFenceMgr.signaled_compute], 0
    mov qword [rbx + GpuFenceMgr.signaled_sdma], 0
    mov qword [r12 + GpuDevice.fence_mgr], rbx
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; gpu_fence_emit
;   Emit fence write into ring tail; returns seq
; ---------------------------------------------------------------------------
global gpu_fence_emit
gpu_fence_emit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; packet: FENCE_WRITE (family-specific opcode filled by family code)
    mov rdi, rbx
    call gpu_ring_submit
    ; seq in rax; record pending (signaled on IRQ in real driver)
    ret

; ---------------------------------------------------------------------------
; gpu_fence_wait
;   IN: rdi = gpu*, rsi = ring type, rdx = seq, rcx = timeout_ns
; ---------------------------------------------------------------------------
global gpu_fence_wait
gpu_fence_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    mov rax, [rbx + GpuDevice.fence_mgr]
    test rax, rax
    jz .fail
    mov rbx, rax
    ; pick signaled counter
    cmp r12, 1
    je .compute
    cmp r12, 2
    je .sdma
    lea rax, [rbx + GpuFenceMgr.signaled_gfx]
    jmp .wait
.compute:
    lea rax, [rbx + GpuFenceMgr.signaled_compute]
    jmp .wait
.sdma:
    lea rax, [rbx + GpuFenceMgr.signaled_sdma]
.wait:
    mov rbx, rax
    call tv_time_now_ns
    mov r12, rax
    add r12, r14
.poll:
    cmp [rbx], r13
    jae .done
    ; TODO: kick IRQ-poll update of signaled counters
    call tv_time_now_ns
    cmp rax, r12
    jae .timeout
    call tv_wait_yield
    jmp .poll
.done:
    xor rax, rax
    ret
.timeout:
    RETURN_ERROR ETIMEDOUT
.fail:
    RETURN_ERROR ENXIO

; ---------------------------------------------------------------------------
; gpu_fence_signal_irq
;   Called from GPU completion IRQ with new seq
; ---------------------------------------------------------------------------
global gpu_fence_signal_irq
gpu_fence_signal_irq:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; rsi = ring type, rdx = seq
    mov rax, [rbx + GpuDevice.fence_mgr]
    test rax, rax
    jz .done
    cmp rsi, 1
    je .compute
    cmp rsi, 2
    je .sdma
    cmp [rax + GpuFenceMgr.signaled_gfx], rdx
    jae .done
    mov [rax + GpuFenceMgr.signaled_gfx], rdx
    ret
.compute:
    cmp [rax + GpuFenceMgr.signaled_compute], rdx
    jae .done
    mov [rax + GpuFenceMgr.signaled_compute], rdx
    ret
.sdma:
    cmp [rax + GpuFenceMgr.signaled_sdma], rdx
    jae .done
    mov [rax + GpuFenceMgr.signaled_sdma], rdx
.done:
    xor rax, rax
    ret

section .data
global gpu_fence_version
gpu_fence_version: dq 0x010000
