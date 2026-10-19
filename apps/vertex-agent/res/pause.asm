%ifndef GUARD_VERTEX_PAUSE_ASM
%define GUARD_VERTEX_PAUSE_ASM
; =============================================================================
; vertex-agent — Pause Fiber
; =============================================================================
; Minimal fiber that serves as PID 1 for pod sandbox
; Holds shared namespaces (netns, ipcns, mntns)
; =============================================================================

[BITS 64]

%include "kernel/sched/sched.inc"
%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_pause_fiber_entry — Pause fiber main loop
; =============================================================================
global vertex_pause_fiber_entry
vertex_pause_fiber_entry:
    ; 1. Log startup
    mov rsi, msg_pause_start
    call ulog_info

    ; 2. Signal readiness (parent waits on this)
    call fiber_signal_ready

    ; 3. Main loop: just yield forever
    ;    All work done by child container fibers
.pause_loop:
    ; Check for shutdown signal from vertex-agent
    mov rax, [pause_shutdown_flag]
    test rax, rax
    jnz .shutdown

    ; Yield CPU
    call fiber_yield
    jmp .pause_loop

.shutdown:
    ; 4. Cleanup: signal all child fibers to exit
    call vertex_pause_signal_children

    ; 5. Wait for children (with timeout)
    mov rdi, 10000000000    ; 10 seconds
    call fiber_wait_children

    ; 6. Log shutdown
    mov rsi, msg_pause_stop
    call ulog_info

    ; 7. Exit
    call fiber_exit
    ret


; -----------------------------------------------------------------------------
; vertex_pause_signal_children — Signal all child fibers to exit
; =============================================================================
vertex_pause_signal_children:
    push rbx
    push r12

    ; Iterate child fibers and send SIGTERM equivalent
    ; Children are tracked in pause_fiber.child_list
    mov rdi, [pause_child_list]
    test rdi, rdi
    jz .done

.iter:
    mov r12, [rdi]
    test r12, r12
    jz .done

    ; Send stop signal
    mov rdi, r12
    call fiber_stop_graceful

    mov rdi, [rdi + fiber_next]
    jmp .iter

.done:
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Data
; =============================================================================
section .data
align 8

pause_shutdown_flag:    dq 0
pause_child_list:       dq 0

msg_pause_start:        db "pause: Pod sandbox started", 0
msg_pause_stop:         db "pause: Pod sandbox stopped", 0

%endif ; GUARD_VERTEX_PAUSE_ASM