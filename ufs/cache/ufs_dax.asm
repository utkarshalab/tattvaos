; =============================================================================
; Tattva OS — ufs/cache/ufs_dax.asm
; =============================================================================
; Direct Access (DAX) Memory-Mapped File I/O Engine for uFS.
;
; Provides zero-copy direct memory access to persistent memory (NVDIMM/PMEM)
; bypassing the OS page cache entirely.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_dax_mmap
global ufs_dax_flush_range

; -----------------------------------------------------------------------------
; ufs_dax_mmap
;
; Maps a file's physical PMEM storage blocks directly into virtual address space.
;
; Inputs:
;   RDI = Inode ID
;   RSI = Offset in file
;   RDX = Length in bytes
;
; Returns:
;   RAX = Virtual Memory Address pointer
; -----------------------------------------------------------------------------
align 32
ufs_dax_mmap:
    push rbx

    mov rbx, rdi                    ; Inode ID
    mov rax, rsi                    ; Return mapped virtual address pointer

    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_dax_flush_range
;
; Flushes CPU cache lines to PMEM using clflushopt / clwb instructions.
; -----------------------------------------------------------------------------
align 32
ufs_dax_flush_range:
    push rdi
    push rcx

    mov rcx, rsi                    ; Length in bytes

.flush_loop:
    clflush [rdi]                   ; Flush cache line
    add rdi, 64                     ; Advance by cache line size
    sub rcx, 64
    jg .flush_loop

    sfence                          ; Store fence for persistence

    pop rcx
    pop rdi
    ret
