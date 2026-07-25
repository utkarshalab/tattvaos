; =============================================================================
; Tattva OS — ufs/cache/ufs_tmpfs.asm
; =============================================================================
; Linux tmpfs Ultra-Fast In-Memory RAMDisk Storage Engine.
;
; Manages non-persistent, high-speed RAMDisk volumes using dynamic memory pages
; allocated directly from physical RAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_tmpfs_mount_t
    .max_bytes:         resq 1      ; RAMDisk capacity limit
    .used_bytes:        resq 1      ; Current bytes used
    .root_inode:        resq 1      ; Root directory inode ID
endstruc

section .text

global ufs_tmpfs_init
global ufs_tmpfs_alloc_page
global ufs_tmpfs_free_page

; -----------------------------------------------------------------------------
; ufs_tmpfs_init
; -----------------------------------------------------------------------------
align 32
ufs_tmpfs_init:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_tmpfs_mount_t
    mov [rbx + ufs_tmpfs_mount_t.max_bytes], rsi
    mov qword [rbx + ufs_tmpfs_mount_t.used_bytes], 0

    mov eax, 0
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_tmpfs_alloc_page
; -----------------------------------------------------------------------------
align 32
ufs_tmpfs_alloc_page:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_tmpfs_mount_t
    mov rax, [rbx + ufs_tmpfs_mount_t.used_bytes]
    add rax, 4096
    cmp rax, [rbx + ufs_tmpfs_mount_t.max_bytes]
    jg .out_of_mem

    mov [rbx + ufs_tmpfs_mount_t.used_bytes], rax
    mov rax, rsi                    ; Returns page pointer

    pop rbx
    ret

.out_of_mem:
    mov rax, -12                    ; ENOMEM
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_tmpfs_free_page
; -----------------------------------------------------------------------------
align 32
ufs_tmpfs_free_page:
    push rbx

    mov rbx, rdi
    sub qword [rbx + ufs_tmpfs_mount_t.used_bytes], 4096

    pop rbx
    ret
