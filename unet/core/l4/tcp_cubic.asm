%ifndef GUARD_UNET_CORE_L4_TCP_CUBIC_ASM
%define GUARD_UNET_CORE_L4_TCP_CUBIC_ASM
; =============================================================================
; Tattva OS — unet/core/l4/tcp_cubic.asm
; =============================================================================
; CUBIC Congestion Control (RFC 8312)
;
; CUBIC uses a cubic function for window growth:
;   W(t) = C * (t - K)^3 + W_max
;   K = cubic_root(W_max * (1 - beta) / C)
;
; Constants:
;   C = 0.4 (scaling constant)
;   beta = 0.7 (multiplicative decrease factor)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define CUBIC_C_NUM          4194304   ; C = 0.4 * 2^24 (fixed point)
%define CUBIC_C_DEN          10485760
%define CUBIC_BETA_NUM       7
%define CUBIC_BETA_DEN       10
%define CUBIC_HZ             1000       ; 1kHz tick rate
%define CUBIC_TCP_FRIENDLINESS 1

struc cubic_state_t
    .w_max:           resd 1      ; Max window before last reduction
    .w_last_max:      resd 1      ; Last max window (for fast convergence)
    .k:               resd 1      ; Time to reach W_max (in ticks)
    .origin_point:    resd 1      ; Window at start of current epoch
    .epoch_start:     resq 1      ; TSC at start of epoch
    .last_ack:        resd 1      ; Last ACK number for TCP friendliness
    .tcp_friendly:    resb 1      ; TCP friendliness mode
    .pad:             resb 3
endstruc

section .text

global cubic_init
global cubic_cong_event
global cubic_ack_received
global cubic_rtt_update
global cubic_cwnd_get

; -----------------------------------------------------------------------------
; cubic_init — Initialize CUBIC state
; Input: RDI = tcb_t*, RSI = cubic_state_t*
; -----------------------------------------------------------------------------
align 64
cubic_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; cubic_state_t*

    ; Initialize CUBIC state
    mov dword [r12 + cubic_state_t.w_max], 0
    mov dword [r12 + cubic_state_t.w_last_max], 0
    mov dword [r12 + cubic_state_t.k], 0
    mov dword [r12 + cubic_state_t.origin_point], 0
    mov qword [r12 + cubic_state_t.epoch_start], 0
    mov dword [r12 + cubic_state_t.last_ack], 0
    mov byte [r12 + cubic_state_t.tcp_friendly], CUBIC_TCP_FRIENDLINESS

    ; Set CC ops pointer in TCB
    lea rax, [cubic_ops]
    mov qword [rbx + tcb_t.cc_ops], rax
    mov qword [rbx + tcb_t.cc_state], r12

    ; Initialize cwnd to 10 MSS (RFC 6928)
    mov dword [rbx + tcb_t.cwnd], 10
    mov dword [rbx + tcb_t.ssthresh], 0xFFFFFFFF

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; cubic_cong_event — Handle congestion event (loss, ECN)
; Input: RDI = tcb_t*, RSI = event type
; -----------------------------------------------------------------------------
align 64
cubic_cong_event:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12d, esi           ; event type

    mov r13, qword [rbx + tcb_t.cc_state]
    test r13, r13
    jz .done

    ; Get current cwnd
    mov r14d, [rbx + tcb_t.cwnd]

    ; Fast convergence: if cwnd < last max, reduce last max
    mov eax, [r13 + cubic_state_t.w_last_max]
    test eax, eax
    jz .no_fast_conv
    cmp r14d, eax
    jge .no_fast_conv
    ; Reduce last max: W_last_max = W_last_max * (1 + beta) / 2
    imul eax, CUBIC_BETA_DEN + CUBIC_BETA_NUM
    shr eax, 1
    mov ecx, CUBIC_BETA_DEN
    xor edx, edx
    div ecx
    mov [r13 + cubic_state_t.w_last_max], eax

.no_fast_conv:
    ; W_max = current cwnd
    mov [r13 + cubic_state_t.w_max], r14d

    ; Multiplicative decrease: cwnd = cwnd * (1 - beta)
    imul r14d, CUBIC_BETA_DEN - CUBIC_BETA_NUM
    mov eax, r14d
    mov ecx, CUBIC_BETA_DEN
    xor edx, edx
    div ecx
    mov r14d, eax
    mov dword [rbx + tcb_t.cwnd], r14d

    ; ssthresh = cwnd (after reduction)
    mov dword [rbx + tcb_t.ssthresh], r14d

    ; Reset epoch
    mov dword [r13 + cubic_state_t.origin_point], r14d
    call rdtsc_get_cycles
    mov qword [r13 + cubic_state_t.epoch_start], rax

    ; Calculate K = cubic_root(W_max * (1 - beta) / C)
    ; K = cubic_root(W_max * beta / C) where beta = 0.3 (1 - 0.7)
    ; Fixed point calculation
    mov eax, r14d
    imul eax, CUBIC_BETA_NUM
    xor edx, edx
    div CUBIC_BETA_DEN
    imul eax, CUBIC_C_DEN
    div CUBIC_C_NUM
    mov r14d, eax

    ; K = cubic_root(value)
    call cubic_root
    mov [r13 + cubic_state_t.k], eax

    ; Update last max for fast convergence
    mov [r13 + cubic_state_t.w_last_max], r14d

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; cubic_ack_received — Process ACK receipt
; Input: RDI = tcb_t*, RSI = acked_bytes
; -----------------------------------------------------------------------------
align 64
cubic_ack_received:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi            ; acked_bytes

    mov r13, qword [rbx + tcb_t.cc_state]
    test r13, r13
    jz .done

    mov r14d, [rbx + tcb_t.cwnd]

    ; If in slow start (cwnd < ssthresh), use standard slow start
    cmp r14d, [rbx + tcb_t.ssthresh]
    jl .slow_start

    ; Congestion avoidance: CUBIC window growth
    ; W(t) = C * (t - K)^3 + W_max
    call rdtsc_get_cycles
    sub rax, qword [r13 + cubic_state_t.epoch_start]
    ; Convert cycles to milliseconds (approximate)
    ; Assuming ~3GHz CPU: cycles / 3000 = ms
    mov rcx, 3000
    div rcx
    mov r15d, eax           ; t in ms

    sub r15d, [r13 + cubic_state_t.k]
    ; Cube: (t - K)^3
    imul r15d, r15d
    imul r15d, r15d
    ; Multiply by C
    imul r15d, CUBIC_C_NUM
    div CUBIC_C_DEN
    ; Add W_max
    add r15d, [r13 + cubic_state_t.w_max]

    ; TCP friendliness check
    cmp byte [r13 + cubic_state_t.tcp_friendly], 1
    jz .tcp_friendly
    jmp .set_cwnd

.tcp_friendly:
    ; TCP-friendly calculation: cwnd = cwnd * (1 + 3*beta/(2 - beta)) * RTT / cwnd
    ; Simplified: ensure we don't exceed TCP Reno growth
    ; cwnd_reno = cwnd + acked / cwnd per RTT
    ; For CUBIC, cap at TCP-friendly rate
    ; (implementation simplified)

.set_cwnd:
    cmp r15d, r14d
    cmovg r14d, r15d
    mov dword [rbx + tcb_t.cwnd], r14d
    jmp .done

.slow_start:
    ; Standard slow start: cwnd += acked / cwnd per ACK (roughly +1 MSS per RTT)
    ; cwnd += MSS per ACK
    add dword [rbx + tcb_t.cwnd], r12d
    cmp dword [rbx + tcb_t.cwnd], [rbx + tcb_t.ssthresh]
    jl .done
    mov dword [rbx + tcb_t.cwnd], [rbx + tcb_t.ssthresh]

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; cubic_rtt_update — Update RTT estimate (not used by CUBIC directly)
; -----------------------------------------------------------------------------
align 64
cubic_rtt_update:
    ret

; -----------------------------------------------------------------------------
; cubic_cwnd_get — Get current congestion window
; Input: RDI = tcb_t*
; Output: RAX = cwnd
; -----------------------------------------------------------------------------
align 64
cubic_cwnd_get:
    mov eax, [rdi + tcb_t.cwnd]
    ret

; -----------------------------------------------------------------------------
; cubic_root — Integer cubic root (fixed point)
; Input: EAX = value
; Output: EAX = floor(cuberoot(value))
; -----------------------------------------------------------------------------
align 64
cubic_root:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12d, eax
    test r12d, r12d
    jz .zero

    ; Binary search for integer cubic root
    ; Range: 0 to 2^10 (since max window ~ 1M)
    mov eax, 1
    mov edx, 1024

.binary_search:
    cmp eax, edx
    jge .done
    mov ecx, eax
    add ecx, edx
    shr ecx, 1            ; mid = (low + high) / 2

    mov r8d, ecx
    imul r8d, ecx
    imul r8d, ecx         ; mid^3

    cmp r8d, r12d
    jle .move_low
    mov edx, ecx
    jmp .binary_search

.move_low:
    lea eax, [ecx + 1]
    jmp .binary_search

.done:
    cmp eax, 1
    mov edx, 1
    cmovl eax, edx
    pop r12
    pop rbx
    pop rbp
    ret

.zero:
    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; CUBIC CC Ops Table
; -----------------------------------------------------------------------------
align 64
cubic_ops:
    dq cubic_init_name
    dq cubic_init
    dq cubic_destroy
    dq cubic_cong_event
    dq cubic_ack_received
    dq cubic_rtt_update
    dq cubic_cwnd_get
    dq cubic_ssthresh_get
    dq cubic_set_state

section .data
cubic_init_name: db "cubic", 0

cubic_destroy:
    ret

cubic_ssthresh_get:
    mov eax, [rdi + tcb_t.ssthresh]
    ret

cubic_set_state:
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_CUBIC_ASM
