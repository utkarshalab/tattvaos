; =============================================================================
; Tattva OS — storage/uxfs/btree/rcu.asm
; =============================================================================
; Lock-Free Read-Copy-Update (RCU) Epoch Recycling & Memory Reclaim Engine.
;
; Implements:
;   - Lock-free global epoch generation advancement (`uxfs_rcu_advance_epoch`)
;   - Per-thread RCU reader lock & unlock (`uxfs_rcu_read_lock`, `uxfs_rcu_read_unlock`)
;   - Lock-free ring buffer queue for deferring node deallocation until epoch boundary
;   - Minimum active epoch calculation across 1024 threads before garbage reclaim
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_RCU_MAX_THREADS          1024
%define UXFS_RCU_QUEUE_CAPACITY       4096

struc uxfs_rcu_reclaim_node_t
    .node_ptr:          resq 1      ; Freed memory block pointer
    .epoch_retired:     resq 1      ; Global epoch count when retired
endstruc

section .data
align 64
global uxfs_rcu_global_epoch
uxfs_rcu_global_epoch: dq 1

align 64
uxfs_rcu_thread_epochs: times UXFS_RCU_MAX_THREADS dq 0
uxfs_rcu_reclaim_queue: times UXFS_RCU_QUEUE_CAPACITY * uxfs_rcu_reclaim_node_t_size db 0
uxfs_rcu_head: dq 0
uxfs_rcu_tail: dq 0

section .text

global uxfs_rcu_init
global uxfs_rcu_read_lock
global uxfs_rcu_read_unlock
global uxfs_rcu_advance_epoch
global uxfs_rcu_defer_free
global uxfs_rcu_reclaim_garbage

; extern uxfs_ag_free_block -> defined in storage/uxfs/btree/alloc_groups.asm (single-unit build: no extern needed)

; -----------------------------------------------------------------------------
; uxfs_rcu_init
; -----------------------------------------------------------------------------
align 32
uxfs_rcu_init:
    push rdi
    push rcx
    push rax

    mov qword [uxfs_rcu_global_epoch], 1
    mov qword [uxfs_rcu_head], 0
    mov qword [uxfs_rcu_tail], 0

    lea rdi, [uxfs_rcu_thread_epochs]
    mov rcx, UXFS_RCU_MAX_THREADS
    xor rax, rax
    rep stosq

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; uxfs_rcu_read_lock
; -----------------------------------------------------------------------------
align 32
uxfs_rcu_read_lock:
    push rbx

    mov eax, edi
    and eax, 1023
    mov rbx, [uxfs_rcu_global_epoch]
    mov [uxfs_rcu_thread_epochs + rax * 8], rbx

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_rcu_read_unlock
; -----------------------------------------------------------------------------
align 32
uxfs_rcu_read_unlock:
    mov eax, edi
    and eax, 1023
    mov qword [uxfs_rcu_thread_epochs + rax * 8], 0
    ret

; -----------------------------------------------------------------------------
; uxfs_rcu_advance_epoch
; -----------------------------------------------------------------------------
align 32
uxfs_rcu_advance_epoch:
    lock inc qword [uxfs_rcu_global_epoch]
    mov rax, [uxfs_rcu_global_epoch]
    ret

; -----------------------------------------------------------------------------
; uxfs_rcu_defer_free
; -----------------------------------------------------------------------------
align 32
uxfs_rcu_defer_free:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, [uxfs_rcu_global_epoch]

    mov rax, [uxfs_rcu_head]
    and rax, UXFS_RCU_QUEUE_CAPACITY - 1

    imul rax, rax, uxfs_rcu_reclaim_node_t_size
    lea rax, [uxfs_rcu_reclaim_queue + rax]

    mov [rax + uxfs_rcu_reclaim_node_t.node_ptr], rbx
    mov [rax + uxfs_rcu_reclaim_node_t.epoch_retired], r12

    lock inc qword [uxfs_rcu_head]

    mov eax, 0
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_rcu_reclaim_garbage
;
; Scans active thread epochs to calculate min_epoch before freeing memory!
; -----------------------------------------------------------------------------
align 32
uxfs_rcu_reclaim_garbage:
    push rbx
    push r12
    push r13
    push r14

    mov rax, [uxfs_rcu_tail]
    cmp rax, [uxfs_rcu_head]
    jge .no_garbage

    ; Compute minimum active reader epoch across all threads
    mov r14, [uxfs_rcu_global_epoch]  ; Start with current global epoch
    xor ecx, ecx

.scan_active_threads:
    cmp ecx, UXFS_RCU_MAX_THREADS
    jge .min_epoch_found

    mov r8, [uxfs_rcu_thread_epochs + rcx * 8]
    test r8, r8
    jz .next_thread

    cmp r8, r14
    cmovl r14, r8                   ; R14 = min(active reader epochs)

.next_thread:
    inc ecx
    jmp .scan_active_threads

.min_epoch_found:
    mov rax, [uxfs_rcu_tail]
    and rax, UXFS_RCU_QUEUE_CAPACITY - 1
    imul rbx, rax, uxfs_rcu_reclaim_node_t_size
    lea rbx, [uxfs_rcu_reclaim_queue + rbx]

    ; Only free if epoch_retired < min_epoch across active threads!
    mov r12, [rbx + uxfs_rcu_reclaim_node_t.epoch_retired]
    cmp r12, r14
    jge .no_garbage                 ; Node still in-use by an active reader thread!

    mov rdi, [rbx + uxfs_rcu_reclaim_node_t.node_ptr]
    call uxfs_ag_free_block

    lock inc qword [uxfs_rcu_tail]
    mov eax, 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.no_garbage:
    mov eax, 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
