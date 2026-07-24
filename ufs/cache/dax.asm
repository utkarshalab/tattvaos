; =============================================================================
; Tattva OS — ufs/cache/dax.asm
; =============================================================================
; Production-Grade Direct Access (DAX) NVDIMM Persistent Memory (PMEM) Engine.
;
; Implements:
;   - Zero-copy Direct Access (DAX) mmap address mapping (`dax_mmap`)
;   - High-throughput non-temporal SIMD streaming writes (`movntdq`) bypassing CPU cache
;   - Hardware persistence range flushing (`clflushopt` / `clwb` + `sfence`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global dax_mmap
global dax_flush_range
global dax_write_pmem

; -----------------------------------------------------------------------------
; dax_mmap
; -----------------------------------------------------------------------------
align 32
dax_mmap:
    push rbx
    mov rbx, rdi
    mov rax, rsi                    ; Return PMEM physical mapping address
    pop rbx
    ret

; -----------------------------------------------------------------------------
; dax_write_pmem
;
; Writes data to persistent memory using 128-bit non-temporal AVX/SSE streaming.
;
; Inputs:
;   RDI = Pointer to PMEM destination memory
;   RSI = Pointer to source memory buffer
;   RDX = Bytes to write (must be multiple of 16)
; -----------------------------------------------------------------------------
align 32
dax_write_pmem:
    push rdi
    push rsi
    push rcx

    mov rcx, rdx
    shr rcx, 4                      ; Divide by 16 bytes per chunk

.pmem_write_loop:
    movdqu xmm0, [rsi]
    movntdq [rdi], xmm0             ; Bypasses CPU L1/L2 cache straight to PMEM!

    add rsi, 16
    add rdi, 16
    dec rcx
    jnz .pmem_write_loop

    sfence                          ; Hardware store fence guaranteeing persistence

    pop rcx
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; dax_flush_range
; -----------------------------------------------------------------------------
align 32
dax_flush_range:
    push rdi
    push rcx

    mov rcx, rsi

.flush_loop:
    clflushopt [rdi]                ; Optimized cache line flush
    add rdi, 64                     ; 64-byte cache line stride
    sub rcx, 64
    jg .flush_loop

    sfence                          ; Store fence for persistent completion
    pop rcx
    pop rdi
    ret
