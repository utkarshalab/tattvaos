; =============================================================================
; Tattva OS — lib/mem/virt/paging/userfaultfd.asm
; =============================================================================
; User-Space Page Fault Handling (userfaultfd) (Feature 12).
; Intercepts page faults, registers target VMAs, suspends faulting threads,
; and allows user-space handler daemons to resolve pages asynchronously.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGING_USERFAULTFD_ASM
%define LIB_MEM_VIRT_PAGING_USERFAULTFD_ASM

[BITS 64]

; Thread Structure Definition (from sched_affinity.asm)
struc thread_t
    .thread_id          resq 1      ; Unique thread ID (PID)
    .cpu_affinity_mask  resq 1      ; Bitmask of allowed CPUs
    .preferred_node     resd 1      ; Target NUMA node ID
    .current_cpu        resd 1      ; Current execution CPU ID
    .flags              resq 1      ; Thread flags (bit 0 = Active, bit 1 = Stalled)
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

; VMA layout (from virt.asm)
struc vma_local_t
    .start      resq 1
    .end        resq 1
    .flags      resq 1
    .next       resq 1
endstruc

; userfaultfd descriptor structure
struc uffd_desc_t
    .fd             resq 1      ; Unique descriptor ID
    .vma_start      resq 1      ; Registered VMA range start address
    .vma_end        resq 1      ; Registered VMA range end address
    .flags          resq 1      ; Mode / flags
    .fault_vaddr    resq 1      ; Faulting virtual address
    .fault_pid      resq 1      ; PID of faulting thread
    .fault_type     resq 1      ; 0 = read, 1 = write
    .state          resq 1      ; 0 = idle, 1 = pending, 2 = resolved
endstruc

section .text

extern vma_list_head
extern sched_get_current_thread
extern thread_table
extern thread_count
extern phys_alloc_page
extern phys_free_page
extern virt_map

; -----------------------------------------------------------------------------
; sys_userfaultfd_register — registers a virtual range to userfaultfd monitoring
; Input:
;   RDI = userfaultfd_descriptor
;   RSI = fault_vaddr
;   RDX = flags
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global sys_userfaultfd_register
sys_userfaultfd_register:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = fd
    mov r13, rsi                    ; R13 = fault_vaddr
    mov r14, rdx                    ; R14 = flags

    ; 1. Walk VMA tree to find the matching VMA range covering fault_vaddr
    mov r15, [vma_list_head]        ; R15 = VMA linked list head
.vma_loop:
    test r15, r15
    jz .fail                        ; No matching VMA found

    mov rbx, [r15 + vma_local_t.start]
    cmp r13, rbx
    jb .next_vma

    mov rbp, [r15 + vma_local_t.end]
    cmp r13, rbp
    jb .found_vma

.next_vma:
    mov r15, [r15 + vma_local_t.next]
    jmp .vma_loop

.found_vma:
    ; 2. Find an empty slot in uffd_table
    lea rcx, [uffd_table]
    xor r8, r8                      ; R8 = index = 0
.search_slot:
    cmp r8, 16
    jae .fail                       ; Table full, fail registration

    imul r9, r8, uffd_desc_t_size
    lea rdx, [rcx + r9]             ; RDX = &uffd_table[r8]
    cmp qword [rdx + uffd_desc_t.fd], 0
    jz .register_slot               ; Found empty slot!

    inc r8
    jmp .search_slot

.register_slot:
    ; 3. Fill the registration descriptor
    mov [rdx + uffd_desc_t.fd], r12
    mov rax, [r15 + vma_local_t.start]
    mov [rdx + uffd_desc_t.vma_start], rax
    mov rax, [r15 + vma_local_t.end]
    mov [rdx + uffd_desc_t.vma_end], rax
    mov [rdx + uffd_desc_t.flags], r14
    mov qword [rdx + uffd_desc_t.fault_vaddr], 0
    mov qword [rdx + uffd_desc_t.fault_pid], 0
    mov qword [rdx + uffd_desc_t.fault_type], 0
    mov qword [rdx + uffd_desc_t.state], 0    ; State = idle

    mov rax, 1                      ; Success
    jmp .exit

.fail:
    xor rax, rax                    ; Failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; handle_userfaultfd_fault — checks and intercepts page faults via userfaultfd
; Input:
;   RDI = faulting_vaddr (CR2)
;   RSI = error_code (bit 1 indicates read/write)
; Output:
;   RAX = 1 if intercepted (suspended), 0 if not registered (fallback to normal path)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global handle_userfaultfd_fault
handle_userfaultfd_fault:
    push rbx
    push rsi
    push rdi

    mov rbx, rdi                    ; RBX = CR2 (faulting address)
    mov r8, rsi                     ; R8 = error code

    ; Walk registered uffd table to check if CR2 falls within any range
    lea rcx, [uffd_table]
    xor r9, r9                      ; index = 0
.check_slot_loop:
    cmp r9, 16
    jae .no_intercept

    imul r10, r9, uffd_desc_t_size
    lea r11, [rcx + r10]            ; R11 = current descriptor pointer
    cmp qword [r11 + uffd_desc_t.fd], 0
    jz .next_slot                   ; Unused slot, skip

    ; check: vma_start <= CR2 < vma_end
    mov rax, [r11 + uffd_desc_t.vma_start]
    cmp rbx, rax
    jb .next_slot
    mov rax, [r11 + uffd_desc_t.vma_end]
    cmp rbx, rax
    jae .next_slot

    ; Found matching userfaultfd handler!
    ; Fill fault descriptor details
    mov [r11 + uffd_desc_t.fault_vaddr], rbx
    mov qword [r11 + uffd_desc_t.state], 1 ; State = pending

    ; Determine fault type: read (0) or write (1) from error code (bit 1)
    mov rdx, r8
    shr rdx, 1
    and rdx, 1
    mov [r11 + uffd_desc_t.fault_type], rdx

    ; Retrieve currently running thread and store its PID
    call sched_get_current_thread   ; RAX = thread pointer
    test rax, rax
    jz .no_intercept
    
    mov rcx, [rax + thread_t.thread_id]
    mov [r11 + uffd_desc_t.fault_pid], rcx

    ; Put the faulting thread to sleep (set bit 1 = Stalled of thread flags)
    or qword [rax + thread_t.flags], 2

    mov rax, 1                      ; Intercepted successfully
    jmp .done

.next_slot:
    inc r9
    jmp .check_slot_loop

.no_intercept:
    xor rax, rax                    ; Normal page fault handling path

.done:
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sys_userfaultfd_copy — resolves userfaultfd fault by mapping a populated page
; Input:
;   RDI = userfaultfd_descriptor
;   RSI = dest_vaddr (fault_vaddr)
;   RDX = src_vaddr  (user-space populated page source)
;   RCX = flags
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global sys_userfaultfd_copy
sys_userfaultfd_copy:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = fd
    mov r13, rsi                    ; R13 = dest_vaddr
    mov r14, rdx                    ; R14 = src_vaddr

    ; Find matching registered userfaultfd descriptor
    lea r8, [uffd_table]
    xor r9, r9                      ; index = 0
.search_fd_loop:
    cmp r9, 16
    jae .fail

    imul r10, r9, uffd_desc_t_size
    lea rbp, [r8 + r10]             ; RBP = &uffd_table[r9]
    cmp [rbp + uffd_desc_t.fd], r12
    je .found_fd

    inc r9
    jmp .search_fd_loop

.found_fd:
    ; Verify that state is pending (1) and faulting address matches
    cmp qword [rbp + uffd_desc_t.state], 1
    jne .fail
    mov rax, [rbp + uffd_desc_t.fault_vaddr]
    and rax, -4096                  ; page align
    mov r11, r13
    and r11, -4096
    cmp rax, r11
    jne .fail

    ; Allocate a physical page frame
    call phys_alloc_page            ; RAX = physical address
    test rax, rax
    jz .fail
    mov r15, rax                    ; R15 = physical page

    ; Copy 4KB data from src_vaddr (user space) to newly allocated frame
    push rsi
    push rdi
    mov rsi, r14                    ; RSI = src_vaddr
    mov rdi, r15                    ; RDI = phys page (identity mapped virtual)
    mov rcx, 512                    ; 512 quadwords = 4096 bytes
    cld
    rep movsq
    pop rdi
    pop rsi

    ; Map the virtual address (dest_vaddr) to the physical page
    mov rdi, r13                    ; virtual address
    mov rsi, r15                    ; physical address
    mov rdx, 0x07                   ; Present (1) | Writable (2) | User (4)
    call virt_map                   ; Map page
    test rax, rax
    jz .map_fail

    ; Wake the sleeping thread matching fault_pid
    mov r9, [rbp + uffd_desc_t.fault_pid]
    mov r10, [thread_count]
    test r10, r10
    jz .wake_done

    xor r8, r8                      ; thread table index
.wake_loop:
    cmp r8, r10
    jae .wake_done

    mov rax, r8
    imul rax, thread_t_size
    lea rcx, [thread_table + rax]   ; RCX = current thread pointer
    
    ; check active status
    mov rax, [rcx + thread_t.flags]
    test rax, 1
    jz .next_wake

    ; compare thread id
    cmp [rcx + thread_t.thread_id], r9
    je .wake_thread

.next_wake:
    inc r8
    jmp .wake_loop

.wake_thread:
    ; Wake it by clearing the Stalled flag (bit 1 of flags)
    and qword [rcx + thread_t.flags], ~2

.wake_done:
    ; Reset/mark userfaultfd descriptor resolved
    mov qword [rbp + uffd_desc_t.state], 2 ; state = resolved
    mov qword [rbp + uffd_desc_t.fd], 0    ; free descriptor slot

    mov rax, 1                      ; Success
    jmp .exit

.map_fail:
    ; Free the allocated physical page upon mapping fail
    mov rdi, r15
    call phys_free_page
.fail:
    xor rax, rax                    ; Failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .bss
align 8
global uffd_table
uffd_table: resb uffd_desc_t_size * 16 ; 16 userfaultfd registry slots

%endif ; LIB_MEM_VIRT_PAGING_USERFAULTFD_ASM
