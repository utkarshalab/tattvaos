%ifndef GUARD_KERNEL_SCHED_SCHED_ASM
%define GUARD_KERNEL_SCHED_SCHED_ASM
; =============================================================================
; Tattva OS — kernel/sched/sched.asm
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

    call fiber_guard_init

    ; Allocate idle fiber FCB for this CPU core
    mov rdi, sched_idle_task
    xor rsi, rsi
    mov rdx, PRIO_IDLE              ; Priority IDLE
    mov rcx, FIBER_RESTART_ALWAYS   ; Always restart idle task
    call fiber_create
    test rax, rax
    jz .error

    mov [gs:percpu_t.idle_fiber], rax                ; Set GS:72 = idle_fiber
    mov [gs:percpu_t.current_fiber], rax                ; Set GS:64 = current_fiber
    mov dword [rax + fcb_t.state], FIBER_STATE_RUNNING

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
    push rbx
    push rdx

    test rdi, rdi
    jz .done

    ; Acquire queue spinlock (GS:112)
.spin_acquire:
    lock bts dword [gs:percpu_t.steal_lock], 0
    jc .spin_acquire

    mov qword [rdi + fcb_t.next], 0
    mov rbx, [gs:percpu_t.run_queue_tail]                ; RBX = current queue tail (GS:88)

    test rbx, rbx
    jz .empty_queue

    ; Queue non-empty: attach to tail
    mov [rbx + fcb_t.next], rdi
    mov [rdi + fcb_t.prev], rbx
    mov [gs:percpu_t.run_queue_tail], rdi                ; New tail = RDI
    jmp .inc_count

.empty_queue:
    ; Queue empty: set both head and tail to RDI
    mov qword [rdi + fcb_t.prev], 0
    mov [gs:percpu_t.run_queue_head], rdi                ; Head = RDI
    mov [gs:percpu_t.run_queue_tail], rdi                ; Tail = RDI

.inc_count:
    inc dword [gs:percpu_t.fiber_count]               ; Increment fiber_count

    ; Release queue spinlock (GS:112)
    mov dword [gs:percpu_t.steal_lock], 0

.done:
    pop rdx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_pop_next_fiber — Pop next FCB from current core's ready queue head (Spinlock Protected)
; Input:  none
; Output: RAX = FCB pointer (or 0 if queue empty)
; -----------------------------------------------------------------------------
sched_pop_next_fiber:
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
    mov qword [rax + fcb_t.next], 0
    mov qword [rax + fcb_t.prev], 0
    jmp .release

.empty:
    xor rax, rax

.release:
    ; Release queue spinlock (GS:112)
    mov dword [gs:percpu_t.steal_lock], 0

    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_core_loop — Per-Core Hybrid Main Loop (Option A + B + C)
; Invoked on each CPU core after boot completes. Never returns.
; -----------------------------------------------------------------------------
sched_core_loop:
.loop:
    ; -------------------------------------------------------------------------
    ; [OPTION A] Non-Blocking Hardware Ring Polling & Memory Reclaimer
    ; -------------------------------------------------------------------------
    call net_poll_stub
    call storage_poll_stub
    call timer_poll_stub
    call fiber_reap_dead            ; Reclaim memory of DEAD fibers

    ; -------------------------------------------------------------------------
    ; [OPTION B] Run Cooperative Fibers
    ; -------------------------------------------------------------------------
    call sched_pop_next_fiber
    test rax, rax
    jz .check_work_steal

    ; Execute popped fiber
    mov rsi, rax                    ; RSI = new fiber

    ; Perform PKEY hardware key switch first: it takes the new fiber's key in
    ; EDI, and fiber_switch below needs the OLD fiber pointer in RDI. Loading
    ; that before this call — as fiber_yield still does — has pkey_switch's
    ; own `mov edi, [rsi + fcb_t.pkey]` immediately overwrite it, so
    ; fiber_switch saves the outgoing stack through `[pkey_value +
    ; fcb_t.rsp]` instead of `[old_fcb + fcb_t.rsp]`: a wild write to
    ; whatever low physical address a single-digit pkey happens to land on,
    ; on the very first fiber this loop ever runs.
    mov edi, [rsi + fcb_t.pkey]
    call pkey_switch

    mov rdi, [gs:percpu_t.current_fiber]                ; RDI = current fiber
    mov [gs:percpu_t.current_fiber], rsi
    mov dword [rsi + fcb_t.state], FIBER_STATE_RUNNING

    call fiber_switch
    jmp .loop

.check_work_steal:
    ; -------------------------------------------------------------------------
    ; [OPTION C] SMP Work Stealing (Lock-Free MPMC Queue)
    ; -------------------------------------------------------------------------
    call sched_work_steal
    test rax, rax
    jnz .loop                       ; If stolen, loop around and execute

    pause                           ; CPU HT/SMT power-saving pause
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
