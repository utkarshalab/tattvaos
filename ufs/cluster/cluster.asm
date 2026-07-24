; =============================================================================
; Tattva OS — ufs/cluster/cluster.asm
; =============================================================================
; Ceph / GlusterFS CRUSH Distributed Cloud Storage Router Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_cluster_route_block

align 32
ufs_cluster_route_block:
    push rbx
    mov rax, rdi
    xor edx, edx
    div rsi
    mov eax, edx
    pop rbx
    ret
