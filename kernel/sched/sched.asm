; =============================================================================
; Tattva OS — kernel/sched/sched.asm
; =============================================================================
; Hybrid Multi-CPU Scheduler Core Loop (Option A + B + C).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "sched/sched.inc"

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
    mov qword [gs:64], 0            ; GS:64 = current_fiber
    mov qword [gs:72], 0            ; GS:72 = idle_fiber
    mov qword [gs:80], 0            ; GS:80 = run_queue_head
    mov qword [gs:88], 0            ; GS:88 = run_queue_tail
    mov dword [gs:96], 0            ; GS:96 = fiber_count
    mov qword [gs:104], 0           ; GS:104 = ticks
    mov dword [gs:112], 0           ; GS:112 = steal_lock

    ; Allocate idle fiber FCB for this CPU core
    mov rdi, sched_idle_task
    xor rsi, rsi
    call fiber_create
    test rax, rax
    jz .error

    mov [gs:72], rax                ; Set GS:72 = idle_fiber
    mov [gs:64], rax                ; Set GS:64 = current_fiber
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
; sched_push_fiber — Push a FCB to current core's ready queue tail
; Input:  RDI = FCB pointer
; Output: none
; -----------------------------------------------------------------------------
sched_push_fiber:
    push rbx
    push rdx

    test rdi, rdi
    jz .done

    mov qword [rdi + fcb_t.next], 0
    mov rbx, [gs:88]                ; RBX = current queue tail (GS:88)

    test rbx, rbx
    jz .empty_queue

    ; Queue non-empty: attach to tail
    mov [rbx + fcb_t.next], rdi
    mov [rdi + fcb_t.prev], rbx
    mov [gs:88], rdi                ; New tail = RDI
    jmp .inc_count

.empty_queue:
    ; Queue empty: set both head and tail to RDI
    mov [rdi + fcb_t.prev], 0
    mov [gs:80], rdi                ; Head = RDI
    mov [gs:88], rdi                ; Tail = RDI

.inc_count:
    inc dword [gs:96]               ; Increment fiber_count

.done:
    pop rdx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_pop_next_fiber — Pop next FCB from current core's ready queue head
; Input:  none
; Output: RAX = FCB pointer (or 0 if queue empty)
; -----------------------------------------------------------------------------
sched_pop_next_fiber:
    push rbx

    mov rax, [gs:80]                ; RAX = queue head (GS:80)
    test rax, rax
    jz .done

    ; Update queue head to rax.next
    mov rbx, [rax + fcb_t.next]
    mov [gs:80], rbx

    test rbx, rbx
    jz .became_empty

    mov qword [rbx + fcb_t.prev], 0
    jmp .dec_count

.became_empty:
    mov qword [gs:88], 0            ; Tail = 0

.dec_count:
    dec dword [gs:96]               ; Decrement fiber_count
    mov qword [rax + fcb_t.next], 0
    mov qword [rax + fcb_t.prev], 0

.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sched_core_loop — Per-Core Hybrid Main Loop (Option A + B + C)
; Invoked on each CPU core after boot completes. Never returns.
; -----------------------------------------------------------------------------
sched_core_loop:
.loop:
    ; -------------------------------------------------------------------------
    ; [OPTION A] Non-Blocking Hardware & Event Polling
    ; -------------------------------------------------------------------------
    call net_poll_stub
    call storage_poll_stub
    call timer_poll_stub

    ; -------------------------------------------------------------------------
    ; [OPTION B] Run Cooperative Fibers
    ; -------------------------------------------------------------------------
    call sched_pop_next_fiber
    test rax, rax
    jz .check_work_steal

    ; Execute popped fiber
    mov rsi, rax                    ; RSI = new fiber
    mov rdi, [gs:64]                ; RDI = current fiber
    mov [gs:64], rsi
    mov dword [rsi + fcb_t.state], FIBER_STATE_RUNNING
    call fiber_switch
    jmp .loop

.check_work_steal:
    ; -------------------------------------------------------------------------
    ; [OPTION C] SMP Work Stealing
    ; -------------------------------------------------------------------------
    call sched_work_steal
    test rax, rax
    jnz .loop                       ; If stolen, loop around and execute

    pause                           ; CPU HT/SMT power-saving pause
    jmp .loop

; -----------------------------------------------------------------------------
; sched_work_steal — Steal a ready fiber from a neighbor CPU core
; Input:  none
; Output: RAX = Stolen FCB pointer (or 0 if no work stolen)
; -----------------------------------------------------------------------------
sched_work_steal:
    ; Placeholder for SMP Work Stealing across multi-cores
    xor rax, rax
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
