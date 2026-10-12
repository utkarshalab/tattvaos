%ifndef GUARD_KERNEL_SCHED_FIBER_SUPERVISOR_ASM
%define GUARD_KERNEL_SCHED_FIBER_SUPERVISOR_ASM
; =============================================================================
; Tattva OS — kernel/sched/fiber_supervisor.asm
; =============================================================================
; Erlang OTP Style Self-Healing Fiber Supervisor & Auto-Restart Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "kernel/sched/fiber.inc"

section .text

; -----------------------------------------------------------------------------
; fiber_supervisor_handle_crash — Self-healing restart engine for crashed fibers
; Input:  RDI = FCB pointer of crashed fiber
; Output: none
; -----------------------------------------------------------------------------
fiber_supervisor_handle_crash:
    push rsi
    ; Restarting or rebuilding a fiber while it still owns the active stack
    ; races the switch-out path.  Record the crash here; the owner CPU's idle
    ; reaper rebuilds the canonical frame only after DEAD is safely published.
    inc dword [rdi + fcb_t.crash_count]
    cmp dword [rdi + fcb_t.crash_count], 5
    jbe .deferred
    mov rsi, msg_supervisor_throttled
    call uart_print_str
    jmp .done

.deferred:
    mov rsi, msg_supervisor_deferred
    call uart_print_str
.done:
    pop rsi
    ret

section .data
msg_supervisor_deferred: db '[SUPERVISOR] Fiber restart deferred until safe stack handoff.', 0x0D, 0x0A, 0
msg_supervisor_throttled: db '[SUPERVISOR WARNING] Daemon fiber crash limit exceeded (>5). Disabling restart.', 0x0D, 0x0A, 0

%endif ; GUARD_KERNEL_SCHED_FIBER_SUPERVISOR_ASM
