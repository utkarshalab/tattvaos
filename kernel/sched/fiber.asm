%ifndef GUARD_KERNEL_SCHED_FIBER_ASM
%define GUARD_KERNEL_SCHED_FIBER_ASM
; =============================================================================
; Tattva OS — kernel/sched/fiber.asm
; =============================================================================
; Ring-0 Cooperative Fiber Creation, Guard Pages, Canaries, and Context Switcher.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "kernel/sched/fiber.inc"
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
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = entry_point
    mov r13, rsi                    ; R13 = arg
    mov r14d, edx                   ; R14D = prio
    mov r15d, ecx                   ; R15D = restart_policy

    ; 1. Find a free FCB slot in fiber_pool
    mov rbx, fiber_pool
    mov ecx, FIBER_MAX_COUNT
.search_slot:
    cmp dword [rbx + fcb_t.state], FIBER_STATE_FREE
    je .slot_found
    add rbx, fcb_t_size
    loop .search_slot

    ; No free slots available
    xor rax, rax
    jmp .done

.slot_found:
    ; 2. Allocate 5 pages (20KB total: 1 guard page + 4 pages 16KB stack)
    mov rdi, 5
    call phys_alloc_pages
    test rax, rax
    jz .alloc_failed

    ; Set guard page & stack addresses
    mov [rbx + fcb_t.guard_addr], rax
    add rax, FIBER_GUARD_SIZE
    mov [rbx + fcb_t.stack_bottom], rax
    add rax, FIBER_STACK_SIZE
    mov [rbx + fcb_t.stack_top], rax

    ; Unmap 4KB Guard Page (VMA_NONE) below stack bottom to catch overflows
    mov rdi, [rbx + fcb_t.guard_addr]
    call virt_unmap

    ; 3. Setup FCB fields
    mov rax, [next_fiber_id]
    inc qword [next_fiber_id]
    mov [rbx + fcb_t.id], rax

    mov dword [rbx + fcb_t.state], FIBER_STATE_READY
    mov [rbx + fcb_t.prio], r14d
    mov [rbx + fcb_t.restart_policy], r15d
    mov dword [rbx + fcb_t.crash_count], 0
    mov [rbx + fcb_t.entry_point], r12
    mov [rbx + fcb_t.arg], r13
    mov qword [rbx + fcb_t.time_slice], 0

    ; Allocate Intel PKEY
    call pkey_alloc
    mov [rbx + fcb_t.pkey], eax

    ; Plant security stack canaries
    mov rdi, rbx
    call canary_plant

    ; 4. Format initial stack frame
    mov rdx, [rbx + fcb_t.stack_top]
    sub rdx, 16                     ; Reserve space for top canary marker

    sub rdx, 8
    mov qword [rdx], fiber_entry_wrapper

    sub rdx, 8
    mov qword [rdx], 0              ; RBP

    sub rdx, 8
    mov qword [rdx], 0              ; RBX

    sub rdx, 8
    mov qword [rdx], 0              ; R12

    sub rdx, 8
    mov qword [rdx], 0              ; R13

    sub rdx, 8
    mov qword [rdx], 0              ; R14

    sub rdx, 8
    mov qword [rdx], 0              ; R15

    mov [rbx + fcb_t.rsp], rdx

    ; 5. Push new FCB to current core's ready queue
    mov rdi, rbx
    call sched_push_fiber

    mov rax, rbx                    ; Return FCB pointer
    jmp .done

.alloc_failed:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
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
    push rsi
    push rdi

    mov rdi, [gs:percpu_t.current_fiber]                ; RDI = current_fiber
    test rdi, rdi
    jz .yield_done

    ; Verify stack canary before switching
    push rdi
    call canary_verify
    pop rdi
    test rax, rax
    jz .canary_failed

    ; If current fiber is RUNNING, set back to READY and push to ready queue
    cmp dword [rdi + fcb_t.state], FIBER_STATE_RUNNING
    jne .select_next
    mov dword [rdi + fcb_t.state], FIBER_STATE_READY
    call sched_push_fiber

.select_next:
    call sched_pop_next_fiber
    test rax, rax
    jnz .switch_to_next

    mov rsi, [gs:percpu_t.idle_fiber]                ; GS:72 = idle_fiber
    test rsi, rsi
    jz .yield_done
    jmp .do_switch

.switch_to_next:
    mov rsi, rax

.do_switch:
    cmp rdi, rsi
    jne .real_switch

    ; sched_pop_next_fiber popped the same fiber that was just pushed a few
    ; lines up (the only thing in the queue was itself) — there's no other
    ; ready work, so this returns to its own caller instead of paying for a
    ; context switch to itself. But its state was already flipped to READY
    ; above, on the assumption a switch would follow and set it back to
    ; RUNNING; skipping the switch here must not skip that too. Leaving it
    ; at READY while execution provably never left this stack meant the
    ; *next* fiber_yield call saw a fiber that wasn't RUNNING and silently
    ; skipped re-queuing it — the fiber ran exactly once more, yielded into
    ; the idle/boot context with nothing left in the queue to ever switch
    ; back to it, and was gone for good. Two prints, then permanent silence.
    mov dword [rdi + fcb_t.state], FIBER_STATE_RUNNING
    jmp .yield_done

.real_switch:
    ; Perform PKEY hardware key switch. RDI already holds the outgoing FCB
    ; pointer, which fiber_switch below needs — but pkey_switch's own first
    ; instruction is `mov edi, [rsi + fcb_t.pkey]`, so calling it unprotected
    ; here overwrites that pointer with a single-digit pkey value. fiber_switch
    ; would then save the outgoing stack through `[pkey_value + fcb_t.rsp]`,
    ; a wild write to whatever low physical address that tiny number lands on
    ; (see sched_core_loop's OPTION B block for the same defect on the pop
    ; path — this is the yield path's counterpart).
    push rdi
    mov edi, [rsi + fcb_t.pkey]
    call pkey_switch
    pop rdi

    mov [gs:percpu_t.current_fiber], rsi
    mov dword [rsi + fcb_t.state], FIBER_STATE_RUNNING

    ; Low-level context switch
    call fiber_switch

.yield_done:
    pop rdi
    pop rsi
    pop rbx
    ret

.canary_failed:
    ; Canary corrupted — hand to fault isolation trap!
    mov rdi, 14                     ; Vector 14 (#PF)
    mov rsi, 0xBADCAFA             ; Custom canary error code
    mov rdx, [rdi + fcb_t.entry_point]
    mov rcx, rsp
    jmp fiber_guard_trap

; -----------------------------------------------------------------------------
; fiber_reap_dead — Reclaim memory of finished/crashed DEAD fibers
; Input:  none
; Output: RAX = count of reaped fibers
; -----------------------------------------------------------------------------
fiber_reap_dead:
    push rbx
    push rcx
    push rdi

    mov rbx, fiber_pool
    mov ecx, FIBER_MAX_COUNT
    xor r8, r8                      ; R8 = reaped count

.scan_loop:
    cmp dword [rbx + fcb_t.state], FIBER_STATE_DEAD
    jne .next_slot

    ; If restart_policy is ALWAYS and crash_count < 5, supervisor handles restart.
    ; Otherwise, reclaim stack!
    cmp dword [rbx + fcb_t.restart_policy], FIBER_RESTART_ALWAYS
    jne .free_memory
    cmp dword [rbx + fcb_t.crash_count], 5
    jbe .next_slot

.free_memory:
    mov rdi, [rbx + fcb_t.guard_addr]
    test rdi, rdi
    jz .reset_fcb

    ; Free 5 pages (20KB total allocation)
    mov rsi, 5
    call phys_free_pages

.reset_fcb:
    mov dword [rbx + fcb_t.state], FIBER_STATE_FREE
    inc r8

.next_slot:
    add rbx, fcb_t_size
    loop .scan_loop

    mov rax, r8
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_exit — Called when a fiber completes execution
; Input:  none
; Output: never returns
; -----------------------------------------------------------------------------
fiber_exit:
    mov rdi, [gs:percpu_t.current_fiber]
    test rdi, rdi
    jz .halt

    mov dword [rdi + fcb_t.state], FIBER_STATE_DEAD

    ; Check if auto-restart daemon
    cmp dword [rdi + fcb_t.restart_policy], FIBER_RESTART_ALWAYS
    jne .do_yield

    mov rdi, [gs:percpu_t.current_fiber]
    call fiber_supervisor_handle_crash

.do_yield:
    call fiber_yield

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
    call rax

.exit:
    call fiber_exit
    ret

; -----------------------------------------------------------------------------
; fiber_switch — Assembly low-level context switcher
; Input:  RDI = Old FCB pointer, RSI = New FCB pointer
; -----------------------------------------------------------------------------
fiber_switch:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov [rdi + fcb_t.rsp], rsp
    mov rsp, [rsi + fcb_t.rsp]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp

    ret

section .data

align 16
global fiber_pool
fiber_pool:     times (FIBER_MAX_COUNT * fcb_t_size) db 0

align 8
next_fiber_id:  dq 1

%endif ; GUARD_KERNEL_SCHED_FIBER_ASM
