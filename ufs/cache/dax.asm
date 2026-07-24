; =============================================================================
; Tattva OS — ufs/cache/dax.asm
; =============================================================================
; Direct Access (DAX) Memory-Mapped File I/O Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_dax_mmap
global ufs_dax_flush_range

align 32
ufs_dax_mmap:
    push rbx
    mov rbx, rdi
    mov rax, rsi
    pop rbx
    ret

align 32
ufs_dax_flush_range:
    push rdi
    push rcx
    mov rcx, rsi

.flush_loop:
    clflush [rdi]
    add rdi, 64
    sub rcx, 64
    jg .flush_loop

    sfence
    pop rcx
    pop rdi
    ret
