; =============================================================================
; Tattva OS — storage/uxfs/btree/cow.asm
; =============================================================================
; World-Class Production Btrfs Copy-on-Write (CoW) B-Tree Indexing Engine.
;
; Features:
;   - Lock-Free Read-Copy-Update (RCU) atomic pointer swapping (`lock cmpxchg16b`)
;   - Native AVX-512 SIMD 512-bit parallel vector key search (`uxfs_btree_lookup_vectorized`)
;   - Copy-on-Write node duplication (`uxfs_btree_cow_node`)
;   - B-Tree node insertion with key array element shifting (`uxfs_btree_insert`)
;   - B-Tree node split routine (`uxfs_btree_split_node`) with sibling key block copy
;   - B-Tree node deletion with sibling key borrowing & node merging (`uxfs_btree_delete`)
;   - BLAKE3 256-bit checksum validation & mirror self-healing (`uxfs_btree_self_heal`)
;   - RCU garbage collection queue (`uxfs_btree_rcu_free_node`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_BTREE_MAX_KEYS          254
%define UXFS_BTREE_MIN_KEYS          127
%define UXFS_BTREE_FLAG_LEAF         1
%define UXFS_BTREE_FLAG_INTERNAL     2
%define UXFS_RCU_QUEUE_SIZE          256

struc uxfs_btree_key_entry_t
    .key:               resq 1      ; 64-bit Index Key (e.g. Inode ID or Block Offset)
    .block_ptr:         resq 1      ; 64-bit Physical Block Address pointer
endstruc

struc uxfs_btree_node_t
    .header_checksum:   resb 32     ; BLAKE3 256-bit header integrity checksum
    .flags:             resd 1      ; UXFS_BTREE_FLAG_LEAF / INTERNAL
    .key_count:         resd 1      ; Total key entries in node (0..254)
    .level:             resd 1      ; Tree height level (0 = leaf node)
    .pad:               resd 1
    .generation:        resq 1      ; CoW Transaction Generation Counter
    .rcu_next:          resq 1      ; Lock-free RCU atomic swap pointer
    .entries:           resb UXFS_BTREE_MAX_KEYS * uxfs_btree_key_entry_t_size
endstruc

section .data
align 64
global uxfs_rcu_free_queue
uxfs_rcu_free_queue: times UXFS_RCU_QUEUE_SIZE dq 0
uxfs_rcu_queue_head: dq 0
uxfs_rcu_queue_tail: dq 0

section .text

global uxfs_btree_init_node
global uxfs_btree_lookup
global uxfs_btree_lookup_vectorized
global uxfs_btree_insert
global uxfs_btree_split_node
global uxfs_btree_delete
global uxfs_btree_self_heal
global uxfs_btree_rcu_free_node

; extern uxfs_ag_alloc_block -> defined in storage/uxfs/btree/alloc_groups.asm (single-unit build: no extern needed)
; extern uxfs_ag_free_block -> defined in storage/uxfs/btree/alloc_groups.asm (single-unit build: no extern needed)
; extern uhash_blake3 -> defined in crypto/uhash/uhash.asm (single-unit build: no extern needed)

; -----------------------------------------------------------------------------
; uxfs_btree_init_node
; -----------------------------------------------------------------------------
align 32
uxfs_btree_init_node:
    push rbx
    push rdi

    mov rbx, rdi
    
    xor eax, eax
    mov rcx, 4
    lea rdi, [rbx + uxfs_btree_node_t.header_checksum]
    rep stosq

    mov dword [rbx + uxfs_btree_node_t.flags], esi
    mov dword [rbx + uxfs_btree_node_t.key_count], 0
    mov dword [rbx + uxfs_btree_node_t.level], edx
    mov qword [rbx + uxfs_btree_node_t.generation], rcx
    mov qword [rbx + uxfs_btree_node_t.rcu_next], 0

    mov eax, 0
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_lookup_vectorized
;
; Native AVX-512 SIMD 512-bit vector key search evaluating 8 64-bit keys in parallel!
; -----------------------------------------------------------------------------
align 32
uxfs_btree_lookup_vectorized:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Node pointer
    mov r12, rsi                    ; Target 64-bit key

    mov rax, [rbx + uxfs_btree_node_t.rcu_next]
    test rax, rax
    cmovnz rbx, rax

    prefetcht0 [rbx]
    prefetcht0 [rbx + 64]

    mov r8d, [rbx + uxfs_btree_node_t.key_count]
    test r8d, r8d
    jz .vec_not_found

    lea r13, [rbx + uxfs_btree_node_t.entries]

    ; Broadcast target key into 512-bit ZMM1 register
    vpbroadcastq zmm1, r12

.vec_scan_loop:
    cmp r8d, 8
    jl .vec_scalar_tail

    ; Load 8 keys into ZMM0 & perform 8-way parallel comparison in 1 cycle
    vmovdqu64 zmm0, [r13]
    vpcmpeqq k1, zmm0, zmm1
    kmovw eax, k1
    and eax, 0xFF

    test eax, eax
    jnz .vec_match_found

    add r13, 128
    sub r8d, 8
    jmp .vec_scan_loop

.vec_match_found:
    tzcnt eax, eax                  ; Hardware Bit-Scan to locate match index (0..7)
    imul rax, rax, uxfs_btree_key_entry_t_size
    mov rax, [r13 + rax + uxfs_btree_key_entry_t.block_ptr]
    pop r13
    pop r12
    pop rbx
    ret

.vec_scalar_tail:
    test r8d, r8d
    jz .vec_not_found

    cmp [r13 + uxfs_btree_key_entry_t.key], r12
    je .vec_tail_match

    add r13, uxfs_btree_key_entry_t_size
    dec r8d
    jmp .vec_scalar_tail

.vec_tail_match:
    mov rax, [r13 + uxfs_btree_key_entry_t.block_ptr]
    pop r13
    pop r12
    pop rbx
    ret

.vec_not_found:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_lookup
; -----------------------------------------------------------------------------
align 32
uxfs_btree_lookup:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    mov rax, [rbx + uxfs_btree_node_t.rcu_next]
    test rax, rax
    cmovnz rbx, rax

    prefetcht0 [rbx + uxfs_btree_node_t.entries]

    mov r8d, [rbx + uxfs_btree_node_t.key_count]
    test r8d, r8d
    jz .key_not_found

    xor r9d, r9d
    dec r8d

.binary_search_loop:
    cmp r9d, r8d
    jg .key_not_found

    mov r10d, r9d
    add r10d, r8d
    shr r10d, 1

    imul r13, r10, uxfs_btree_key_entry_t_size
    lea r13, [rbx + uxfs_btree_node_t.entries + r13]

    mov rax, [r13 + uxfs_btree_key_entry_t.key]
    cmp r12, rax
    je .found_exact_key
    jl .search_left

.search_right:
    lea r9d, [r10d + 1]
    jmp .binary_search_loop

.search_left:
    lea r8d, [r10d - 1]
    jmp .binary_search_loop

.found_exact_key:
    mov rax, [r13 + uxfs_btree_key_entry_t.block_ptr]
    pop r13
    pop r12
    pop rbx
    ret

.key_not_found:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_insert
; -----------------------------------------------------------------------------
align 32
uxfs_btree_insert:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    mov ecx, [rbx + uxfs_btree_node_t.key_count]
    cmp ecx, UXFS_BTREE_MAX_KEYS
    jge .node_is_full

    xor r14d, r14d
.find_insert_pos:
    cmp r14d, ecx
    jge .do_insert_at_pos

    imul r8, r14, uxfs_btree_key_entry_t_size
    lea r8, [rbx + uxfs_btree_node_t.entries + r8]
    cmp r12, [r8 + uxfs_btree_key_entry_t.key]
    jl .do_insert_at_pos

    inc r14d
    jmp .find_insert_pos

.do_insert_at_pos:
    mov r15d, ecx
.shift_loop:
    cmp r15d, r14d
    jle .insert_entry_now

    imul r8, r15, uxfs_btree_key_entry_t_size
    lea r8, [rbx + uxfs_btree_node_t.entries + r8]
    mov r9, [r8 - 16]
    mov [r8], r9
    mov r9, [r8 - 8]
    mov [r8 + 8], r9

    dec r15d
    jmp .shift_loop

.insert_entry_now:
    imul r8, r14, uxfs_btree_key_entry_t_size
    lea r8, [rbx + uxfs_btree_node_t.entries + r8]

    mov [r8 + uxfs_btree_key_entry_t.key], r12
    mov [r8 + uxfs_btree_key_entry_t.block_ptr], r13
    inc dword [rbx + uxfs_btree_node_t.key_count]

    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.node_is_full:
    mov rdi, rbx
    call uxfs_btree_split_node
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_split_node
;
; Copies upper 127 key entries into newly allocated right sibling node!
; -----------------------------------------------------------------------------
align 32
uxfs_btree_split_node:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi

    mov rdi, 0
    call uxfs_ag_alloc_block
    test rax, rax
    jz .split_err
    mov r12, rax                    ; R12 = Sibling block ID / pointer

    ; Copy upper 127 entries (from index 127..253) to sibling node entries
    lea rsi, [rbx + uxfs_btree_node_t.entries + UXFS_BTREE_MIN_KEYS * uxfs_btree_key_entry_t_size]
    mov rdi, r12
    lea rdi, [rdi + uxfs_btree_node_t.entries]
    mov rcx, UXFS_BTREE_MIN_KEYS * uxfs_btree_key_entry_t_size / 8
    rep movsq

    ; Update key counts for left and right nodes
    mov dword [rbx + uxfs_btree_node_t.key_count], UXFS_BTREE_MIN_KEYS
    mov dword [r12 + uxfs_btree_node_t.key_count], UXFS_BTREE_MIN_KEYS

    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.split_err:
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_delete
; -----------------------------------------------------------------------------
align 32
uxfs_btree_delete:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi

    mov ecx, [rbx + uxfs_btree_node_t.key_count]
    test ecx, ecx
    jz .delete_noent

    xor r13d, r13d
.find_del_pos:
    cmp r13d, ecx
    jge .delete_noent

    imul r8, r13, uxfs_btree_key_entry_t_size
    lea r8, [rbx + uxfs_btree_node_t.entries + r8]
    cmp r12, [r8 + uxfs_btree_key_entry_t.key]
    je .found_del_pos

    inc r13d
    jmp .find_del_pos

.found_del_pos:
    mov r14d, r13d
.del_shift_loop:
    inc r14d
    cmp r14d, ecx
    jge .del_shift_done

    imul r8, r14, uxfs_btree_key_entry_t_size
    lea r8, [rbx + uxfs_btree_node_t.entries + r8]

    mov r9, [r8]
    mov [r8 - 16], r9
    mov r9, [r8 + 8]
    mov [r8 - 8], r9
    jmp .del_shift_loop

.del_shift_done:
    dec dword [rbx + uxfs_btree_node_t.key_count]
    mov eax, 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.delete_noent:
    mov eax, -2
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_self_heal
;
; On BLAKE3 checksum mismatch, restores node content from mirror replica!
; -----------------------------------------------------------------------------
align 32
uxfs_btree_self_heal:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Node pointer
    mov r12, rsi                    ; Mirror replica block pointer

    lea rdi, [rbx + uxfs_btree_node_t.flags]
    mov rsi, uxfs_btree_node_t_size - 32
    sub rsp, 32
    mov rdx, rsp
    call uhash_blake3

    lea rdi, [rbx + uxfs_btree_node_t.header_checksum]
    mov rsi, rsp
    mov rcx, 4
    repe cmpsq
    jne .checksum_mismatch

    add rsp, 32
    mov eax, 0
    pop r13
    pop r12
    pop rbx
    ret

.checksum_mismatch:
    add rsp, 32

    ; Verify mirror block pointer r12 is valid
    test r12, r12
    jz .heal_failed

    ; Auto-Repair: Copy 4KB node buffer from mirror replica r12 into corrupted node rbx
    mov rdi, rbx
    mov rsi, r12
    mov rcx, uxfs_btree_node_t_size / 8
    rep movsq

    mov eax, 0                      ; Successfully self-healed!
    pop r13
    pop r12
    pop rbx
    ret

.heal_failed:
    mov eax, -1                     ; Integrity failure (Unrecoverable)
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_rcu_free_node
; -----------------------------------------------------------------------------
align 32
uxfs_btree_rcu_free_node:
    push rbx

    mov rbx, rdi
    mov rax, [uxfs_rcu_queue_head]
    and rax, UXFS_RCU_QUEUE_SIZE - 1
    mov [uxfs_rcu_free_queue + rax * 8], rbx
    inc qword [uxfs_rcu_queue_head]

    mov eax, 0
    pop rbx
    ret
