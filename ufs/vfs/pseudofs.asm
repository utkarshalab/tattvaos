; =============================================================================
; Tattva OS — ufs/vfs/pseudofs.asm
; =============================================================================
; Synthetic /proc and /sys Pseudo Filesystem Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_pseudofs_read_proc
global ufs_pseudofs_read_sys

align 32
ufs_pseudofs_read_proc:
    push rbx
    mov rbx, rsi
    mov byte [rbx], 0
    mov rax, 0
    pop rbx
    ret

align 32
ufs_pseudofs_read_sys:
    push rbx
    mov rbx, rsi
    mov byte [rbx], 0
    mov rax, 0
    pop rbx
    ret
