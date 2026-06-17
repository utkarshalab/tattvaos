; =============================================================================
; Tattva OS — lib/mem/virt/virt.asm
; =============================================================================
; Virtual memory manager entry. Handles Virtual Memory Areas (VMAs).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_VIRT_ASM
%define LIB_MEM_VIRT_VIRT_ASM

[BITS 64]

struc vma_t
    .start      resq 1          ; Start virtual address (page-aligned)
    .end        resq 1          ; End virtual address (page-aligned, exclusive)
    .flags      resq 1          ; VMA flags
    .next       resq 1          ; Pointer to next VMA in the list
    .file_ptr   resq 1          ; Pointer to mapped file structure
    .file_off   resq 1          ; Offset inside the file
    .file_size  resq 1          ; Original mapped size of the file
endstruc

struc mem_cgroup_t
    .id             resq 1      ; Unique cgroup ID
    .hard_limit     resq 1      ; Hard limit (in pages)
    .soft_limit     resq 1      ; Soft limit (in pages)
    .usage          resq 1      ; Current usage (in pages)
endstruc

VMA_FILE        equ (1 << 8)    ; Bind storage file directly to VMA
VMA_HMM         equ (1 << 9)    ; VMA flag for HMM Unified Memory
VMA_DAX         equ (1 << 10)   ; DAX Zero-Cache mapping flag
VMA_PMEM        equ (1 << 11)   ; PMEM Byte-Addressability mapping flag
VMA_PMEM_WINDOW equ (1 << 12)   ; PMEM static hardware window mapping flag


section .text

; -----------------------------------------------------------------------------
; vma_init — initializes the VMA allocator
; Input: none
; Output: none
; -----------------------------------------------------------------------------
global vma_init
vma_init:
    mov qword [vma_list_head], 0
    ret

; -----------------------------------------------------------------------------
; vma_create — creates a non-overlapping Virtual Memory Area (VMA)
; Input:
;   RDI = start virtual address
;   RSI = size in bytes
;   RDX = VMA flags
; Output:
;   RAX = pointer to the created VMA structure, or 0 if overlap/OOM
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9
; -----------------------------------------------------------------------------
global vma_create
vma_create:
    push rbx
    push r12
    push r13
    push r14

    ; Page-align the start address down
    mov rbx, rdi
    and rbx, -4096                  ; RBX = aligned start address
    
    ; Page-align the size up
    mov r12, rsi
    add r12, 4095
    and r12, -4096                  ; R12 = aligned size
    
    ; Calculate end address (start + size)
    mov r13, rbx
    add r13, r12                    ; R13 = end address (exclusive)
    
    mov r14, rdx                    ; R14 = flags

    ; 1. Check for overlap with existing VMAs
    mov rsi, [vma_list_head]
.overlap_loop:
    test rsi, rsi
    jz .no_overlap
    
    ; Check: start < vma->end && end > vma->start
    mov rcx, [rsi + vma_t.start]
    mov rdx, [rsi + vma_t.end]
    
    cmp rbx, rdx
    jae .next_overlap
    cmp r13, rcx
    jbe .next_overlap
    
    ; Overlap detected!
    jmp .error_overlap

.next_overlap:
    mov rsi, [rsi + vma_t.next]
    jmp .overlap_loop

.no_overlap:
    extern sched_get_current_thread
    extern kswapd_check_and_reclaim
    ; Allocate stack space for temporary pointers (thread and cgroup)
    sub rsp, 16
    mov qword [rsp + 0], 0          ; current thread pointer
    mov qword [rsp + 8], 0          ; cgroup pointer

    ; Get current thread and cgroup
    call sched_get_current_thread
    test rax, rax
    jz .cgroup_done_init
    mov [rsp + 0], rax              ; save thread pointer
    
    mov rsi, [rax + thread_t.cgroup_ptr]
    mov [rsp + 8], rsi              ; save cgroup pointer
.cgroup_done_init:

    ; Check if cgroup exists
    mov rsi, [rsp + 8]
    test rsi, rsi
    jz .check_global_overcommit

    ; Soft limit check
    mov rdi, r12
    shr rdi, 12                     ; RDI = requested pages
    mov rdx, [rsi + mem_cgroup_t.usage]
    add rdx, rdi                    ; RDX = usage + requested_pages
    cmp rdx, [rsi + mem_cgroup_t.soft_limit]
    jbe .check_hard_limit

    ; Soft limit exceeded! Trigger reclaim pressure.
    push rdi
    push rsi
    push rdx
    mov rsi, msg_cgroup_soft_limit_exceeded
    call uart_print_str

    mov r8, [rsp + 8]               ; reload cgroup pointer
    mov rax, [r8 + mem_cgroup_t.id]
    call uart_print_dec
    mov rsi, msg_cgroup_reclaim_trigger
    call uart_print_str
    pop rdx
    pop rsi
    pop rdi

    call kswapd_check_and_reclaim

.check_hard_limit:
    mov rsi, [rsp + 8]              ; RSI = cgroup pointer
.hard_limit_loop:
    mov rdi, r12
    shr rdi, 12                     ; RDI = requested pages
    mov rdx, [rsi + mem_cgroup_t.usage]
    add rdx, rdi                    ; RDX = usage + requested_pages
    cmp rdx, [rsi + mem_cgroup_t.hard_limit]
    jbe .check_global_overcommit    ; if <= hard_limit, we are good!

    ; Hard limit exceeded! Loop to find a victim in the cgroup.
    mov rdi, rsi                    ; RDI = cgroup pointer
    call virt_oom_select_victim_in_cgroup
    test rax, rax
    jz .error_oom_cleanup           ; if no victim inside cgroup, fail allocation (OOM)

    ; Kill the victim thread inside cgroup
    mov rdi, rax
    call virt_oom_kill_process

    mov rsi, [rsp + 8]              ; reload cgroup pointer
    jmp .hard_limit_loop

.check_global_overcommit:
    ; 2. Check overcommit policy before allocating
    mov rdi, r12
    shr rdi, 12                     ; RDI = requested pages
    call virt_overcommit_check
    test rax, rax
    jnz .alloc_vma

    ; Overcommit check failed (OOM)! Invoke OOM Killer to select and kill a victim.
.oom_loop:
    call virt_oom_select_victim     ; RAX = victim thread_t pointer
    test rax, rax
    jz .error_oom_cleanup           ; if no victim found, fail allocation

    ; Kill the victim process to reclaim its memory
    mov rdi, rax
    call virt_oom_kill_process

    ; Try allocation check again
    mov rdi, r12
    shr rdi, 12                     ; RDI = requested pages
    call virt_overcommit_check
    test rax, rax
    jz .oom_loop                    ; if it still fails, try killing another victim!

.alloc_vma:

    ; 3. Allocate VMA node from the heap
    mov rdi, vma_t_size
    call heap_alloc
    test rax, rax
    jz .error_oom_cleanup
    
    ; Populate the VMA structure
    mov [rax + vma_t.start], rbx
    mov [rax + vma_t.end], r13
    mov [rax + vma_t.flags], r14
    mov qword [rax + vma_t.next], 0
    mov qword [rax + vma_t.file_ptr], 0
    mov qword [rax + vma_t.file_off], 0
    mov qword [rax + vma_t.file_size], 0

    ; Charge allocation to thread and cgroup usage
    mov rcx, r12
    shr rcx, 12                     ; RCX = requested pages
    
    mov rdx, [rsp + 0]              ; RDX = current thread pointer
    test rdx, rdx
    jz .cgroup_charge_done
    
    add [rdx + thread_t.mem_usage], rcx
    
    mov rsi, [rsp + 8]              ; RSI = cgroup pointer
    test rsi, rsi
    jz .cgroup_charge_done
    add [rsi + mem_cgroup_t.usage], rcx
    
.cgroup_charge_done:
    ; Deallocate stack frame
    add rsp, 16

    ; 3. Insert VMA into ascending address-sorted list
    mov rdx, [vma_list_head]
    test rdx, rdx
    jz .insert_head_empty
    
    cmp rbx, [rdx + vma_t.start]
    jb .insert_head
    
    ; Search for insertion spot (node before VMA)
    mov rsi, rdx
.insert_search:
    mov rcx, [rsi + vma_t.next]
    test rcx, rcx
    jz .insert_after
    
    cmp rbx, [rcx + vma_t.start]
    jb .insert_after
    
    mov rsi, rcx
    jmp .insert_search

.insert_after:
    mov rcx, [rsi + vma_t.next]
    mov [rax + vma_t.next], rcx
    mov [rsi + vma_t.next], rax
    jmp .done

.insert_head:
    mov [rax + vma_t.next], rdx
    mov [vma_list_head], rax
    jmp .done

.insert_head_empty:
    mov [vma_list_head], rax

.done:
    ; Update virt_reserved_pages count
    mov rcx, r12
    shr rcx, 12
    add [virt_reserved_pages], rcx

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.error_oom_cleanup:
    add rsp, 16
    jmp .error_oom

.error_overlap:
.error_oom:
    xor rax, rax                    ; return 0 on error
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; vma_find — finds the VMA containing a given virtual address
; Input:
;   RDI = virtual address
; Output:
;   RAX = pointer to VMA structure, or 0 if not found
; -----------------------------------------------------------------------------
global vma_find
vma_find:
    mov rax, [vma_list_head]
.loop:
    test rax, rax
    jz .not_found
    
    mov rcx, [rax + vma_t.start]
    mov rdx, [rax + vma_t.end]
    
    cmp rdi, rcx
    jb .next
    cmp rdi, rdx
    jb .found                       ; if start <= addr < end, found!
    
.next:
    mov rax, [rax + vma_t.next]
    jmp .loop

.found:
    ret

.not_found:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; vma_destroy — removes and frees a VMA
; Input:
;   RDI = pointer to VMA structure to destroy
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global vma_destroy
vma_destroy:
    test rdi, rdi
    jz .done
    
    push rbx
    mov rbx, rdi                    ; RBX = target VMA to destroy
    
    ; Find and remove VMA from list
    mov rsi, [vma_list_head]
    test rsi, rsi
    jz .pop_done
    
    cmp rsi, rbx
    je .remove_head
    
.search_loop:
    mov rcx, [rsi + vma_t.next]
    test rcx, rcx
    jz .pop_done
    
    cmp rcx, rbx
    je .remove_next
    
    mov rsi, rcx
    jmp .search_loop

.remove_next:
    mov rdx, [rbx + vma_t.next]
    mov [rsi + vma_t.next], rdx
    jmp .free_node

.remove_head:
    mov rdx, [rbx + vma_t.next]
    mov [vma_list_head], rdx

.free_node:
    ; Calculate page count of VMA to destroy and update virt_reserved_pages count
    mov rcx, [rbx + vma_t.end]
    sub rcx, [rbx + vma_t.start]
    shr rcx, 12
    sub [virt_reserved_pages], rcx

    ; Release charge from thread and cgroup
    push rcx                        ; save page count
    call sched_get_current_thread
    pop rcx                         ; restore page count
    test rax, rax
    jz .skip_cgroup_release
    
    ; Release thread usage (clamp to 0)
    mov rdx, [rax + thread_t.mem_usage]
    cmp rdx, rcx
    jbe .zero_thread_usage
    sub rdx, rcx
    mov [rax + thread_t.mem_usage], rdx
    jmp .thread_release_done
.zero_thread_usage:
    mov qword [rax + thread_t.mem_usage], 0
.thread_release_done:

    ; Release cgroup usage
    mov rsi, [rax + thread_t.cgroup_ptr]
    test rsi, rsi
    jz .skip_cgroup_release
    
    mov rdx, [rsi + mem_cgroup_t.usage]
    cmp rdx, rcx
    jbe .zero_cgroup_usage
    sub rdx, rcx
    mov [rsi + mem_cgroup_t.usage], rdx
    jmp .skip_cgroup_release
.zero_cgroup_usage:
    mov qword [rsi + mem_cgroup_t.usage], 0
.skip_cgroup_release:

    ; Free VMA structure back to heap
    mov rdi, rbx
    call heap_free

.pop_done:
    pop rbx
.done:
    ret

; -----------------------------------------------------------------------------
; virt_create_user_pml4 — creates a shadow User PML4 page table for KPTI
; Input:
;   RDI = physical address of the Kernel PML4 (if 0, reads current CR3)
; Output:
;   RAX = physical address of the User PML4, or 0 if OOM
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9
; -----------------------------------------------------------------------------
global virt_create_user_pml4
virt_create_user_pml4:
    push rbx
    push r12
    
    mov rbx, rdi
    test rbx, rbx
    jnz .have_kernel_pml4
    mov rbx, cr3
    and rbx, 0xFFFFFFFFFFFFF000     ; Rbx = current Kernel PML4
.have_kernel_pml4:

    ; 1. Allocate a physical page for the User PML4
    call phys_alloc_page
    test rax, rax
    jz .oom
    mov r12, rax                    ; R12 = new User PML4 physical address

    ; 2. Zero out the new User PML4
    mov rdi, r12
    mov rsi, 4096
    call memzero

    ; 3. Copy user-space mappings (entries 0 to 255) from Kernel PML4
    ; Each entry is 8 bytes. 256 entries = 2048 bytes.
    mov rdi, r12                    ; dest
    mov rsi, rbx                    ; source
    mov rdx, 2048                   ; size in bytes
    call memcpy

    ; 4. Copy the kernel exception/trampoline mapping (PML4 entry 511)
    ; This is required so the CPU can transition to Ring 0 during interrupts.
    mov rcx, [rbx + 511 * 8]
    mov [r12 + 511 * 8], rcx

    mov rax, r12                    ; return User PML4
    jmp .exit

.oom:
    xor rax, rax                    ; return 0 on OOM

.exit:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_decoy_init — allocates and populates the global decoy physical page
; Input:  none
; Output: RAX = physical address of decoy page, or 0 on failure
; -----------------------------------------------------------------------------
global virt_decoy_init
virt_decoy_init:
    push rbx
    push rdi
    push rsi
    push rdx
    
    ; 1. Allocate a physical page frame
    call phys_alloc_page
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = decoy physical frame
    
    ; 2. Initialize the page frame with NOPs (0x90)
    mov rdi, rbx                    ; destination
    mov rsi, 0x90                   ; NOP instruction
    mov rdx, 4096                   ; 4KB size
    call memset
    
    ; 3. Place a RET instruction (0xC3) at the end of the page to safely return execution
    mov byte [rbx + 4095], 0xC3     ; RET instruction
    
    ; 4. Store the physical address in the global variable
    mov [decoy_page_phys], rbx
    mov rax, rbx
    jmp .done
    
.fail:
    xor rax, rax
.done:
    pop rdx
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_map_decoy — maps a virtual address to the shared decoy physical frame
; Input:
;   RDI = virtual address (should be 4KB page aligned)
;   RDX = mapping flags (e.g. PAGE_USER)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global virt_map_decoy
virt_map_decoy:
    push rbx
    push r12
    push r13
    
    mov r12, rdi                    ; r12 = virtual address
    mov r13, rdx                    ; r13 = mapping flags
    
    ; Check if the decoy page has been initialized
    mov rbx, [decoy_page_phys]
    test rbx, rbx
    jnz .do_map
    
    ; Initialize the decoy page
    call virt_decoy_init
    test rax, rax
    jz .fail
    mov rbx, rax
    
.do_map:
    ; Map the virtual address to the decoy page with given flags, ensuring executable (clear NX)
    mov rdi, r12
    mov rsi, rbx                    ; physical address of decoy page
    
    ; Clear PAGE_NX to allow execution on the decoy page
    mov rcx, PAGE_NX
    not rcx
    and r13, rcx
    
    mov rdx, r13
    call virt_map                   ; RAX = success status (1 or 0)
    jmp .done
    
.fail:
    xor rax, rax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_logical_to_physical_vaddr — translates a logical virtual address to its physical shuffled virtual address
; Input:
;   RDI = logical virtual address
; Output:
;   RAX = physical shuffled virtual address
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global virt_logical_to_physical_vaddr
virt_logical_to_physical_vaddr:
    mov rax, rdi
    shr rax, 39
    and rax, 0x1FF                  ; RAX = logical PML4 index
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]  ; RAX = physical PML4 index
    
    ; Reconstruct physical virtual address
    mov rcx, rdi
    mov rdx, 0xFFFFFF8000000000
    and rcx, ~rdx                   ; clear logical PML4 index and sign bits
    
    shl rax, 39                     ; shift physical index to bits 39-47
    
    ; Apply sign extension if physical index >= 256
    cmp rax, 0x8000000000           ; index 256
    jb .no_sign_ext
    or rax, rdx                     ; set sign bits
.no_sign_ext:
    or rax, rcx                     ; merge back offset
    ret

; -----------------------------------------------------------------------------
; virt_overcommit_check — checks if page allocation violates overcommit policy
; Input:
;   RDI = number of virtual pages requested
; Output:
;   RAX = 1 if reservation is allowed, 0 if denied
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
extern current_swap_device
extern phys_state
global virt_overcommit_check
virt_overcommit_check:
    push rbx
    
    ; Load requested pages
    mov rbx, rdi                    ; RBX = requested pages
    
    ; Read current overcommit mode
    mov rcx, [overcommit_mode]
    
    ; Mode 1: always overcommit
    cmp rcx, 1
    je .allow
    
    ; Mode 0: never overcommit (strict limit)
    cmp rcx, 0
    je .check_never
    
    ; Mode 2: heuristic overcommit
    cmp rcx, 2
    je .check_heuristic
    
    ; Fallback: allow if mode is unrecognized
    jmp .allow

.check_never:
    ; Strict limit: total VMA pages cannot exceed physical RAM
    mov rax, [virt_reserved_pages]
    add rax, rbx                    ; RAX = potential new reservation
    
    ; Load total physical pages from phys_state
    mov rcx, [phys_state + phys_state_t.total_pages]
    
    cmp rax, rcx
    jbe .allow
    jmp .deny

.check_heuristic:
    ; Heuristic limit: total VMA pages cannot exceed physical RAM * overcommit_ratio / 100 + swap capacity
    mov rax, [virt_reserved_pages]
    add rax, rbx                    ; RAX = potential new reservation
    
    ; Calculate physical RAM allowance = total_pages * overcommit_ratio / 100
    push rax
    push rsi
    mov rax, [phys_state + phys_state_t.total_pages]
    mov rsi, [overcommit_ratio]
    mul rsi                         ; RDX:RAX = total_pages * overcommit_ratio
    mov rsi, 100
    div rsi                         ; RAX = (total_pages * overcommit_ratio) / 100
    mov rcx, rax                    ; RCX = physical RAM allowance
    pop rsi
    pop rax
    
    ; Check if a swap device is active and add its capacity
    push rax
    mov rdx, [current_swap_device]
    test rdx, rdx
    jz .no_swap
    
    ; Add swap capacity (max_slots)
    add rcx, [rdx + swap_device_t.max_slots]

.no_swap:
    pop rax
    
    cmp rax, rcx
    jbe .allow
    jmp .deny

.allow:
    mov rax, 1
    jmp .exit

.deny:
    xor rax, rax

.exit:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_oom_calculate_score — calculates OOM score for a given thread
; Input:
;   RDI = pointer to thread_t
; Output:
;   RAX = OOM score (mem_usage * time_alive * priority_weight)
; Clobbers: RAX, RDX
; -----------------------------------------------------------------------------
global virt_oom_calculate_score
virt_oom_calculate_score:
    test rdi, rdi
    jz .err
    
    mov rax, [rdi + thread_t.mem_usage]
    mov rdx, [rdi + thread_t.time_alive]
    mul rdx                         ; RDX:RAX = mem_usage * time_alive
    
    mov rdx, [rdi + thread_t.priority_weight]
    mul rdx                         ; RDX:RAX = (mem_usage * time_alive) * priority_weight
    
    ret
    
.err:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; virt_oom_select_victim — selects the active thread with the lowest OOM score
; Output:
;   RAX = pointer to thread_t of selected victim, or 0 if none
; Clobbers: RAX, RCX, RDX, RDI
; -----------------------------------------------------------------------------
extern thread_count
extern thread_table
global virt_oom_select_victim
virt_oom_select_victim:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [thread_count]
    test r12, r12
    jz .no_victim
    
    xor r13, r13                    ; R13 = current index i = 0
    mov r14, -1                     ; R14 = lowest score (initialize to max uint64)
    xor r15, r15                    ; R15 = pointer to best victim thread_t (0)
    
.loop:
    cmp r13, r12
    jae .done
    
    ; Calculate thread pointer
    mov rax, r13
    imul rax, thread_t_size
    lea rbx, [thread_table + rax]   ; RBX = current thread pointer
    
    ; Check if active
    mov rax, [rbx + thread_t.flags]
    test rax, 1
    jz .next
    
    ; Calculate score
    mov rdi, rbx
    call virt_oom_calculate_score   ; RAX = score
    
    ; Compare with lowest score
    cmp rax, r14
    jae .next                       ; if current score >= lowest score, skip
    
    mov r14, rax                    ; update lowest score
    mov r15, rbx                    ; update best victim pointer
    
.next:
    inc r13
    jmp .loop
    
.done:
    mov rax, r15                    ; RAX = victim thread pointer (or 0)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    
.no_victim:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_oom_kill_process — sends SIGKILL to a thread and reclaims its memory
; Input:
;   RDI = pointer to thread_t to kill
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global virt_oom_kill_process
virt_oom_kill_process:
    test rdi, rdi
    jz .done
    
    push rbx
    mov rbx, rdi                    ; RBX = thread pointer
    
    ; Check if OOM notifier callback is registered
    mov rax, [rbx + thread_t.oom_notifier]
    test rax, rax
    jz .do_kill
    
    ; Print notifier notification
    mov rsi, msg_oom_notify_prefix
    call uart_print_str
    
    mov rax, [rbx + thread_t.thread_id]
    call uart_print_dec
    
    mov rsi, msg_oom_notify_suffix
    call uart_print_str
    
    ; Invoke callback
    mov rdi, rbx                    ; pass thread pointer in RDI
    call qword [rbx + thread_t.oom_notifier]

.do_kill:
    ; 1. Print kill log message
    mov rsi, msg_oom_kill_prefix
    call uart_print_str
    
    mov rax, [rbx + thread_t.thread_id]
    call uart_print_dec
    
    mov rsi, msg_oom_kill_suffix
    call uart_print_str
    
    ; 2. Deactivate the thread
    mov qword [rbx + thread_t.flags], 0
    
    ; 3. Reclaim physical memory pages from its mem_usage
    mov rcx, [rbx + thread_t.mem_usage]
    test rcx, rcx
    jz .skip_mem
    
    ; Update physical allocator statistics
    add [phys_state + phys_state_t.free_pages], rcx
    sub [phys_state + phys_state_t.reserved_pages], rcx
    
    ; Update virtual reserved pages tracking
    sub [virt_reserved_pages], rcx
    
    ; If thread has cgroup, release its charge
    mov rsi, [rbx + thread_t.cgroup_ptr]
    test rsi, rsi
    jz .skip_cgroup_reclaim
    
    mov rdx, [rsi + mem_cgroup_t.usage]
    cmp rdx, rcx
    jbe .zero_usage
    sub rdx, rcx
    mov [rsi + mem_cgroup_t.usage], rdx
    jmp .skip_cgroup_reclaim
.zero_usage:
    mov qword [rsi + mem_cgroup_t.usage], 0
.skip_cgroup_reclaim:

    ; Clear thread's memory usage
    mov qword [rbx + thread_t.mem_usage], 0

.skip_mem:
    pop rbx
.done:
    ret

; -----------------------------------------------------------------------------
; virt_oom_register_notifier — registers an OOM callback for a thread
; Input:
;   RDI = pointer to thread_t
;   RSI = pointer to callback function
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global virt_oom_register_notifier
virt_oom_register_notifier:
    test rdi, rdi
    jz .done
    mov [rdi + thread_t.oom_notifier], rsi
.done:
    ret

; -----------------------------------------------------------------------------
; virt_memcg_create — initializes a memory cgroup
; Input:
;   RDI = cgroup ID
;   RSI = hard limit (pages)
;   RDX = soft limit (pages)
; Output: RAX = pointer to allocated and initialized mem_cgroup_t, or 0 if OOM
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global virt_memcg_create
virt_memcg_create:
    push rbx
    push r12
    push r13
    
    mov rbx, rdi                    ; RBX = cgroup ID
    mov r12, rsi                    ; R12 = hard limit
    mov r13, rdx                    ; R13 = soft limit
    
    mov rdi, mem_cgroup_t_size
    call heap_alloc
    test rax, rax
    jz .exit
    
    mov [rax + mem_cgroup_t.id], rbx
    mov [rax + mem_cgroup_t.hard_limit], r12
    mov [rax + mem_cgroup_t.soft_limit], r13
    mov qword [rax + mem_cgroup_t.usage], 0

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_memcg_destroy — destroys a memory cgroup
; Input: RDI = pointer to mem_cgroup_t
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI
; -----------------------------------------------------------------------------
global virt_memcg_destroy
virt_memcg_destroy:
    test rdi, rdi
    jz .done
    call heap_free
.done:
    ret

; -----------------------------------------------------------------------------
; virt_memcg_attach — attaches a thread to a memory cgroup
; Input:
;   RDI = pointer to thread_t
;   RSI = pointer to mem_cgroup_t (or 0 to detach)
; Output: none
; Clobbers: none
; -----------------------------------------------------------------------------
global virt_memcg_attach
virt_memcg_attach:
    test rdi, rdi
    jz .done
    mov [rdi + thread_t.cgroup_ptr], rsi
.done:
    ret

; -----------------------------------------------------------------------------
; virt_oom_select_victim_in_cgroup — selects the active thread in the cgroup with the lowest score
; Input:
;   RDI = pointer to mem_cgroup_t
; Output:
;   RAX = pointer to thread_t of selected victim, or 0 if none
; Clobbers: RAX, RCX, RDX, RDI
; -----------------------------------------------------------------------------
extern thread_count
extern thread_table
global virt_oom_select_victim_in_cgroup
virt_oom_select_victim_in_cgroup:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [thread_count]
    test r12, r12
    jz .no_victim
    
    mov r15, rdi                    ; R15 = target cgroup pointer
    xor r13, r13                    ; R13 = current index i = 0
    mov r14, -1                     ; R14 = lowest score (initialize to max uint64)
    xor rbx, rbx                    ; best victim pointer (0)
    
.loop:
    cmp r13, r12
    jae .done
    
    ; Calculate thread pointer
    mov rax, r13
    imul rax, thread_t_size
    lea rcx, [thread_table + rax]   ; RCX = current thread pointer
    
    ; Check if active
    mov rax, [rcx + thread_t.flags]
    test rax, 1
    jz .next
    
    ; Check if thread belongs to target cgroup
    mov rax, [rcx + thread_t.cgroup_ptr]
    cmp rax, r15
    jne .next
    
    ; Calculate score
    push rcx
    mov rdi, rcx
    call virt_oom_calculate_score   ; RAX = score
    pop rcx
    
    ; Compare with lowest score
    cmp rax, r14
    jae .next                       ; if current score >= lowest score, skip
    
    mov r14, rax                    ; update lowest score
    mov rbx, rcx                    ; update best victim pointer
    
.next:
    inc r13
    jmp .loop
    
.done:
    mov rax, rbx                    ; RAX = victim thread pointer (or 0)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    
.no_victim:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global msg_oom_notify_prefix
msg_oom_notify_prefix: db "[OOM Notifier] Invoking graceful shutdown callback for thread ", 0

align 8
global msg_oom_notify_suffix
msg_oom_notify_suffix: db " before termination.", 0x0D, 0x0A, 0

align 8
global msg_oom_kill_prefix
msg_oom_kill_prefix: db "[OOM Killer] Sending SIGKILL to thread ", 0

align 8
global msg_oom_kill_suffix
msg_oom_kill_suffix: db " to reclaim memory.", 0x0D, 0x0A, 0

align 8
global msg_cgroup_soft_limit_exceeded
msg_cgroup_soft_limit_exceeded: db "[cgroup] Warning: Soft limit exceeded for cgroup ", 0

align 8
global msg_cgroup_reclaim_trigger
msg_cgroup_reclaim_trigger: db ". Triggering reclaim...", 0x0D, 0x0A, 0

align 8
global overcommit_mode
overcommit_mode: dq 2 ; default: heuristic

align 8
global virt_reserved_pages
virt_reserved_pages: dq 0

align 8
global overcommit_ratio
overcommit_ratio: dq 150 ; default: 150%

align 8
global vma_list_head
vma_list_head: dq 0

align 8
global decoy_page_phys
decoy_page_phys: dq 0

%endif ; LIB_MEM_VIRT_VIRT_ASM
