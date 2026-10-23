%ifndef GUARD_UNET_CORE_L4_TCP_CUBIC_ASM
%define GUARD_UNET_CORE_L4_TCP_CUBIC_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/tcp_cubic.asm
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

%include "lib/unet/unet.inc"

%define CUBIC_C_NUM          4194304   ; C = 0.4 * 2^24 (fixed point)
%define CUBIC_C_DEN          10485760
%define CUBIC_BETA_NUM       7
%define CUBIC_BETA_DEN       10
%define CUBIC_HZ             1000       ; 1kHz tick rate
%define CUBIC_TCP_FRIENDLINESS 1
%define CUBIC_K_SCALE        750000000  ; (1 - beta) / C * 10^9, for K in ms
%define CUBIC_MAX_DELTA_MS   100000     ; clamp |t - K| so D^3 fits in 64 bits

struc cubic_state_t
    .w_max:           resd 1      ; Max window before last reduction
    .w_last_max:      resd 1      ; Last max window (for fast convergence)
    .k:               resd 1      ; Time to reach W_max (ms)
    .origin_point:    resd 1      ; Window at start of current epoch
    .epoch_start:     resq 1      ; mono_get_nanos at start of epoch (0 = none)
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
;
; Windows are in bytes, like the rest of tcb_t (cwnd, ssthresh); CUBIC's own
; W_max / origin_point are in segments of tcb_t.mss.
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

    ; Initial window: 10 segments (RFC 6928)
    mov rdi, rbx
    call cubic_mss
    imul eax, 10
    mov dword [rbx + tcb_t.cwnd], eax
    mov dword [rbx + tcb_t.ssthresh], 0xFFFFFFFF

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; cubic_cong_event — Handle congestion event (loss, ECN)   [RFC 8312 4.5-4.6]
; Input: RDI = tcb_t*, RSI = event type
; -----------------------------------------------------------------------------
align 64
cubic_cong_event:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12d, esi           ; event type

    mov r13, qword [rbx + tcb_t.cc_state]
    test r13, r13
    jz .done

    ; R14D = cwnd in segments
    mov rdi, rbx
    call cubic_mss
    mov ecx, eax
    mov eax, [rbx + tcb_t.cwnd]
    xor edx, edx
    div ecx
    mov r14d, eax

    ; Fast convergence: losing below the last maximum means capacity shrank,
    ; so remember a W_max lower than this window: cwnd * (1 + beta) / 2
    mov eax, r14d
    cmp r14d, [r13 + cubic_state_t.w_last_max]
    jae .no_fast_conv
    imul eax, CUBIC_BETA_DEN + CUBIC_BETA_NUM
    mov ecx, 2 * CUBIC_BETA_DEN
    xor edx, edx
    div ecx
.no_fast_conv:
    mov [r13 + cubic_state_t.w_max], eax
    mov [r13 + cubic_state_t.w_last_max], r14d
    mov [r13 + cubic_state_t.origin_point], eax

    ; Multiplicative decrease: cwnd = max(cwnd * beta, 2 * MSS)
    mov eax, [rbx + tcb_t.cwnd]
    imul rax, rax, CUBIC_BETA_NUM
    mov ecx, CUBIC_BETA_DEN
    xor edx, edx
    div rcx
    mov ecx, eax            ; ECX = reduced window
    mov rdi, rbx
    call cubic_mss
    shl eax, 1              ; 2 * MSS
    cmp ecx, eax
    cmovb ecx, eax
    mov [rbx + tcb_t.cwnd], ecx
    mov [rbx + tcb_t.ssthresh], ecx

    ; K = cbrt(W_max * (1 - beta) / C) seconds. In milliseconds, with
    ; (1 - beta) / C = 0.3 / 0.4: K_ms = cbrt(W_max * 0.75 * 10^9)
    mov eax, [r13 + cubic_state_t.w_max]
    imul rax, rax, CUBIC_K_SCALE
    call cubic_root
    mov [r13 + cubic_state_t.k], eax

    ; New epoch starts now
    call mono_get_nanos
    mov [r13 + cubic_state_t.epoch_start], rax

.done:
    pop r14
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
    push r15
    sub rsp, 8

    mov rbx, rdi
    mov r12, rsi            ; acked_bytes

    mov r13, qword [rbx + tcb_t.cc_state]
    test r13, r13
    jz .done

    mov rdi, rbx
    call cubic_mss
    mov r15d, eax           ; R15D = MSS
    mov r14d, [rbx + tcb_t.cwnd]

    cmp r14d, [rbx + tcb_t.ssthresh]
    jae .congestion_avoidance

    ; Slow start: cwnd += min(acked, MSS) per ACK (RFC 5681)
    mov eax, r12d
    cmp eax, r15d
    cmova eax, r15d
    add r14d, eax
    jc .saturate
    mov [rbx + tcb_t.cwnd], r14d
    jmp .done
.saturate:
    mov dword [rbx + tcb_t.cwnd], 0xFFFFFFFF
    jmp .done

.congestion_avoidance:
    cmp qword [r13 + cubic_state_t.epoch_start], 0
    jne .have_epoch
    ; First ACK in congestion avoidance with no loss yet: start the epoch
    ; at the current window, which is then W_max with K = 0
    mov eax, r14d
    xor edx, edx
    div r15d
    mov [r13 + cubic_state_t.w_max], eax
    mov [r13 + cubic_state_t.origin_point], eax
    mov dword [r13 + cubic_state_t.k], 0
    call mono_get_nanos
    mov [r13 + cubic_state_t.epoch_start], rax
    jmp .done

.have_epoch:
    ; t = time since the epoch, in ms; D = t - K, clamped to +-100 s
    call mono_get_nanos
    sub rax, [r13 + cubic_state_t.epoch_start]
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov ecx, [r13 + cubic_state_t.k]
    sub rax, rcx
    mov rcx, CUBIC_MAX_DELTA_MS
    cmp rax, rcx
    cmovg rax, rcx
    neg rcx
    cmp rax, rcx
    cmovl rax, rcx

    ; W(t) = C * D^3 + W_max segments, C = 0.4 per s^3 = 4 / 10^10 per ms^3
    mov rcx, rax
    imul rax, rcx
    imul rax, rcx           ; D^3 (fits: |D| <= 10^5)
    imul rax, rax, 4
    cqo
    mov rcx, 10000000000
    idiv rcx
    mov ecx, [r13 + cubic_state_t.w_max]
    add rax, rcx            ; RAX = target, segments
    jle .done

    ; Target in bytes; grow toward it by (target - cwnd) / cwnd per ACK,
    ; at most one MSS per ACK
    imul rax, r15
    mov ecx, r14d
    sub rax, rcx
    jbe .done               ; already at or above the target
    imul rax, r15
    xor edx, edx
    div rcx                 ; (target - cwnd) * MSS / cwnd
    test eax, eax
    jnz .have_inc
    inc eax
.have_inc:
    cmp eax, r15d
    cmova eax, r15d
    add r14d, eax
    jc .saturate
    mov [rbx + tcb_t.cwnd], r14d

.done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; cubic_mss — MSS of a connection, 1460 if not negotiated yet
; Input: RDI = tcb_t*
; Output: EAX = MSS
; -----------------------------------------------------------------------------
align 16
cubic_mss:
    mov eax, [rdi + tcb_t.mss]
    test eax, eax
    jnz .ok
    mov eax, 1460
.ok:
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
; cubic_root — Integer cube root
; Input: RAX = value (unsigned, below 2^63)
; Output: EAX = floor(cbrt(value))
; Clobbers: RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
align 64
cubic_root:
    mov r9, rax             ; value
    xor eax, eax            ; low  = 0 (answer is in [low, high))
    mov edx, 1 << 21        ; high = 2^21 > cbrt(2^63)

.binary_search:
    lea ecx, [rax + 1]
    cmp ecx, edx
    jae .done               ; high - low == 1: low is the answer
    lea ecx, [rax + rdx]
    shr ecx, 1              ; mid

    mov r8d, ecx
    imul r8, r8
    imul r8, rcx            ; mid^3, below 2^63
    cmp r8, r9
    ja .too_big
    mov eax, ecx            ; mid^3 <= value: low = mid
    jmp .binary_search
.too_big:
    mov edx, ecx            ; high = mid
    jmp .binary_search

.done:
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

section .text

cubic_destroy:
    ret

cubic_ssthresh_get:
    mov eax, [rdi + tcb_t.ssthresh]
    ret

cubic_set_state:
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_CUBIC_ASM
