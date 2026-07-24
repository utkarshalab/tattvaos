; =============================================================================
; Tattva OS — ufs/vfs/ufs_pseudofs.asm
; =============================================================================
; Synthetic /proc and /sys Pseudo Filesystem Engine for uFS.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_pseudofs_read_proc
global ufs_pseudofs_read_sys

; -----------------------------------------------------------------------------
; ufs_pseudofs_read_proc
; -----------------------------------------------------------------------------
align 32
ufs_pseudofs_read_proc:
    push rbx

    mov rbx, rsi                    ; Destination buffer pointer
    mov byte [rbx], 0               ; Empty synthetic string

    mov rax, 0                      ; Bytes read
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_pseudofs_read_sys
; -----------------------------------------------------------------------------
align 32
ufs_pseudofs_read_sys:
    push rbx

    mov rbx, rsi
    mov byte [rbx], 0

    mov rax, 0
    pop rbx
    ret
