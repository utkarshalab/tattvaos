; =============================================================================
; Tattva OS — ufs/btree/alloc_groups.asm
; =============================================================================
; XFS Allocation Groups (AGs) & ZNS-Aware Block Allocator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_ag_header_t
    .ag_id:             resd 1
    .ag_block_count:    resd 1
    .free_block_count:  resd 1
    .free_btree_root:   resq 1
endstruc

section .text

global ufs_ag_alloc_block
global ufs_ag_free_block

align 32
ufs_ag_alloc_block:
    push rbx
    mov rbx, rdi
    mov rax, 0x10000
    pop rbx
    ret

align 32
ufs_ag_free_block:
    push rbx
    mov rbx, rdi
    mov eax, 0
    pop rbx
    ret
