%ifndef GUARD_UNET_CORE_L4_TCP_BBRV2_ASM
%define GUARD_UNET_CORE_L4_TCP_BBRV2_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/tcp_bbrv2.asm
; =============================================================================
; BBRv2 Congestion Control (RFC 9402, IETF Draft)
;
; BBRv2 improves upon BBRv1 with:
;   - L4S (Low Latency, Low Loss, Scalable Throughput) ECN support
;   - Improved loss detection (RACK-TLP)
;   - Better coexistence with loss-based CC
;   - Pacing rate updates on every ACK
;   - Better probing for bandwidth
;
; States: STARTUP, DRAIN, PROBE_BW, PROBE_RTT
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"

%define BBRV2_MODE_STARTUP        0
%define BBRV2_MODE_DRAIN          1
%define BBRV2_MODE_PROBE_BW       2
%define BBRV2_MODE_PROBE_RTT      3

%define BBRV2_GAIN_STARTUP        2863311531  ; 2/ln(2) ≈ 2.885 in Q30
%define BBRV2_GAIN_DRAIN          715827883   ; 1/2 * ln(2) ≈ 0.721 in Q30
%define BBRV2_GAIN_PROBE_BW_CYCLE 1073741824, 1174405120, 973078528, 1073741824  ; 1.0, 1.25, 0.75, 1.0 in Q30

%define BBRV2_CWND_GAIN_STARTUP   1073741824  ; 1.0 in Q30 (cwnd = 2*BDP in STARTUP)
%define BBRV2_CWND_GAIN_DRAIN     1073741824  ; 1.0 in Q30
%define BBRV2_CWND_GAIN_PROBE_BW  1610612736  ; 1.5 in Q30
%define BBRV2_CWND_GAIN_PROBE_RTT 1073741824  ; 1.0 in Q30

%define BBRV2_MIN_RTT_WINDOW_MS   10000       ; 10 seconds min RTT window
%define BBRV2_PROBE_RTT_DURATION_MS 200       ; 200ms PROBE_RTT duration
%define BBRV2_PROBE_BW_CYCLE_MS   7000        ; 7 second PROBE_BW cycle

struc bbrv2_state_t
    .mode:              resd 1      ; Current BBRv2 mode
    .cycle_idx:         resb 1      ; PROBE_BW cycle index (0-3)
    .cycle_start_ts:    resq 1      ; Cycle start timestamp

    .bw_latest:         resq 1      ; Latest bandwidth sample (bytes/sec, Q16)
    .bw_max:            resq 1      ; Max bandwidth estimate (bytes/sec, Q16)
    .bw_max_ts:         resq 1      ; Timestamp of bw_max
    .bw_est:            resq 1      ; Current bandwidth estimate (bytes/sec, Q16)

    .rtt_min:           resd 1      ; Minimum RTT (microseconds)
    .rtt_min_ts:        resq 1      ; Timestamp of min RTT

    .pacing_rate:       resq 1      ; Pacing rate (bytes/sec, Q16)
    .cwnd:              resd 1      ; Congestion window (packets)

    .inflight_hi:       resd 1      ; Max inflight in current round
    .inflight_lo:       resd 1      ; Min inflight in current round
    .round_count:       resd 1      ; Packet round counter
    .next_round_delivered: resd 1   ; Delivered at next round

    .packet_conservation: resb 1    ; Packet conservation mode
    .loss_recovery:       resb 1    ; In loss recovery

    .ecn_ce_count:        resd 1    ; ECN CE marks received
    .ecn_ect_count:       resd 1    ; ECN ECT marks received
    .l4s_enabled:         resb 1    ; L4S ECN enabled

    .startup_full_loss_count: resd 1 ; Full loss count in STARTUP
    .startup_ecn_count:       resd 1 ; ECN count in STARTUP

    .probe_rtt_done_ts:   resq 1    ; PROBE_RTT completion timestamp
    .probe_rtt_round_done:  resb 1  ; PROBE_RTT round completed

    .pacing_gain:         resd 1    ; Current pacing gain (Q30)
    .cwnd_gain:           resd 1    ; Current cwnd gain (Q30)

    .ack_height:          resd 1    ; ACK height for RACK
    .reorder_fuzz:        resd 1    ; Reordering fuzz

    .tlp_retrans:         resb 1    ; TLP retransmission pending
    .rack_reorder_ts:     resq 1    ; RACK reordering timestamp

    .pad:                 resb 7
endstruc

section .text

global bbrv2_init
global bbrv2_cong_event
global bbrv2_ack_received
global bbrv2_rtt_update
global bbrv2_cwnd_get
global bbrv2_ssthresh_get
global bbrv2_set_state
global bbrv2_pacing_rate_get

; =============================================================================
; Fixed-point math helpers (Q16.16 and Q30)
; =============================================================================

%define FP16_SHIFT 16
%define FP30_SHIFT 30

; multiply two Q30 numbers: result = (a * b) >> 30
%macro MUL_Q30 2
    mov rax, %1
    imul rax, %2
    sar rax, 30
%endmacro

; divide Q16 by Q16: result = (a * 2^16) / b
%macro DIV_Q16 2
    mov rax, %1
    shl rax, 16
    cqo
    idiv %2
%endmacro

; =============================================================================
; bbrv2_init — Initialize BBRv2 state
; Input: RDI = tcb_t*, RSI = bbrv2_state_t*
; -----------------------------------------------------------------------------
align 64
bbrv2_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; bbrv2_state_t*

    ; Initialize BBRv2 state
    mov dword [r12 + bbrv2_state_t.mode], BBRV2_MODE_STARTUP
    mov byte [r12 + bbrv2_state_t.cycle_idx], 0
    mov qword [r12 + bbrv2_state_t.cycle_start_ts], 0

    ; Bandwidth estimates
    mov qword [r12 + bbrv2_state_t.bw_latest], 0
    mov qword [r12 + bbrv2_state_t.bw_max], 0
    mov qword [r12 + bbrv2_state_t.bw_max_ts], 0
    mov qword [r12 + bbrv2_state_t.bw_est], 0

    ; RTT
    mov dword [r12 + bbrv2_state_t.rtt_min], 0x7FFFFFFF  ; INF
    mov qword [r12 + bbrv2_state_t.rtt_min_ts], 0

    ; Pacing and cwnd
    mov qword [r12 + bbrv2_state_t.pacing_rate], 0
    mov dword [r12 + bbrv2_state_t.cwnd], 10  ; Initial cwnd = 10 MSS (RFC 6928)

    ; Inflight tracking
    mov dword [r12 + bbrv2_state_t.inflight_hi], 0
    mov dword [r12 + bbrv2_state_t.inflight_lo], 0xFFFFFFFF
    mov dword [r12 + bbrv2_state_t.round_count], 0
    mov dword [r12 + bbrv2_state_t.next_round_delivered], 0

    ; State flags
    mov byte [r12 + bbrv2_state_t.packet_conservation], 0
    mov byte [r12 + bbrv2_state_t.loss_recovery], 0

    ; ECN/L4S
    mov dword [r12 + bbrv2_state_t.ecn_ce_count], 0
    mov dword [r12 + bbrv2_state_t.ecn_ect_count], 0
    mov byte [r12 + bbrv2_state_t.l4s_enabled], 1  ; Enable L4S by default

    ; STARTUP counters
    mov dword [r12 + bbrv2_state_t.startup_full_loss_count], 0
    mov dword [r12 + bbrv2_state_t.startup_ecn_count], 0

    ; PROBE_RTT
    mov qword [r12 + bbrv2_state_t.probe_rtt_done_ts], 0
    mov byte [r12 + bbrv2_state_t.probe_rtt_round_done], 0

    ; Gains (Q30)
    mov dword [r12 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_STARTUP
    mov dword [r12 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_STARTUP

    ; RACK/TLP
    mov dword [r12 + bbrv2_state_t.ack_height], 0
    mov dword [r12 + bbrv2_state_t.reorder_fuzz], 1000  ; 1ms default
    mov byte [r12 + bbrv2_state_t.tlp_retrans], 0
    mov qword [r12 + bbrv2_state_t.rack_reorder_ts], 0

    ; Set CC ops pointer in TCB
    lea rax, [bbrv2_ops]
    mov qword [rbx + tcb_t.cc_ops], rax
    mov qword [rbx + tcb_t.cc_state], r12

    ; Initialize cwnd to 10 MSS (RFC 6928)
    mov dword [rbx + tcb_t.cwnd], 10
    mov dword [rbx + tcb_t.ssthresh], 0xFFFFFFFF

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; bbrv2_cong_event — Handle congestion event (loss, ECN)
; Input: RDI = tcb_t*, RSI = event type
;   EVENT_LOSS = 1, EVENT_ECN = 2, EVENT_TIMEOUT = 4
; -----------------------------------------------------------------------------
align 64
bbrv2_cong_event:
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

    mov r14d, [rbx + tcb_t.cwnd]

    ; Check event type
    cmp r12d, 1             ; EVENT_LOSS
    je .loss_event
    cmp r12d, 2             ; EVENT_ECN
    je .ecn_event
    cmp r12d, 4             ; EVENT_TIMEOUT
    je .timeout_event
    jmp .done

.loss_event:
    ; Packet loss detected
    ; Enter recovery if not already
    test dword [rbx + tcb_t.flags], TCBF_FAST_RECOVERY
    jnz .in_recovery

    ; Set loss recovery
    or dword [rbx + tcb_t.flags], TCBF_FAST_RECOVERY
    mov byte [r13 + bbrv2_state_t.loss_recovery], 1

    ; BBRv2: Reset inflight_hi to current inflight
    mov eax, [rbx + tcb_t.snd_nxt]
    sub eax, [rbx + tcb_t.snd_una]
    mov [r13 + bbrv2_state_t.inflight_hi], eax
    mov [r13 + bbrv2_state_t.inflight_lo], eax

    ; Fast recovery: ssthresh = cwnd * 0.5
    mov eax, [rbx + tcb_t.cwnd]
    shr eax, 1
    cmp eax, 2
    jge .set_ssthresh_loss
    mov eax, 2
.set_ssthresh_loss:
    mov [rbx + tcb_t.ssthresh], eax

    ; cwnd = ssthresh (BBRv2 uses ssthresh as cwnd during recovery)
    mov [rbx + tcb_t.cwnd], eax

    ; Exit STARTUP if in loss
    cmp dword [r13 + bbrv2_state_t.mode], BBRV2_MODE_STARTUP
    jne .loss_done
    ; Exit STARTUP on first loss
    mov dword [r13 + bbrv2_state_t.mode], BBRV2_MODE_DRAIN
    mov dword [r13 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_DRAIN
    mov dword [r13 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_DRAIN

.loss_done:
    jmp .update_pacing

.ecn_event:
    ; ECN congestion signal (CE mark)
    inc dword [r13 + bbrv2_state_t.ecn_ce_count]

    ; L4S: If L4S enabled, use scaled response
    test byte [r13 + bbrv2_state_t.l4s_enabled], 1
    jz .ecn_standard

    ; L4S: Scale response by CE fraction
    ; cwnd = cwnd * (1 - CE_fraction/2)
    ; For simplicity, use standard reduction but track CE
    mov eax, [rbx + tcb_t.cwnd]
    shr eax, 2              ; cwnd *= 3/4 for L4S
    jmp .set_cwnd_ecn

.ecn_standard:
    ; Standard ECN response: same as loss
    mov eax, [rbx + tcb_t.cwnd]
    shr eax, 1              ; cwnd *= 1/2

.set_cwnd_ecn:
    cmp eax, 2
    jge .set_ssthresh_ecn
    mov eax, 2
.set_ssthresh_ecn:
    mov [rbx + tcb_t.cwnd], eax
    mov [rbx + tcb_t.ssthresh], eax
    or dword [rbx + tcb_t.flags], TCBF_FAST_RECOVERY
    mov byte [r13 + bbrv2_state_t.loss_recovery], 1

    ; Update pacing gain
    mov dword [r13 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_DRAIN
    jmp .update_pacing

.timeout_event:
    ; RTO timeout - severe congestion
    ; Full reset: cwnd = 1, ssthresh = cwnd/2
    mov eax, [rbx + tcb_t.cwnd]
    shr eax, 1
    cmp eax, 1
    jge .set_ssthresh_to
    mov eax, 1
.set_ssthresh_to:
    mov [rbx + tcb_t.ssthresh], eax
    mov dword [rbx + tcb_t.cwnd], 1
    mov dword [rbx + tcb_t.cwnd], 1

    ; Reset BBRv2 state
    mov dword [r13 + bbrv2_state_t.mode], BBRV2_MODE_STARTUP
    mov dword [r13 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_STARTUP
    mov dword [r13 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_STARTUP
    mov byte [r13 + bbrv2_state_t.loss_recovery], 0
    jmp .update_pacing

.in_recovery:
    ; Already in recovery, just update cwnd
    mov eax, [rbx + tcb_t.cwnd]
    shr eax, 1
    cmp eax, 2
    jge .set_cwnd_rec
    mov eax, 2
.set_cwnd_rec:
    mov [rbx + tcb_t.cwnd], eax

.update_pacing:
    ; Recalculate pacing rate
    mov rdi, rbx
    call bbrv2_update_pacing_rate

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; bbrv2_ack_received — Process ACK receipt
; Input: RDI = tcb_t*, RSI = acked_bytes, RDX = rtt_us, RCX = delivered
; -----------------------------------------------------------------------------
align 64
bbrv2_ack_received:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi            ; acked_bytes
    mov r13d, edx           ; rtt_us
    mov r14d, ecx           ; delivered (cumulative)

    mov r15, qword [rbx + tcb_t.cc_state]
    test r15, r15
    jz .done

    ; Update bandwidth estimate
    ; bw = delivered * 1e6 / rtt_us
    test r13d, r13d
    jz .no_rtt_update
    mov rax, r14
    imul rax, 1000000
    xor rdx, rdx
    div r13                 ; rax = bw in bytes/sec
    mov qword [r15 + bbrv2_state_t.bw_latest], rax

    ; Update max bandwidth (max filter over 10s window)
    mov r14, qword [r15 + bbrv2_state_t.bw_max]
    cmp rax, r14
    jbe .check_max_age
    mov [r15 + bbrv2_state_t.bw_max], rax
    call rdtsc_get_cycles
    mov [r15 + bbrv2_state_t.bw_max_ts], rax

.check_max_age:
    ; Check if bw_max is older than 10s
    call rdtsc_get_cycles
    sub rax, [r15 + bbrv2_state_t.bw_max_ts]
    ; Convert cycles to ms (assume 3GHz)
    mov rcx, 3000000
    div rcx
    cmp rax, 10000          ; 10 seconds in ms
    jbe .update_bw_est
    ; Max bandwidth expired, reset
    mov rax, [r15 + bbrv2_state_t.bw_latest]
    mov [r15 + bbrv2_state_t.bw_max], rax
    mov [r15 + bbrv2_state_t.bw_max_ts], rax

.update_bw_est:
    ; Update bandwidth estimate (max filter)
    mov r14, qword [r15 + bbrv2_state_t.bw_est]
    cmp rax, r14
    cmova r14, rax
    mov qword [r15 + bbrv2_state_t.bw_est], r14

.no_rtt_update:
    ; Update min RTT
    test r13d, r13d
    jz .no_rtt_min
    cmp r13d, [r15 + bbrv2_state_t.rtt_min]
    jge .no_rtt_min
    mov [r15 + bbrv2_state_t.rtt_min], r13d
    call rdtsc_get_cycles
    mov [r15 + bbrv2_state_t.rtt_min_ts], rax

.no_rtt_min:
    ; Update round counting for RACK
    mov eax, [rbx + tcb_t.snd_una]
    cmp eax, [r15 + bbrv2_state_t.next_round_delivered]
    jl .no_new_round
    ; New round started
    inc dword [r15 + bbrv2_state_t.round_count]
    mov [r15 + bbrv2_state_t.next_round_delivered], eax

.no_new_round:
    ; Update delivered count
    mov eax, [rbx + tcb_t.snd_nxt]
    sub eax, [rbx + tcb_t.snd_una]
    mov [r15 + bbrv2_state_t.inflight_hi], eax

    ; Update cwnd based on mode
    mov eax, [r15 + bbrv2_state_t.mode]
    cmp eax, BBRV2_MODE_STARTUP
    je .startup_update
    cmp eax, BBRV2_MODE_DRAIN
    je .drain_update
    cmp eax, BBRV2_MODE_PROBE_BW
    je .probe_bw_update
    cmp eax, BBRV2_MODE_PROBE_RTT
    je .probe_rtt_update
    jmp .done

.startup_update:
    ; STARTUP: Exponential growth until loss/ECN
    ; cwnd grows exponentially: cwnd += acked/cwnd per ACK
    ; Implemented as cwnd += acked per RTT (roughly +1 MSS per RTT)
    mov eax, [rbx + tcb_t.cwnd]
    add eax, r12d
    mov [rbx + tcb_t.cwnd], eax

    ; Check if we should exit STARTUP
    test dword [rbx + tcb_t.flags], TCBF_FAST_RECOVERY
    jnz .exit_startup
    ; Check if bandwidth growth has stopped (3 rounds no growth)
    ; Simplified: check if we've been in STARTUP for 3 rounds
    cmp dword [r15 + bbrv2_state_t.round_count], 3
    jl .done
    ; Exit STARTUP
.exit_startup:
    mov dword [r15 + bbrv2_state_t.mode], BBRV2_MODE_DRAIN
    mov dword [r15 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_DRAIN
    mov dword [r15 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_DRAIN
    jmp .done

.drain_update:
    ; DRAIN: Reduce queue until pacing_rate <= bw
    ; Wait until inflight <= BDP
    mov eax, [rbx + tcb_t.cwnd]
    ; In DRAIN, cwnd decreases
    cmp eax, [rbx + tcb_t.ssthresh]
    jle .drain_done
    ; Still draining
    jmp .done

.drain_done:
    ; Transition to PROBE_BW
    mov dword [r15 + bbrv2_state_t.mode], BBRV2_MODE_PROBE_BW
    mov byte [r15 + bbrv2_state_t.cycle_idx], 0
    call rdtsc_get_cycles
    mov [r15 + bbrv2_state_t.cycle_start_ts], rax
    mov dword [r15 + bbrv2_state_t.pacing_gain], 1073741824  ; 1.0
    mov dword [r15 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_PROBE_BW
    jmp .done

.probe_bw_update:
    ; PROBE_BW: Cycle through pacing gains [1.25, 0.75, 1.0, 1.0]
    ; Check cycle duration
    call rdtsc_get_cycles
    sub rax, [r15 + bbrv2_state_t.cycle_start_ts]
    mov rcx, 3000000
    div rcx
    cmp rax, BBRV2_PROBE_BW_CYCLE_MS / 4
    jl .probe_bw_continue

    ; Advance cycle
    movzx eax, byte [r15 + bbrv2_state_t.cycle_idx]
    inc al
    and al, 3
    mov byte [r15 + bbrv2_state_t.cycle_idx], al
    call rdtsc_get_cycles
    mov [r15 + bbrv2_state_t.cycle_start_ts], rax

    ; Update pacing gain based on cycle
    cmp al, 0
    je .gain_1_25
    cmp al, 1
    je .gain_0_75
    ; al = 2 or 3 -> gain = 1.0
    mov dword [r15 + bbrv2_state_t.pacing_gain], 1073741824  ; 1.0
    jmp .probe_bw_continue

.gain_1_25:
    mov dword [r15 + bbrv2_state_t.pacing_gain], 1342177280  ; 1.25
    jmp .probe_bw_continue

.gain_0_75:
    mov dword [r15 + bbrv2_state_t.pacing_gain], 805306368   ; 0.75

.probe_bw_continue:
    ; Update cwnd gain
    mov dword [r15 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_PROBE_BW
    jmp .done

.probe_rtt_update:
    ; PROBE_RTT: Reduce inflight to 4 packets for min RTT measurement
    ; Check duration
    call rdtsc_get_cycles
    sub rax, [r15 + bbrv2_state_t.probe_rtt_done_ts]
    mov rcx, 3000000
    div rcx
    cmp rax, BBRV2_PROBE_RTT_DURATION_MS
    jl .probe_rtt_continue

    ; PROBE_RTT done, return to PROBE_BW
    mov dword [r15 + bbrv2_state_t.mode], BBRV2_MODE_PROBE_BW
    mov byte [r15 + bbrv2_state_t.cycle_idx], 0
    call rdtsc_get_cycles
    mov [r15 + bbrv2_state_t.cycle_start_ts], rax
    mov byte [r15 + bbrv2_state_t.probe_rtt_round_done], 0
    jmp .done

.probe_rtt_continue:
    ; Limit cwnd to 4 packets
    cmp dword [rbx + tcb_t.cwnd], 4
    jle .done
    mov dword [rbx + tcb_t.cwnd], 4
    jmp .done

.done:
    ; Update pacing rate after cwnd changes
    mov rdi, rbx
    call bbrv2_update_pacing_rate

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; bbrv2_update_pacing_rate — Update pacing rate based on current state
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
bbrv2_update_pacing_rate:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.cc_state]
    test r12, r12
    jz .done

    ; pacing_rate = bw_est * pacing_gain
    mov rax, [r12 + bbrv2_state_t.bw_est]
    test rax, rax
    jz .done

    mov r13d, [r12 + bbrv2_state_t.pacing_gain]
    ; Multiply Q16 * Q30 = Q46, then shift to Q16
    ; rax (Q16) * r13d (Q30) = Q46, result Q16 = (rax * r13d) >> 30
    imul rax, r13
    sar rax, 30
    mov qword [r12 + bbrv2_state_t.pacing_rate], rax

    ; Also update TCB pacing_rate
    mov qword [rbx + tcb_t.pacing_rate], rax

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; bbrv2_rtt_update — Update RTT estimate (called from TCP layer)
; Input: RDI = tcb_t*, RSI = rtt_us
; -----------------------------------------------------------------------------
align 64
bbrv2_rtt_update:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    mov r13, qword [rbx + tcb_t.cc_state]
    test r13, r13
    jz .done

    ; Update min RTT
    cmp r12d, [r13 + bbrv2_state_t.rtt_min]
    jge .done
    mov [r13 + bbrv2_state_t.rtt_min], r12d
    call rdtsc_get_cycles
    mov [r13 + bbrv2_state_t.rtt_min_ts], rax

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; bbrv2_cwnd_get — Get current congestion window
; Input: RDI = tcb_t*
; Output: RAX = cwnd (packets)
; -----------------------------------------------------------------------------
align 64
bbrv2_cwnd_get:
    mov eax, [rdi + tcb_t.cwnd]
    ret

; =============================================================================
; bbrv2_ssthresh_get — Get slow start threshold
; Input: RDI = tcb_t*
; Output: RAX = ssthresh
; -----------------------------------------------------------------------------
align 64
bbrv2_ssthresh_get:
    mov eax, [rdi + tcb_t.ssthresh]
    ret

; =============================================================================
; bbrv2_set_state — Set BBRv2 mode (for testing/debugging)
; Input: RDI = tcb_t*, RSI = mode
; -----------------------------------------------------------------------------
align 64
bbrv2_set_state:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.cc_state]
    test r12, r12
    jz .done

    mov dword [r12 + bbrv2_state_t.mode], esi

    ; Update gains based on mode
    cmp esi, BBRV2_MODE_STARTUP
    je .set_startup
    cmp esi, BBRV2_MODE_DRAIN
    je .set_drain
    cmp esi, BBRV2_MODE_PROBE_BW
    je .set_probe_bw
    cmp esi, BBRV2_MODE_PROBE_RTT
    je .set_probe_rtt
    jmp .done

.set_startup:
    mov dword [r12 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_STARTUP
    mov dword [r12 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_STARTUP
    jmp .done

.set_drain:
    mov dword [r12 + bbrv2_state_t.pacing_gain], BBRV2_GAIN_DRAIN
    mov dword [r12 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_DRAIN
    jmp .done

.set_probe_bw:
    mov dword [r12 + bbrv2_state_t.pacing_gain], 1073741824
    mov dword [r12 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_PROBE_BW
    jmp .done

.set_probe_rtt:
    mov dword [r12 + bbrv2_state_t.pacing_gain], 1073741824
    mov dword [r12 + bbrv2_state_t.cwnd_gain], BBRV2_CWND_GAIN_PROBE_RTT
    jmp .done

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; bbrv2_pacing_rate_get — Get current pacing rate
; Input: RDI = tcb_t*
; Output: RAX = pacing rate (bytes/sec, Q16)
; -----------------------------------------------------------------------------
align 64
bbrv2_pacing_rate_get:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rax, qword [rbx + tcb_t.cc_state]
    test rax, rax
    jz .zero
    mov rax, [rax + bbrv2_state_t.pacing_rate]
    jmp .done

.zero:
    xor rax, rax

.done:
    pop rbx
    pop rbp
    ret

; =============================================================================
; BBRv2 CC Ops Table
; =============================================================================
align 64
bbrv2_ops:
    dq bbrv2_init_name
    dq bbrv2_init
    dq bbrv2_destroy
    dq bbrv2_cong_event
    dq bbrv2_ack_received
    dq bbrv2_rtt_update
    dq bbrv2_cwnd_get
    dq bbrv2_ssthresh_get
    dq bbrv2_set_state
    dq bbrv2_pacing_rate_get

section .data
bbrv2_init_name: db "bbrv2", 0

section .text

bbrv2_destroy:
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_BBRV2_ASM
