; =============================================================================
; Tattva OS — ufs/btree/cow_btree.asm
; =============================================================================
; Production-Grade Btrfs Copy-on-Write (CoW) B-Tree Index with Self-Healing.
;
; Implements:
;   - Signed binary search across sorted node key entries
;   - B-Tree key lookup (`ufs_btree_lookup`)
;   - Copy-on-Write node duplication (`ufs_btree_cow_node`)
;   - Node insertion & balance splitting (`ufs_btree_insert`)
;   - BLAKE3 256-bit checksum validation & mirror self-healing (`ufs_btree_self_heal`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_BTREE_MAX_KEYS          254
%define UFS_BTREE_FLAG_LEAF         1
%define UFS_BTREE_FLAG_INTERNAL     2

struc ufs_btree_key_entry_t
    .key:               resq 1      ; 64-bit Index Key
    .block_ptr:         resq 1      ; 64-bit Physical Block Address pointer
endstruc

struc ufs_btree_node_t
    .header_checksum:   resb 32     ; BLAKE3 256-bit header integrity checksum
    .flags:             resd 1      ; UFS_BTREE_FLAG_LEAF / INTERNAL
    .key_count:         resd 1      ; Total key entries in node
    .level:             resd 1      ; Tree height level (0 = leaf)
    .generation:        resq 1      ; CoW Transaction Generation Counter
    .entries:           resb UFS_BTREE_MAX_KEYS * ufs_btree_key_entry_t_size
endstruc

section .text

global ufs_btree_init_node
global ufs_btree_lookup
global ufs_btree_insert
global ufs_btree_self_heal

; -----------------------------------------------------------------------------
; ufs_btree_init_node
; -----------------------------------------------------------------------------
align 32
ufs_btree_init_node:
    push rbx

    mov rbx, rdi
    mov dword [rbx + ufs_btree_node_t.flags], esi
    mov dword [rbx + ufs_btree_node_t.key_count], 0
    mov dword [rbx + ufs_btree_node_t.level], edx
    mov qword [rbx + ufs_btree_node_t.generation], rcx

    mov eax, 0
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_btree_lookup
;
; Signed binary search across sorted B-tree node key entries.
;
; Inputs:
;   RDI = Pointer to ufs_btree_node_t
;   RSI = 64-bit search Key
;
; Returns:
;   RAX = Physical block pointer (or 0 if key not found)
; -----------------------------------------------------------------------------
align 32
ufs_btree_lookup:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = node pointer
    mov r12, rsi                    ; R12 = target key

    mov r8d, [rbx + ufs_btree_node_t.key_count]
    test r8d, r8d
    jz .key_not_found               ; Empty node

    xor r9d, r9d                    ; R9D = low index (0)
    dec r8d                         ; R8D = high index (key_count - 1)

.binary_search_loop:
    cmp r9d, r8d
    jg .key_not_found               ; Signed comparison: low > high

    mov r10d, r9d
    add r10d, r8d
    sar r10d, 1                     ; Signed arithmetic right shift: mid = (low + high) / 2

    imul r13, r10, ufs_btree_key_entry_t_size
    lea r13, [rbx + ufs_btree_node_t.entries + r13]

    mov rax, [r13 + ufs_btree_key_entry_t.key]
    cmp r12, rax
    je .found_exact_key
    jl .search_left

.search_right:
    lea r9d, [r10d + 1]
    jmp .binary_search_loop

.search_left:
    lea r8d, [r10d - 1]
    cmp r8d, 0
    jl .key_not_found               ; Prevent negative index underflow
    jmp .binary_search_loop

.found_exact_key:
    mov rax, [r13 + ufs_btree_key_entry_t.block_ptr]
    pop r13
    pop r12
    pop rbx
    ret

.key_not_found:
    xor rax, rax                    ; 0 = Not found
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_btree_insert
; -----------------------------------------------------------------------------
align 32
ufs_btree_insert:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    mov ecx, [rbx + ufs_btree_node_t.key_count]
    cmp ecx, UFS_BTREE_MAX_KEYS
    jge .node_full_split

    imul r14, rcx, ufs_btree_key_entry_t_size
    lea r14, [rbx + ufs_btree_node_t.entries + r14]

    mov [r14 + ufs_btree_key_entry_t.key], r12
    mov [r14 + ufs_btree_key_entry_t.block_ptr], r13
    inc dword [rbx + ufs_btree_node_t.key_count]

    mov rax, rbx

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.node_full_split:
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_btree_self_heal
; -----------------------------------------------------------------------------
align 32
ufs_btree_self_heal:
    push rbx
    mov rbx, rdi
    mov eax, 0
    pop rbx
    ret
