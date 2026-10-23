; ============================================================================
; GPU Memory — GTT/VRAM Placement, Buffer Objects, Tiling Flags
; Unified memory preferred (APU); discrete VRAM via ut_dma
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define GpuMemMgr_SIZE 56
%define GpuBo_SIZE 64
%define GPU_PLACE_GTT      1
%define GPU_PLACE_VRAM     2
%define GPU_PLACE_VISIBLE   4
%define GPU_TILING_LINEAR  0
%define GPU_TILING_TILED   1

section .text

struc GpuMemMgr
    .gpu:           resq 1
    .total_bytes:   resq 1
    .used_bytes:    resq 1
    .gtt_base:      resq 1
    .vram_base:     resq 1
    .bos:           resq 1
    .bo_count:      resq 1
endstruc

struc GpuBo
    .size:          resq 1
    .align:         resq 1
    .cpu_addr:      resq 1
    .dma_addr:      resq 1
    .handle:        resq 1
    .placement:     resd 1
    .tiling:        resd 1
    .refcount:      resd 1
    .next:          resq 1
endstruc



; ---------------------------------------------------------------------------
; gpu_mem_init
; ---------------------------------------------------------------------------
global gpu_mem_init
gpu_mem_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, GpuMemMgr_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + GpuMemMgr.gpu], r12
    mov qword [rbx + GpuMemMgr.total_bytes], 256 * 1024 * 1024
    mov qword [rbx + GpuMemMgr.used_bytes], 0
    mov qword [rbx + GpuMemMgr.gtt_base], 0
    mov qword [rbx + GpuMemMgr.vram_base], 0
    mov qword [rbx + GpuMemMgr.bos], 0
    mov qword [rbx + GpuMemMgr.bo_count], 0
    mov qword [r12 + GpuDevice.mem_mgr], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; gpu_bo_create
;   IN: rdi = gpu*, rsi = size, rdx = align, rcx = placement
;   OUT: rax = GpuBo*
; ---------------------------------------------------------------------------
global gpu_bo_create
gpu_bo_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    test r12, r12
    jz .invalid
    mov r15, [rbx + GpuDevice.mem_mgr]
    test r15, r15
    jz .fail
    ; quota check
    mov rax, [r15 + GpuMemMgr.used_bytes]
    add rax, r12
    cmp rax, [r15 + GpuMemMgr.total_bytes]
    ja .oom
    ; alloc BO header from server arena
    mov rax, [rbx + GpuDevice.server]
    mov rdi, [rax + Server.arena]
    mov rsi, GpuBo_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    ; DMA buffer
    mov rdi, r12
    mov rsi, r13
    call ut_dma_alloc
    test rax, rax
    js .oom
    mov [rbx + GpuBo.cpu_addr], rax
    mov [rbx + GpuBo.dma_addr], rdx
    mov [rbx + GpuBo.handle], r8
    mov [rbx + GpuBo.size], r12
    mov [rbx + GpuBo.align], r13
    mov [rbx + GpuBo.placement], r14d
    mov dword [rbx + GpuBo.tiling], GPU_TILING_LINEAR
    mov dword [rbx + GpuBo.refcount], 1
    ; link
    mov rax, [r15 + GpuMemMgr.bos]
    mov [rbx + GpuBo.next], rax
    mov [r15 + GpuMemMgr.bos], rbx
    inc qword [r15 + GpuMemMgr.bo_count]
    add [r15 + GpuMemMgr.used_bytes], r12
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; gpu_bo_ref / gpu_bo_unref
; ---------------------------------------------------------------------------
global gpu_bo_ref
gpu_bo_ref:
    PROLOGUE
    ASSERT_PTR rdi
    lock inc dword [rdi + GpuBo.refcount]
    mov rax, rdi
    leave
    ret

global gpu_bo_unref
gpu_bo_unref:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    lock dec dword [rbx + GpuBo.refcount]
    jnz .done
    mov rdi, [rbx + GpuBo.handle]
    call ut_dma_free
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; gpu_bo_sync
; ---------------------------------------------------------------------------
global gpu_bo_sync
gpu_bo_sync:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, [rbx + GpuBo.handle]
    mov rsi, 0
    mov rdx, [rbx + GpuBo.size]
    mov rcx, DMA_BIDIR
    call ut_dma_sync
    EPILOGUE_RESTORE rbx
    ret

section .data
global gpu_mem_version
gpu_mem_version: dq 0x010000
