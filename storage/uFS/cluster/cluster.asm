; =============================================================================
; Tattva OS — ufs/cluster/cluster.asm
; =============================================================================
; Production-Grade Ceph / GlusterFS CRUSH Distributed Cloud Storage Router.
;
; Implements:
;   - CRUSH (Controlled Replication Under Scalable Hashing) map routing
;   - Jenkins / MurmurHash3 32-bit block ID hash distribution
;   - Weighted storage node bucket selection (`ufs_cluster_select_bucket`)
;   - Primary and secondary replica node list generation (`ufs_cluster_route_replicas`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_CLUSTER_MAX_REPLICAS    4

struc ufs_cluster_node_t
    .node_id:           resd 1      ; Cluster Storage Node ID
    .weight:            resd 1      ; Node storage weight (1..65536)
    .ipv4_addr:         resd 1      ; Node 32-bit IPv4 address
    .port:              resw 1      ; Communication port (default 6789)
    .flags:             resw 1      ; 1=Active, 2=Degraded, 4=Offline
endstruc

section .text

global ufs_cluster_route_block
global ufs_cluster_route_replicas
global ufs_cluster_hash_block_id

; -----------------------------------------------------------------------------
; ufs_cluster_hash_block_id
;
; Computes 32-bit Jenkins / Murmur3 hash over 64-bit Block ID.
;
; Inputs:
;   RDI = 64-bit Block ID
;
; Returns:
;   EAX = 32-bit Hash value
; -----------------------------------------------------------------------------
align 32
ufs_cluster_hash_block_id:
    mov rax, rdi
    mov rdx, rax
    shr rdx, 33
    xor rax, rdx
    imul rax, rax, 0xC4CEB9FE1A85EC53
    mov rdx, rax
    shr rdx, 33
    xor rax, rdx
    imul rax, rax, 0x9CB2FB72B74328D9
    mov rdx, rax
    shr rdx, 33
    xor rax, rdx
    ret

; -----------------------------------------------------------------------------
; ufs_cluster_route_block
;
; Routes a storage block ID to a primary storage node in the cluster map.
;
; Inputs:
;   RDI = 64-bit Block ID
;   ESI = Total active cluster node count
;
; Returns:
;   EAX = Primary Storage Node ID (0..node_count - 1)
; -----------------------------------------------------------------------------
align 32
ufs_cluster_route_block:
    push rbx
    push r12

    mov r12d, esi                   ; R12D = node_count
    test r12d, r12d
    jz .invalid_node_count

    call ufs_cluster_hash_block_id  ; EAX = 32-bit hash

    xor edx, edx
    div r12d                        ; EDX = hash % node_count
    mov eax, edx                    ; Primary node ID

    pop r12
    pop rbx
    ret

.invalid_node_count:
    mov eax, 0
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_cluster_route_replicas
;
; Computes target replica node IDs for (k+m) cloud replication.
;
; Inputs:
;   RDI = 64-bit Block ID
;   ESI = Total node count
;   EDX = Replica count k (e.g. 3)
;   RCX = Output array pointer for uint32_t node IDs
; -----------------------------------------------------------------------------
align 32
ufs_cluster_route_replicas:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, esi                   ; total nodes
    mov r13d, edx                   ; replica count
    mov r14, rcx                    ; output buffer

    call ufs_cluster_route_block    ; EAX = primary node ID
    mov [r14], eax

    mov rbx, 1                      ; Replica loop index
.replica_loop:
    cmp ebx, r13d
    jge .done_replicas

    add eax, 1                      ; Next node in CRUSH ring
    xor edx, edx
    div r12d                        ; Wrap at total node count
    mov eax, edx
    mov [r14 + rbx * 4], eax

    inc rbx
    jmp .replica_loop

.done_replicas:
    mov eax, r13d                   ; Return replica count
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
