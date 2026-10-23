%ifndef GUARD_KERNEL_SCHED_FIBER_ASM
%define GUARD_KERNEL_SCHED_FIBER_ASM
; =============================================================================
; Utkarsha OS — kernel/sched/fiber.asm
; =============================================================================
; Ring-0 Cooperative Fiber Creation, Guard Pages, Canaries, and Context Switcher.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "kernel/sched/fiber.inc"
%include "kernel/sched/sched.inc"
%include "lib/percpu.inc"           ; current_fiber/idle_fiber are percpu_t fields

section .text

; -----------------------------------------------------------------------------
; fiber_system_init — Initialize global fiber pool
; Input:  none
; Output: RAX = 1 (success)
; -----------------------------------------------------------------------------
fiber_system_init:
    push rbx
    push rcx
    push rdi

    ; Zero out the global FCB array (FIBER_MAX_COUNT * fcb_t_size)
    mov rdi, fiber_pool
    mov rcx, (FIBER_MAX_COUNT * fcb_t_size) / 8
    xor rax, rax
    rep stosq

    mov qword [next_fiber_id], 1
    call pkey_init
    mov rax, 1

    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_create — Allocate and initialize a new Enterprise Ring-0 fiber
; Input:  RDI = entry_point function pointer
;         RSI = argument (64-bit value passed in RDI to entry_point)
;         RDX = priority (0=REALTIME, 1=HIGH, 2=NORMAL, 3=IDLE)
;         RCX = restart_policy (0=NEVER, 1=ALWAYS, 2=TRANSIENT)
; Output: RAX = Pointer to new FCB (or 0 if out of memory/slots)
; -----------------------------------------------------------------------------
fiber_create:
    xor r8d, r8d
    mov r9d, [gs:percpu_t.cpu_id]
    mov r10, FIBER_AFFINITY_ANY
    jmp fiber_create_flags

; Explicit opt-in API.  The legacy four-argument entry remains cooperative.
fiber_create_preemptible:
    mov r8d, FIBER_FLAG_PREEMPTIBLE
    mov r9d, [gs:percpu_t.cpu_id]
    mov r10, FIBER_AFFINITY_ANY
    jmp fiber_create_flags

; Targeted creation APIs. R8D is the initial logical CPU and R9 is the allowed
; CPU mask; the caller chooses whether later park drainage may migrate it.
global fiber_create_on_cpu
fiber_create_on_cpu:
    mov r10, r9
    mov r9d, r8d
    xor r8d, r8d
    jmp fiber_create_flags

global fiber_create_preemptible_on_cpu
fiber_create_preemptible_on_cpu:
    mov r10, r9
    mov r9d, r8d
    mov r8d, FIBER_FLAG_PREEMPTIBLE

; R8D=FIBER_FLAG_*, R9D=initial CPU, R10=affinity mask.
fiber_create_flags:
    push rbx
    push rbp
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24                     ; two locals plus SysV call-site alignment

    mov [rsp], r9
    mov [rsp + 8], r10

    mov r12, rdi                    ; R12 = entry_point
    mov r13, rsi                    ; R13 = arg
    mov r14d, edx                   ; R14D = prio
    mov r15d, ecx                   ; R15D = restart_policy
    mov ebp, r8d
    and ebp, FIBER_FLAG_PREEMPTIBLE

    test r10, r10
    jz .invalid_request
    cmp r9d, 64
    jae .invalid_request
    bt r10, r9
    jnc .invalid_request
    mov eax, [gs:percpu_t.cpu_id]
    cmp r9d, eax
    je .request_valid
    cmp r9d, [rel smp_active_cores]
    jae .invalid_request
    bt qword [rel smp_sched_run_mask], r9
    jnc .invalid_request
.request_valid:

    ; 1. Find a free FCB slot in fiber_pool
    mov rbx, fiber_pool
    mov ecx, FIBER_MAX_COUNT
.search_slot:
    xor eax, eax                    ; expected FIBER_STATE_FREE
    mov edx, FIBER_STATE_CLAIMED
    lock cmpxchg dword [rbx + fcb_t.state], edx
    je .slot_found
    add rbx, fcb_t_size
    loop .search_slot

    ; No free slots available
    xor rax, rax
    jmp .done

.slot_found:
    ; 2. Allocate guard + 16KB stack + one page-aligned XSAVE area.
    mov rdi, FIBER_TOTAL_PAGES
    call phys_alloc_pages
    test rax, rax
    jz .alloc_failed

    ; Set guard page & stack addresses
    mov [rbx + fcb_t.guard_addr], rax
    add rax, FIBER_GUARD_SIZE
    mov [rbx + fcb_t.stack_bottom], rax
    add rax, FIBER_STACK_SIZE
    mov [rbx + fcb_t.stack_top], rax
    mov [rbx + fcb_t.xsave_area], rax

    ; Unmap 4KB Guard Page (VMA_NONE) below stack bottom to catch overflows
    mov rdi, [rbx + fcb_t.guard_addr]
    call virt_unmap

    ; 3. Setup FCB fields
    mov eax, 1
    lock xadd qword [next_fiber_id], rax
    mov [rbx + fcb_t.id], rax

    mov [rbx + fcb_t.prio], r14d
    mov [rbx + fcb_t.restart_policy], r15d
    mov dword [rbx + fcb_t.crash_count], 0
    mov [rbx + fcb_t.entry_point], r12
    mov [rbx + fcb_t.arg], r13
    mov qword [rbx + fcb_t.time_slice], 0
    mov [rbx + fcb_t.flags], ebp
    mov eax, [rsp]
    mov [rbx + fcb_t.cpu_id], eax
    mov rax, [rsp + 8]
    mov [rbx + fcb_t.affinity], rax

    ; Allocate Intel PKEY
    call pkey_alloc
    mov [rbx + fcb_t.pkey], eax

    ; Plant canaries, initialize XSTATE, and synthesize the canonical IRET
    ; frame used by both newly created and supervisor-restarted fibers.
    mov rdi, rbx
    call fiber_reset_context

    ; 5. Publish only after the complete FCB and stack context are initialized.
    mov dword [rbx + fcb_t.state], FIBER_STATE_READY
    mov esi, [rsp]
    cmp esi, [gs:percpu_t.cpu_id]
    jne .publish_remote
    mov rdi, rbx
    call sched_push_fiber
    jmp .published

.publish_remote:
    mov rdi, rbx
    call sched_push_fiber_to_cpu
    jnc .published
    mov eax, [gs:percpu_t.cpu_id]
    mov [rbx + fcb_t.cpu_id], eax
    mov dword [rbx + fcb_t.state], FIBER_STATE_DEAD
    xor rax, rax
    jmp .done

.published:
    mov rax, rbx                    ; Return FCB pointer
    jmp .done

.alloc_failed:
    mov dword [rbx + fcb_t.state], FIBER_STATE_FREE
    xor rax, rax
    jmp .done

.invalid_request:
    xor rax, rax

.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_reset_context — clear private state and build a fresh canonical frame
; Input: RDI = exclusively owned FCB
; -----------------------------------------------------------------------------
fiber_reset_context:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi

    mov rdi, [rbx + fcb_t.stack_bottom]
    mov rcx, FIBER_STACK_SIZE / 8
    xor eax, eax
    cld
    rep stosq

    ; Header.XSTATE_BV=0 means architectural initial x87/SSE/AVX state.
    mov rdi, [rbx + fcb_t.xsave_area]
    mov rcx, FIBER_XSTATE_SIZE / 8
    xor eax, eax
    rep stosq

    mov rdi, rbx
    call canary_plant
    call fiber_build_initial_frame

    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_build_initial_frame — synthesize the frame restored by SCHED_POP_FRAME
; Input: RDI = FCB
; -----------------------------------------------------------------------------
fiber_build_initial_frame:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    mov rdx, [rbx + fcb_t.stack_top]
    sub rdx, 16                     ; keep top canary at stack_top - 16
    sub rdx, SCHED_FRAME_SIZE

    mov rdi, rdx
    mov rcx, SCHED_FRAME_SIZE / 8
    xor eax, eax
    rep stosq

    mov qword [rdx + SCHED_FRAME_VECTOR], SCHED_YIELD_VECTOR
    mov qword [rdx + SCHED_FRAME_RIP], fiber_entry_wrapper
    mov qword [rdx + SCHED_FRAME_CS], 0x08
    mov qword [rdx + SCHED_FRAME_RFLAGS], 0x202
    lea rax, [rdx + SCHED_FRAME_SIZE]
    mov [rdx + SCHED_FRAME_RSP], rax
    mov qword [rdx + SCHED_FRAME_SS], 0x10
    mov [rbx + fcb_t.rsp], rdx

    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_yield — Yield current fiber and context switch to next ready fiber
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
fiber_yield:
    push rbx
    mov rbx, [gs:percpu_t.current_fiber]
    test rbx, rbx
    jz .yield_done

    ; Verify stack canary before switching
    mov rdi, rbx
    call canary_verify
    test rax, rax
    jz .canary_failed

    ; Both cooperative yield and involuntary timer switching now save exactly
    ; the same full GPR/IRET frame. The ISR chooses and restores the next one.
    int SCHED_YIELD_VECTOR

.yield_done:
    pop rbx
    ret

.canary_failed:
    mov rdx, [rbx + fcb_t.entry_point]
    mov rcx, rsp
    mov edi, 14                     ; Vector 14 (#PF)
    mov esi, 0x0BADCAFA             ; Custom canary error code
    jmp fiber_guard_trap

; -----------------------------------------------------------------------------
; fiber_reap_dead — Reclaim memory of finished/crashed DEAD fibers
; Input:  none
; Output: RAX = count of reaped fibers
; -----------------------------------------------------------------------------
fiber_reap_dead:
    push rbx
    push r12
    push r13
    push r14
    push r15

    xor r13d, r13d                  ; reaped/restarted count
    mov rax, [gs:percpu_t.current_fiber]
    cmp rax, [gs:percpu_t.idle_fiber]
    jne .done                       ; never reclaim from a worker stack

    mov rbx, fiber_pool
    mov r12d, FIBER_MAX_COUNT

.scan_loop:
    mov eax, [gs:percpu_t.cpu_id]
    cmp [rbx + fcb_t.cpu_id], eax
    jne .next_slot

    mov eax, FIBER_STATE_DEAD
    mov edx, FIBER_STATE_REAPING
    lock cmpxchg dword [rbx + fcb_t.state], edx
    jne .next_slot

    mov eax, [rbx + fcb_t.restart_policy]
    cmp eax, FIBER_RESTART_ALWAYS
    je .restart_candidate
    cmp eax, FIBER_RESTART_TRANSIENT
    jne .free_memory
    cmp dword [rbx + fcb_t.crash_count], 0
    je .free_memory                  ; transient does not restart normal exits
.restart_candidate:
    cmp dword [rbx + fcb_t.crash_count], 5
    ja .free_memory

    mov rdi, rbx
    call fiber_reset_context
    and dword [rbx + fcb_t.flags], ~FIBER_FLAG_ON_RUNQ
    mov dword [rbx + fcb_t.state], FIBER_STATE_READY
    mov rdi, rbx
    call sched_push_fiber
    inc r13d
    jmp .next_slot

.free_memory:
    mov r15, [rbx + fcb_t.guard_addr]
    test r15, r15
    jz .reset_fcb

    ; phys_free_pages zeroes before release, so restore the deliberately
    ; unmapped guard page first.  Failure leaves the FCB retryable, not leaked.
    mov rdi, r15
    mov rsi, r15
    mov rdx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_NX
    call virt_map
    test rax, rax
    jz .retry_later

    mov rdi, r15
    mov rsi, FIBER_TOTAL_PAGES
    call phys_free_pages

.reset_fcb:
    mov qword [rbx + fcb_t.rsp], 0
    mov qword [rbx + fcb_t.stack_bottom], 0
    mov qword [rbx + fcb_t.stack_top], 0
    mov qword [rbx + fcb_t.guard_addr], 0
    mov qword [rbx + fcb_t.xsave_area], 0
    mov qword [rbx + fcb_t.next], 0
    mov qword [rbx + fcb_t.prev], 0
    mov qword [rbx + fcb_t.affinity], 0
    mov dword [rbx + fcb_t.flags], 0
    mov dword [rbx + fcb_t.state], FIBER_STATE_FREE
    inc r13d
    jmp .next_slot

.retry_later:
    mov dword [rbx + fcb_t.state], FIBER_STATE_DEAD

.next_slot:
    add rbx, fcb_t_size
    dec r12d
    jnz .scan_loop

.done:
    mov eax, r13d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_exit — Called when a fiber completes execution
; Input:  none
; Output: never returns
; -----------------------------------------------------------------------------
fiber_exit:
    mov rax, [gs:percpu_t.current_fiber]
    test rax, rax
    jz .halt
    cmp rax, [gs:percpu_t.idle_fiber]
    je .halt

    ; Only the scheduler ISR may publish DEAD, after it has moved RSP onto
    ; another fiber's frame.  EXITING cannot be reclaimed by any CPU.
    mov dword [rax + fcb_t.state], FIBER_STATE_EXITING
    int SCHED_YIELD_VECTOR

.halt:
    cli
    hlt
    jmp .halt

; -----------------------------------------------------------------------------
; fiber_entry_wrapper — Trampoline entry point for newly created fibers
; -----------------------------------------------------------------------------
fiber_entry_wrapper:
    mov rbx, [gs:percpu_t.current_fiber]
    test rbx, rbx
    jz .exit

    mov rax, [rbx + fcb_t.entry_point]
    mov rdi, [rbx + fcb_t.arg]
    ldmxcsr [rel default_mxcsr]     ; restore kernel FTZ/DAZ policy for fresh state
    call rax

.exit:
    jmp fiber_exit

section .data

align 16
global fiber_pool
fiber_pool:     times (FIBER_MAX_COUNT * fcb_t_size) db 0

align 8
next_fiber_id:  dq 1

%endif ; GUARD_KERNEL_SCHED_FIBER_ASM
