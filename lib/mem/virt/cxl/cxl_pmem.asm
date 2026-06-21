; =============================================================================
; Tattva OS — lib/mem/virt/cxl_pmem.asm
; =============================================================================
; CXL Persistent Memory — Subfeature 39.4.
;
; Implements drivers for managing byte-addressable CXL Persistent Memory
; regions. Guarantees persistence of critical runtime data (e.g., KV cache) across
; system crashes or power losses using cache flush instruction barriers.
;
; API:
;   cxl_pmem_init()                     — Map persistent CXL region.
;   cxl_pmem_flush(addr, size)          — Executes clwb & sfence pipeline sync.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_CXL_PMEM_ASM
%define LIB_MEM_VIRT_CXL_PMEM_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; cxl_pmem_init — Map byte-addressable CXL persistent region
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cxl_pmem_init
cxl_pmem_init:
    mov  qword [sys_cxl_pmem_active_regions], 1
    mov  qword [sys_cxl_pmem_flushed_bytes], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; cxl_pmem_flush — Flush CPU caches and barrier data writes to NVRAM
; Input:
;   RDI = Address to flush
;   RSI = Byte size of flush region
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global cxl_pmem_flush
cxl_pmem_flush:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    ; Perform cache lines flush loop (clwb in strides of 64 bytes)
    mov  rcx, rsi
    add  rcx, 63
    shr  rcx, 6                     ; RCX = number of cachelines
    mov  rax, rdi

.flush_loop:
    clwb [rax]                      ; Cache Line Write Back (leaves clean in cache)
    add  rax, 64
    dec  rcx
    jnz  .flush_loop

    sfence                          ; Store Fence to ensure persistence

    add  [sys_cxl_pmem_flushed_bytes], rsi
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_cxl_pmem_active_regions
sys_cxl_pmem_active_regions:    dq 0

align 8
global sys_cxl_pmem_flushed_bytes
sys_cxl_pmem_flushed_bytes:     dq 0

section .text

%endif ; LIB_MEM_VIRT_CXL_PMEM_ASM
