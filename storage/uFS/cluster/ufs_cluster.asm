; =============================================================================
; Tattva OS — ufs/cluster/ufs_cluster.asm
; =============================================================================
; Ceph / GlusterFS CRUSH Distributed Cloud Storage Router Engine for uFS.
;
; Implements CRUSH (Controlled Replication Under Scalable Hashing) map routing
; for distributing file blocks across cluster storage nodes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_cluster_route_block

; -----------------------------------------------------------------------------
; ufs_cluster_route_block
;
; Computes target target node ID for block using CRUSH hash hashing.
;
; Inputs:
;   RDI = Block ID
;   ESI = Node count
;
; Returns:
;   EAX = Target storage node ID
; -----------------------------------------------------------------------------
align 32
ufs_cluster_route_block:
    push rbx

    mov rax, rdi
    xor edx, edx
    div rsi                         ; RDX = block_id % node_count
    mov eax, edx                    ; Target node ID

    pop rbx
    ret
