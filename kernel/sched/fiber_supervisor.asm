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
    push rbx
    push rsi

    mov rbx, rdi                    ; RBX = FCB pointer

    ; Check restart policy
    mov eax, [rbx + fcb_t.restart_policy]
    cmp eax, FIBER_RESTART_NEVER
    je .no_restart

    ; Check crash throttling limit (max 5 consecutive crashes)
    mov ecx, [rbx + fcb_t.crash_count]
    inc ecx
    mov [rbx + fcb_t.crash_count], ecx
    cmp ecx, 5
    ja .throttled

    ; 1. Reset stack pointer RSP back to top of stack
    mov rdx, [rbx + fcb_t.stack_top]

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

    ; 2. Re-plant canary cookie
    mov rdi, rbx
    call canary_plant

    ; 3. Reset state to READY & push back to ready queue
    mov dword [rbx + fcb_t.state], FIBER_STATE_READY
    mov rdi, rbx
    call sched_push_fiber

    mov rsi, msg_supervisor_restarted
    call uart_print_str
    jmp .done

.throttled:
    mov rsi, msg_supervisor_throttled
    call uart_print_str
    jmp .no_restart

.no_restart:
    ; Leave state as DEAD for memory reclaimer

.done:
    pop rsi
    pop rbx
    ret

section .data
msg_supervisor_restarted: db '[SUPERVISOR] Self-Healing Engine: Auto-restarted daemon fiber successfully!', 0x0D, 0x0A, 0
msg_supervisor_throttled: db '[SUPERVISOR WARNING] Daemon fiber crash limit exceeded (>5). Disabling restart.', 0x0D, 0x0A, 0

%endif ; GUARD_KERNEL_SCHED_FIBER_SUPERVISOR_ASM
