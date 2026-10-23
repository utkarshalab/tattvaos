%ifndef GUARD_KERNEL_SCHED_SCHED_ASM
%define GUARD_KERNEL_SCHED_SCHED_ASM
; =============================================================================
; Utkarsha OS — kernel/sched/sched.asm
; =============================================================================
; Hybrid Multi-CPU Scheduler Core Loop (Option A + B + C) & Spinlock Safety.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "kernel/sched/sched.inc"
%include "lib/percpu.inc"           ; Run-queue slots are named percpu_t fields

section .text

; -----------------------------------------------------------------------------
; sched_init_real — Initialize scheduler for current CPU core
; Input:  none
; Output: RAX = 1 (success)
; -----------------------------------------------------------------------------
sched_init_real:
    push rbx
    push rdi

    ; Initialize CPU-local scheduler fields (GS base)
    mov qword [gs:percpu_t.current_fiber], 0            ; GS:64 = current_fiber
    mov qword [gs:percpu_t.idle_fiber], 0            ; GS:72 = idle_fiber
    mov qword [gs:percpu_t.run_queue_head], 0            ; GS:80 = run_queue_head
    mov qword [gs:percpu_t.run_queue_tail], 0            ; GS:88 = run_queue_tail
    mov dword [gs:percpu_t.fiber_count], 0            ; GS:96 = fiber_count
    mov qword [gs:percpu_t.ticks], 0           ; GS:104 = ticks
    mov dword [gs:percpu_t.steal_lock], 0           ; GS:112 = steal_lock
    mov dword [gs:percpu_t.need_resched], 0
    mov dword [gs:percpu_t.preempt_count], 0
    mov dword [gs:percpu_t.irq_depth], 0
    mov dword [gs:percpu_t.sched_flags], 0
    mov dword [gs:percpu_t.resched_ipis], 0
    mov dword [gs:percpu_t.drained_fibers], 0

    call fiber_guard_init

    ; Allocate idle fiber FCB for this CPU core
    mov rdi, sched_idle_task
    xor rsi, rsi
    mov rdx, PRIO_IDLE              ; Priority IDLE
    mov rcx, FIBER_RESTART_ALWAYS   ; Always restart idle task
    call fiber_create_preemptible
    test rax, rax
    jz .error

    mov rbx, rax
    mov ecx, [gs:percpu_t.cpu_id]
    mov rdx, 1
    shl rdx, cl
    mov [rbx + fcb_t.affinity], rdx ; idle contexts never migrate
    call sched_pop_next_fiber         ; idle is never ordinary runnable work
    cmp rax, rbx
    jne .error

    ; The bootstrap/AP entry stack becomes this CPU's idle context on its
    ; first software reschedule trap.  The allocated guarded stack remains a
    ; valid fresh context for recovery.
    mov [gs:percpu_t.idle_fiber], rbx
    mov [gs:percpu_t.current_fiber], rbx
    mov dword [rbx + fcb_t.state], FIBER_STATE_RUNNING
    mov dword [gs:percpu_t.sched_flags], SCHED_PERCPU_READY

    mov rax, 1
    pop rdi
    pop rbx
    ret

.error:
    xor rax, rax
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_push_fiber — Push a FCB to current core's ready queue tail (Spinlock Protected)
; Input:  RDI = FCB pointer
; Output: none
; -----------------------------------------------------------------------------
sched_push_fiber:
    push rdx
    mov rsi, [gs:percpu_t.self]
    mov edx, -1                    ; local lifecycle paths ignore run_mask
    call sched_queue_push_fiber
    pop rdx
    ret

; RDI=FCB, RSI=canonical per-CPU block.  The intrusive queue is protected by
; the destination CPU's own lock, so this primitive is safe for remote push.
; EDX is a logical CPU validated under the lock, or -1 for local/internal use.
; Returns EAX=1 if present/inserted and zero if rejected.
sched_queue_push_fiber:
    pushfq
    cli
    push rbx
    push rdx

    test rdi, rdi
    jz .done

    ; Acquire queue spinlock (GS:112)
.spin_acquire:
    lock bts dword [rsi + percpu_t.steal_lock], 0
    jc .spin_acquire

    cmp edx, -1
    je .run_allowed
    bt qword [rel smp_sched_run_mask], rdx
    jnc .rejected
.run_allowed:

    ; A duplicate enqueue corrupts the intrusive list.  Treat it as an
    ; idempotent request while the queue lock is held.
    bt dword [rdi + fcb_t.flags], 31
    jc .present

    mov qword [rdi + fcb_t.next], 0
    mov rbx, [rsi + percpu_t.run_queue_tail]

    test rbx, rbx
    jz .empty_queue

    ; Queue non-empty: attach to tail
    mov [rbx + fcb_t.next], rdi
    mov [rdi + fcb_t.prev], rbx
    mov [rsi + percpu_t.run_queue_tail], rdi
    jmp .inc_count

.empty_queue:
    ; Queue empty: set both head and tail to RDI
    mov qword [rdi + fcb_t.prev], 0
    mov [rsi + percpu_t.run_queue_head], rdi
    mov [rsi + percpu_t.run_queue_tail], rdi

.inc_count:
    or dword [rdi + fcb_t.flags], FIBER_FLAG_ON_RUNQ
    inc dword [rsi + percpu_t.fiber_count]
.present:
    mov eax, 1
    jmp .release
.rejected:
    xor eax, eax

    ; Release queue spinlock (GS:112)
.release:
    mov dword [rsi + percpu_t.steal_lock], 0

.done:
    test rdi, rdi
    jnz .return
    xor eax, eax
.return:
    pop rdx
    pop rbx
    popfq
    ret

; Publish one READY fiber to a selected online CPU and send its reschedule IPI.
; RDI=FCB, ESI=dense logical CPU ID.  CF=0/EAX=1 on publication; CF=1/EAX=0
; when the FCB, affinity, CPU, or scheduler state rejects the request.
global sched_push_fiber_to_cpu
sched_push_fiber_to_cpu:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13d, esi
    test r12, r12
    jz .failed
    cmp dword [r12 + fcb_t.state], FIBER_STATE_READY
    jne .failed
    test dword [r12 + fcb_t.flags], FIBER_FLAG_ON_RUNQ
    jnz .failed

    mov edi, r13d
    call smp_sched_percpu_for_id
    test rax, rax
    jz .failed
    mov rbx, rax
    test dword [rbx + percpu_t.sched_flags], SCHED_PERCPU_READY
    jz .failed
    bt qword [r12 + fcb_t.affinity], r13
    jnc .failed

    mov r11d, [r12 + fcb_t.cpu_id]
    mov [r12 + fcb_t.cpu_id], r13d
    mov rdi, r12
    mov rsi, rbx
    mov edx, r13d
    call sched_queue_push_fiber
    test eax, eax
    jnz .queued
    mov [r12 + fcb_t.cpu_id], r11d
    jmp .failed

.queued:
    cmp r13d, [gs:percpu_t.cpu_id]
    je .published
    mov edi, r13d
    call smp_sched_send_wake       ; timer delivery remains the bounded fallback
.published:
    mov eax, 1
    clc
    jmp .done
.failed:
    xor eax, eax
    stc
.done:
    pop r13
    pop r12
    pop rbx
    ret

; Move every CPU-0-eligible READY fiber off the current AP before it publishes
; parked.  Hard-affine work stays queued and resumes when that CPU is unparked.
; ponytail: park drainage targets the non-parkable BSP; add NUMA placement only
; when scheduler topology policy exists.
global sched_drain_current_cpu
sched_drain_current_cpu:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    pushfq
    pop rax
    mov [rsp], rax
    cli
    xor ebp, ebp
    mov r15d, [gs:percpu_t.cpu_id]
    test r15d, r15d
    jz .drain_done
    bt qword [rel smp_sched_run_mask], r15
    jc .drain_done
    mov r12, [gs:percpu_t.self]
    xor edi, edi
    call smp_sched_percpu_for_id
    test rax, rax
    jz .drain_done
    mov r13, rax

.drain_lock:
    lock bts dword [r12 + percpu_t.steal_lock], 0
    jc .drain_lock
    mov r14, [r12 + percpu_t.run_queue_head]
.drain_scan:
    test r14, r14
    jz .drain_unlock
    mov rbx, [r14 + fcb_t.next]
    bt qword [r14 + fcb_t.affinity], 0
    jnc .drain_next

    mov rax, [r14 + fcb_t.prev]
    mov rdx, [r14 + fcb_t.next]
    test rax, rax
    jz .drain_head
    mov [rax + fcb_t.next], rdx
    jmp .drain_tail
.drain_head:
    mov [r12 + percpu_t.run_queue_head], rdx
.drain_tail:
    test rdx, rdx
    jz .drain_last
    mov [rdx + fcb_t.prev], rax
    jmp .drain_detached
.drain_last:
    mov [r12 + percpu_t.run_queue_tail], rax
.drain_detached:
    dec dword [r12 + percpu_t.fiber_count]
    and dword [r14 + fcb_t.flags], ~FIBER_FLAG_ON_RUNQ
    mov qword [r14 + fcb_t.next], 0
    mov qword [r14 + fcb_t.prev], 0
    mov dword [r14 + fcb_t.cpu_id], 0
    mov rdi, r14
    mov rsi, r13
    mov edx, -1
    call sched_queue_push_fiber
    inc ebp
    inc dword [r12 + percpu_t.drained_fibers]
.drain_next:
    mov r14, rbx
    jmp .drain_scan
.drain_unlock:
    mov dword [r12 + percpu_t.steal_lock], 0
    test ebp, ebp
    jz .drain_done
    xor edi, edi
    call smp_sched_send_wake
.drain_done:
    mov eax, ebp
    mov rdx, [rsp]
    push rdx
    popfq
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_pop_next_fiber — Pop next FCB from current core's ready queue head (Spinlock Protected)
; Input:  none
; Output: RAX = FCB pointer (or 0 if queue empty)
; -----------------------------------------------------------------------------
sched_pop_next_fiber:
    pushfq
    cli
    push rbx

    ; Acquire queue spinlock (GS:112)
.spin_acquire:
    lock bts dword [gs:percpu_t.steal_lock], 0
    jc .spin_acquire

    mov rax, [gs:percpu_t.run_queue_head]                ; RAX = queue head (GS:80)
    test rax, rax
    jz .empty

    ; Update queue head to rax.next
    mov rbx, [rax + fcb_t.next]
    mov [gs:percpu_t.run_queue_head], rbx

    test rbx, rbx
    jz .became_empty

    mov qword [rbx + fcb_t.prev], 0
    jmp .dec_count

.became_empty:
    mov qword [gs:percpu_t.run_queue_tail], 0            ; Tail = 0

.dec_count:
    dec dword [gs:percpu_t.fiber_count]               ; Decrement fiber_count
    and dword [rax + fcb_t.flags], ~FIBER_FLAG_ON_RUNQ
    mov qword [rax + fcb_t.next], 0
    mov qword [rax + fcb_t.prev], 0
    jmp .release

.empty:
    xor rax, rax

.release:
    ; Release queue spinlock (GS:112)
    mov dword [gs:percpu_t.steal_lock], 0

    pop rbx
    popfq
    ret

; -----------------------------------------------------------------------------
; Explicit preemption guards for short lockless/ownership critical sections.
; The final enable services a timer request before returning to its caller.
; -----------------------------------------------------------------------------
global sched_preempt_disable
sched_preempt_disable:
    inc dword [gs:percpu_t.preempt_count]
    ret

global sched_preempt_enable
sched_preempt_enable:
    push rax
    cmp dword [gs:percpu_t.preempt_count], 0
    je .done
    dec dword [gs:percpu_t.preempt_count]
    jnz .done
    cmp dword [gs:percpu_t.need_resched], 0
    je .done
    cmp dword [gs:percpu_t.irq_depth], 0
    jne .done
    mov rax, [gs:percpu_t.current_fiber]
    test rax, rax
    jz .done
    test dword [rax + fcb_t.flags], FIBER_FLAG_PREEMPTIBLE
    jz .clear
    pushfq
    pop rax
    test eax, 1 << 9
    jz .done
    mov dword [gs:percpu_t.need_resched], 0
    int SCHED_YIELD_VECTOR
    jmp .done
.clear:
    mov dword [gs:percpu_t.need_resched], 0
.done:
    pop rax
    ret

; -----------------------------------------------------------------------------
; sched_yield_isr — ring-0 software reschedule interrupt (vector 0xF7)
; -----------------------------------------------------------------------------
global sched_yield_isr
sched_yield_isr:
    SCHED_PUSH_FRAME SCHED_YIELD_VECTOR
    cld
    inc dword [gs:percpu_t.irq_depth]

    mov rdi, rsp                    ; canonical outgoing frame
    and rsp, -16                    ; SysV call-site alignment
    call sched_switch_frame         ; RAX=next frame, RDX=old FCB to finalize

    cli
    dec dword [gs:percpu_t.irq_depth]
    mov rsp, rax                    ; old stack is now abandoned
    test rdx, rdx
    jz .restore
    mov dword [rdx + fcb_t.state], FIBER_STATE_DEAD
.restore:
    SCHED_POP_FRAME
    iretq

; -----------------------------------------------------------------------------
; sched_switch_frame — choose a context from a complete scheduler trap frame
; Input:  RDI = saved canonical frame
; Output: RAX = frame to restore, RDX = exited FCB safe to publish DEAD
; -----------------------------------------------------------------------------
sched_switch_frame:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                      ; six saves leave nested call sites misaligned

    mov r12, rdi
    xor r15d, r15d
    mov rbx, [gs:percpu_t.current_fiber]
    test rbx, rbx
    jz .same
    test dword [gs:percpu_t.sched_flags], SCHED_PERCPU_READY
    jz .same

    mov eax, [r12 + SCHED_FRAME_VECTOR]
    cmp eax, APIC_TIMER_VECTOR
    je .timer
    cmp eax, SCHED_WAKE_VECTOR
    je .timer
    cmp eax, SCHED_YIELD_VECTOR
    jne .same

    ; A voluntary switch from a critical section or IF=0 context is a kernel
    ; contract violation.  Leave it pending instead of corrupting ownership.
    cmp dword [gs:percpu_t.irq_depth], 1
    jne .defer
    cmp dword [gs:percpu_t.preempt_count], 0
    jne .defer
    test qword [r12 + SCHED_FRAME_RFLAGS], 1 << 9
    jz .defer
    mov dword [gs:percpu_t.need_resched], 0
    jmp .schedule

.timer:
    test dword [rbx + fcb_t.flags], FIBER_FLAG_PREEMPTIBLE
    jz .not_preemptible
    cmp rbx, [gs:percpu_t.idle_fiber]
    je .not_preemptible
    cmp dword [gs:percpu_t.irq_depth], 1
    jne .defer
    cmp dword [gs:percpu_t.preempt_count], 0
    jne .defer
    test qword [r12 + SCHED_FRAME_RFLAGS], 1 << 9
    jz .defer
    mov dword [gs:percpu_t.need_resched], 0

.schedule:
    mov [rbx + fcb_t.rsp], r12

    mov eax, [rbx + fcb_t.state]
    cmp eax, FIBER_STATE_RUNNING
    jne .not_running
    cmp rbx, [gs:percpu_t.idle_fiber]
    jne .queue_worker
    mov dword [rbx + fcb_t.state], FIBER_STATE_WAITING
    jmp .select
.queue_worker:
    mov dword [rbx + fcb_t.state], FIBER_STATE_READY
    mov rdi, rbx
    call sched_push_fiber
    jmp .select

.not_running:
    cmp eax, FIBER_STATE_EXITING
    jne .select
    mov r15, rbx
    jmp .select_idle                ; reap only after returning to the idle stack

.select:
    mov ecx, [gs:percpu_t.cpu_id]
    bt qword [rel smp_sched_run_mask], rcx
    jnc .select_idle
    cmp rbx, [gs:percpu_t.idle_fiber]
    je .pop_next
    cmp dword [r12 + SCHED_FRAME_VECTOR], SCHED_YIELD_VECTOR
    je .select_idle                 ; every cooperative yield gives idle/reaper a turn
.pop_next:
    call sched_pop_next_fiber
    test rax, rax
    jnz .have_next
.select_idle:
    mov rax, [gs:percpu_t.idle_fiber]
    test rax, rax
    jz .same
.have_next:
    mov r13, rax
    cmp r13, rbx
    jne .switch
    mov dword [rbx + fcb_t.state], FIBER_STATE_RUNNING
    jmp .same

.switch:
    mov rdi, [rbx + fcb_t.xsave_area]
    test rdi, rdi
    jz .restore_next
    mov eax, 7
    xor edx, edx
    xsave64 [rdi]

.restore_next:
    mov rdi, [r13 + fcb_t.xsave_area]
    test rdi, rdi
    jz .xstate_done
    mov eax, 7
    xor edx, edx
    xrstor64 [rdi]
.xstate_done:
    mov edi, [r13 + fcb_t.pkey]
    call pkey_switch

    mov eax, [gs:percpu_t.cpu_id]
    mov [r13 + fcb_t.cpu_id], eax
    mov [gs:percpu_t.current_fiber], r13
    mov dword [r13 + fcb_t.state], FIBER_STATE_RUNNING
    mov rax, [r13 + fcb_t.rsp]
    mov rdx, r15
    jmp .done

.not_preemptible:
    mov dword [gs:percpu_t.need_resched], 0
    jmp .same
.defer:
    mov dword [gs:percpu_t.need_resched], 1
.same:
    mov rax, r12
    xor edx, edx

.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_core_loop — Per-Core Hybrid Main Loop (Option A + B + C)
; Invoked on each CPU core after boot completes. Never returns.
; -----------------------------------------------------------------------------
sched_core_loop:
.loop:
    ; Honor runtime scheduler-park requests only at the idle safe point. The
    ; helper drains movable work and returns immediately on busy CPUs/the BSP.
    call smp_sched_park_if_requested

    ; -------------------------------------------------------------------------
    ; [OPTION A] Non-Blocking Hardware Ring Polling & Memory Reclaimer
    ; -------------------------------------------------------------------------
    call net_poll_stub
    call storage_poll_stub
    call timer_poll_stub
    call fiber_reap_dead            ; Reclaim memory of DEAD fibers

    ; One canonical software interrupt performs every voluntary dispatch.
    ; The unsafe global MPMC ring remains disconnected until target-CPU queues
    ; and wake IPIs are implemented in the next scheduler phase.
    call fiber_yield
    pause
    jmp .loop

; -----------------------------------------------------------------------------
; sched_work_steal — Steal a ready fiber from Lock-Free MPMC Queue
; Input:  none
; Output: RAX = Stolen FCB pointer (or 0 if no work stolen)
; -----------------------------------------------------------------------------
sched_work_steal:
    call smp_mpmc_pop
    ret

; -----------------------------------------------------------------------------
; sched_idle_task — Default background idle fiber
; -----------------------------------------------------------------------------
sched_idle_task:
.idle_loop:
    pause
    call fiber_yield
    jmp .idle_loop

; -----------------------------------------------------------------------------
; Event Stubs for Option A Polling
; -----------------------------------------------------------------------------
net_poll_stub:
    ret

storage_poll_stub:
    ret

timer_poll_stub:
    ret

%endif ; GUARD_KERNEL_SCHED_SCHED_ASM
