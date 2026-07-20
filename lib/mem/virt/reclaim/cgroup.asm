; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/cgroup.asm
; =============================================================================
; Hierarchical Memory Cgroups (v2 Control Topology) (Feature 15).
; Enforces memory limits hierarchically across cgroups, executing cgroup-specific
; reclaim and OOM termination if thresholds are breached.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_CGROUP_ASM
%define LIB_MEM_VIRT_RECLAIM_CGROUP_ASM

[BITS 64]

; Thread Structure Definition (from sched_affinity.asm)
struc thread_t
    .thread_id          resq 1      ; Unique thread ID
    .cpu_affinity_mask  resq 1      ; Bitmask of allowed CPUs
    .preferred_node     resd 1      ; Target NUMA node ID
    .current_cpu        resd 1      ; Current execution CPU ID
    .flags              resq 1      ; Thread flags (bit 0 = Active, bit 1 = Stalled)
    .tsx_active         resq 1      
    .tsx_xbegin_rip     resq 1      
    .tsx_fallback_rip   resq 1      
    .tsx_retries        resq 1      
    .mem_usage          resq 1      ; Memory usage (pages)
    .time_alive         resq 1      
    .priority_weight    resq 1      
    .oom_notifier       resq 1      
    .cgroup_ptr         resq 1      ; Pointer to thread's memory cgroup
endstruc

; mem_cgroup structure layout (v2 Hierarchical Control Topology)
struc mem_cgroup
    .max_limit      resq 1          ; Max budget limit in bytes
    .high_limit     resq 1          ; High/throttle threshold limit in bytes
    .usage_bytes    resq 1          ; Current charged usage in bytes
    .parent         resq 1          ; Parent cgroup pointer (NULL if root)
endstruc

section .text



; -----------------------------------------------------------------------------
; mem_cgroup_charge — charges allocation size hierarchically up the control tree
; Input:
;   RDI = mem_cgroup_ptr
;   RSI = allocation_size (in bytes)
; Output:
;   RAX = 1 on success, 0 on charge failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global mem_cgroup_charge
mem_cgroup_charge:
    push rbx
    push rbp
    push r12
    push r13

    mov r12, rdi                    ; R12 = current mem_cgroup
    mov r13, rsi                    ; R13 = allocation_size

.charge_loop:
    test r12, r12
    jz .success                     ; Successfully charged to root

    mov rax, [r12 + mem_cgroup.usage_bytes]
    add rax, r13
    cmp rax, [r12 + mem_cgroup.max_limit]
    ja .limit_exceeded

    ; Atomically update usage bytes of current cgroup node
.retry_add:
    mov rdx, [r12 + mem_cgroup.usage_bytes]
    mov r8, rdx
    add r8, r13
    mov rax, rdx
    lock cmpxchg [r12 + mem_cgroup.usage_bytes], r8
    jnz .retry_add

    ; Move to parent cgroup node
    mov r12, [r12 + mem_cgroup.parent]
    jmp .charge_loop

.success:
    mov rax, 1                      ; Successful charge
    jmp .exit

.limit_exceeded:
    ; Try cgroup-specific memory reclaim first
    mov rdi, r12                    ; RDI = current cgroup
    mov rsi, r13                    ; RSI = size
    call mem_cgroup_reclaim         ; RAX = 1 on reclaim success
    test rax, rax
    jnz .charge_loop                ; Retry charging loop if reclaim freed enough

    ; Reclaim failed! Invoke cgroup OOM killer to terminate heaviest task in path
    mov rdi, r12                    ; RDI = current cgroup
    call mem_cgroup_oom_kill
    
    xor rax, rax                    ; Return charge failure

.exit:
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; mem_cgroup_reclaim — attempts to reclaim pages specifically from a cgroup path
; Input:
;   RDI = cgroup_ptr
;   RSI = allocation_size (in bytes)
; Output:
;   RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
global mem_cgroup_reclaim
mem_cgroup_reclaim:
    push rbx
    push rsi
    push rdi

    mov rbx, rdi                    ; RBX = cgroup
    mov r8, rsi                     ; R8 = allocation_size

    ; Read current usage
    mov rax, [rbx + mem_cgroup.usage_bytes]
    test rax, rax
    jz .fail

    ; Simulate page cache/VMA reclaim by subtracting allocation_size from usage_bytes
    cmp rax, r8
    jbe .clear_usage

    sub rax, r8
    mov [rbx + mem_cgroup.usage_bytes], rax
    mov rax, 1                      ; Reclaim succeeded
    jmp .done

.clear_usage:
    mov qword [rbx + mem_cgroup.usage_bytes], 0
    mov rax, 1

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

.fail:
    xor rax, rax
    jmp .done

; -----------------------------------------------------------------------------
; mem_cgroup_oom_kill — kills the heaviest task inside a cgroup path
; Input:
;   RDI = cgroup_ptr
;   Output:
;   RAX = 1 if thread terminated, 0 if no candidate found
; -----------------------------------------------------------------------------
global mem_cgroup_oom_kill
mem_cgroup_oom_kill:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = target cgroup pointer
    mov r13, [thread_count]
    test r13, r13
    jz .no_candidate

    xor r14, r14                    ; R14 = heaviest memory usage (pages)
    xor r15, r15                    ; R15 = pointer to heaviest thread_t (victim)
    xor rbx, rbx                    ; loop index = 0

.find_loop:
    cmp rbx, r13
    jae .kill_victim

    mov rax, rbx
    imul rax, thread_t_size
    lea rbp, [thread_table + rax]   ; RBP = current thread pointer

    ; Check if active
    mov rax, [rbp + thread_t.flags]
    test rax, 1
    jz .next_thread

    ; Check if thread belongs to target cgroup
    cmp [rbp + thread_t.cgroup_ptr], r12
    jne .next_thread

    ; Check if its memory usage is the heaviest
    mov rax, [rbp + thread_t.mem_usage]
    cmp rax, r14
    jbe .next_thread

    mov r14, rax                    ; Update heaviest size
    mov r15, rbp                    ; Update heaviest thread pointer

.next_thread:
    inc rbx
    jmp .find_loop

.kill_victim:
    test r15, r15
    jz .no_candidate

    ; Terminate the victim thread (clear bit 0 of flags)
    and qword [r15 + thread_t.flags], ~1
    mov rax, 1                      ; Victim successfully killed
    jmp .exit

.no_candidate:
    xor rax, rax                    ; No candidate found to kill

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_RECLAIM_CGROUP_ASM
