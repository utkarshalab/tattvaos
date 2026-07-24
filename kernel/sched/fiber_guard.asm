; =============================================================================
; Tattva OS — kernel/sched/fiber_guard.asm
; =============================================================================
; Enterprise Fault Interceptor & Crash Telemetry Logger.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "sched/fiber.inc"
%include "sched/fiber_guard.inc"

section .text

; -----------------------------------------------------------------------------
; fiber_guard_init — Initialize crash telemetry ring buffer
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
fiber_guard_init:
    push rbx
    push rcx
    push rdi

    mov rdi, crash_log_ring
    mov rcx, (MAX_CRASH_LOGS * crash_record_t_size) / 8
    xor rax, rax
    rep stosq

    mov qword [crash_log_head], 0
    mov rax, 1

    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; fiber_guard_trap — Master Fault Interceptor called from IDT handlers
; Input:  RDI = Exception Vector (14=#PF, 13=#GP, 0=#DE, 6=#UD)
;         RSI = Error Code
;         RDX = Faulting RIP
;         RCX = Faulting RSP
; Output: Never returns to faulting code (recovers RSP back to sched_core_loop)
; -----------------------------------------------------------------------------
fiber_guard_trap:
    mov r8, [gs:64]                 ; R8 = current_fiber (GS:64)
    test r8, r8
    jz .raw_kernel_panic            ; If no fiber active, panic kernel!

    ; Check if running fiber is idle_fiber (GS:72)
    mov r9, [gs:72]
    cmp r8, r9
    je .raw_kernel_panic            ; Idle task crash is fatal

    ; 1. Read CR2 for Page Faults (#PF)
    mov r10, cr2

    ; 2. Record telemetry entry in crash_log_ring
    mov r11, [crash_log_head]
    imul r11, crash_record_t_size
    add r11, crash_log_ring

    rdtsc
    shl rdx, 32
    or rax, rdx
    mov [r11 + crash_record_t.timestamp], rax
    mov rax, [r8 + fcb_t.id]
    mov [r11 + crash_record_t.fiber_id], rax
    mov rax, [r8 + fcb_t.name]
    mov [r11 + crash_record_t.fiber_name], rax
    mov eax, [gs:8]                 ; CPU ID
    mov [r11 + crash_record_t.cpu_id], eax
    mov [r11 + crash_record_t.vector], edi
    mov [r11 + crash_record_t.error_code], rsi
    mov [r11 + crash_record_t.fault_rip], rdx
    mov [r11 + crash_record_t.fault_rsp], rcx
    mov [r11 + crash_record_t.fault_cr2], r10

    ; Advance telemetry head
    inc qword [crash_log_head]
    and qword [crash_log_head], (MAX_CRASH_LOGS - 1)

    ; 3. Print diagnostic crash report to UART
    push rdi
    push rsi
    push rdx
    mov rsi, msg_fault_header
    call uart_print_str

    mov rsi, msg_fault_fiber_id
    call uart_print_str
    mov rax, [r8 + fcb_t.id]
    call uart_print_dec
    mov rsi, msg_crlf
    call uart_print_str

    mov rsi, msg_fault_vector
    call uart_print_str
    pop rdx
    pop rsi
    pop rdi
    mov eax, edi
    call uart_print_dec
    mov rsi, msg_crlf
    call uart_print_str

    ; 4. Mark fiber as DEAD
    mov dword [r8 + fcb_t.state], FIBER_STATE_DEAD

    ; 5. Pass crashed fiber to Supervisor Engine for self-healing restart
    mov rdi, r8
    call fiber_supervisor_handle_crash

    ; 6. Recover CPU Stack RSP back to idle_fiber stack and resume main loop!
    mov r9, [gs:72]                 ; idle_fiber
    mov [gs:64], r9                 ; set current_fiber = idle_fiber
    mov dword [r9 + fcb_t.state], FIBER_STATE_RUNNING
    mov rsp, [r9 + fcb_t.rsp]

    ; Enable interrupts and jump to core loop
    sti
    jmp sched_core_loop

.raw_kernel_panic:
    ; Hardware crash in raw kernel initialization — cannot recover
    mov rsi, msg_fatal_panic
    call uart_print_str
.panic_loop:
    cli
    hlt
    jmp .panic_loop

section .data

align 64
crash_log_ring: times (MAX_CRASH_LOGS * crash_record_t_size) db 0
crash_log_head: dq 0

msg_fault_header: db '=================================================================', 0x0D, 0x0A
                  db '[FAULT ISOLATION] Ring-0 Fiber Hardware Exception Intercepted!', 0x0D, 0x0A, 0
msg_fault_fiber_id: db '  Crashed Fiber ID: ', 0
msg_fault_vector:   db '  Exception Vector: ', 0
msg_fatal_panic:    db '[FATAL PANIC] Unhandled hardware crash in raw kernel core!', 0x0D, 0x0A, 0
