; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/process_madvise.asm
; =============================================================================
; Remote Process Advice & Reclamation (Feature 11).
; Allows administrative tasks to reclaim memory from target tasks.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_PROCESS_MADVISE_ASM
%define LIB_MEM_VIRT_RECLAIM_PROCESS_MADVISE_ASM

[BITS 64]

; Thread Structure Definition (Must align with sched_affinity.asm)
struc thread_t
    .thread_id          resq 1      ; Unique thread ID (PID)
    .cpu_affinity_mask  resq 1      ; Bitmask of allowed CPUs
    .preferred_node     resd 1      ; Target NUMA node ID
    .current_cpu        resd 1      ; Current execution CPU ID
    .flags              resq 1      ; Thread flags (bit 0 = Active, bit 1 = Stalled, bit 2 = Lock)
    .tsx_active         resq 1      
    .tsx_xbegin_rip     resq 1      
    .tsx_fallback_rip   resq 1      
    .tsx_retries        resq 1      
    .mem_usage          resq 1      
    .time_alive         resq 1      
    .priority_weight    resq 1      
    .oom_notifier       resq 1      
    .cgroup_ptr         resq 1      
endstruc

section .text

extern sched_get_current_thread
extern thread_count
extern thread_table
extern virt_walk_table
extern swap_alloc_slot
extern swap_write_page
extern swap_free_slot
extern phys_free_page

; -----------------------------------------------------------------------------
; sys_process_madvise — advises and reclaims memory of a remote target process
; Input:
;   RDI = target_pid
;   RSI = target_vaddr
;   RDX = size
;   RCX = advice_flag (e.g. MADV_RECLAIM = 18)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global sys_process_madvise
sys_process_madvise:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Save input registers
    mov r12, rdi                    ; R12 = target_pid
    mov r13, rsi                    ; R13 = target_vaddr
    mov r14, rdx                    ; R14 = size
    mov r15, rcx                    ; R15 = advice_flag

    ; 1. Check capability of the caller thread
    call sched_get_current_thread   ; RAX = current thread pointer
    test rax, rax
    jz .fail
    
    mov r8, [rax + thread_t.flags]
    test r8, (1 << 12)              ; CAP_SYS_RECLAIM = bit 12
    jz .fail

    ; 2. Validate advice flag (MADV_RECLAIM = 18)
    cmp r15, 18
    jne .fail

    ; 3. Search target process in thread_table
    mov r9, [thread_count]
    test r9, r9
    jz .fail

    xor r8, r8                      ; R8 = thread index i = 0
.search_loop:
    cmp r8, r9
    jae .fail                       ; Target PID not found

    mov rax, r8
    imul rax, thread_t_size
    lea rbx, [thread_table + rax]   ; RBX = candidate thread pointer

    ; Check if active (bit 0 of flags)
    mov r10, [rbx + thread_t.flags]
    test r10, 1
    jz .next_thread

    ; Compare PID
    cmp [rbx + thread_t.thread_id], r12
    je .found_target

.next_thread:
    inc r8
    jmp .search_loop

.found_target:
    ; RBX = target thread_t pointer
    ; 4. Acquire spinlock on the target process structure (bit 2 of flags)
.lock_spin:
    lock bts qword [rbx + thread_t.flags], 2
    jc .lock_pause
    jmp .lock_acquired

.lock_pause:
    pause
    test qword [rbx + thread_t.flags], (1 << 2)
    jnz .lock_pause
    jmp .lock_spin

.lock_acquired:
    ; 5. Loop through page tables in range [target_vaddr, target_vaddr + size)
    mov r12, r13                    ; R12 = current virtual address (aligned down)
    and r12, -4096

    mov r13, r14                    ; R13 = end virtual address (exclusive)
    add r13, 4095
    and r13, -4096
    add r13, r12                    ; R13 = end_vaddr

.reclaim_loop:
    cmp r12, r13
    jae .unlock_and_success

    ; Walk page table to find leaf PTE
    mov rdi, r12
    xor rsi, rsi                    ; CR3 = 0 (use active CR3)
    call virt_walk_table            ; RAX = PTE pointer
    test rax, rax
    jz .skip_page

    mov r15, rax                    ; R15 = PTE pointer
    mov rdx, [r15]
    test rdx, 0x01                  ; Present?
    jz .skip_page
    test rdx, 0x80                  ; Huge page?
    jnz .skip_page                  ; Skip huge pages for standard 4KB reclamation

    ; Extract physical base address (mask off flags)
    mov rbp, rdx
    and rbp, 0xFFFFFFFFFFFFF000     ; RBP = physical frame address

    ; Allocate a slot on the swap device
    call swap_alloc_slot            ; RAX = slot index (or -1)
    cmp rax, -1
    je .skip_page                   ; Swap device full, skip this page
    mov r10, rax                    ; R10 = swap slot index

    ; Write page data to swap device
    mov rdi, rbp                    ; source physical address
    mov rsi, r10                    ; swap slot index
    push r10
    call swap_write_page            ; RAX = status (1 = success)
    pop r10
    test rax, rax
    jz .free_slot_and_skip          ; Write failed, free slot and skip

    ; Update PTE: clear Present (bit 0 = 0), set Swap (bit 10 = 1), store swap slot index in bits 12-51
    mov rdx, r10
    shl rdx, 12
    or rdx, 0x400                   ; Set PAGE_SWAPPED (bit 10)
    lock xchg [r15], rdx            ; Update PTE atomically

    ; Invalidate TLB for the target virtual address
    invlpg [r12]

    ; Free the original physical page frame
    mov rdi, rbp
    call phys_free_page
    jmp .skip_page

.free_slot_and_skip:
    mov rdi, r10
    call swap_free_slot

.skip_page:
    add r12, 4096                   ; Next page
    jmp .reclaim_loop

.unlock_and_success:
    ; Release spinlock on target structure (clear bit 2 of flags)
    lock btr qword [rbx + thread_t.flags], 2
    mov rax, 1                      ; Return success
    jmp .exit

.fail:
    xor rax, rax                    ; Return failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_RECLAIM_PROCESS_MADVISE_ASM
