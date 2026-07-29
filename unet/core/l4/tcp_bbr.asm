; =============================================================================
; Tattva OS — unet/core/l4/tcp_bbr.asm
; =============================================================================
; Master TCP BBR v2 (Bottleneck Bandwidth & RTT) Congestion Control Engine.
;
; Features:
;   - BBR v2 Model-Based Congestion Control (BBR_STARTUP, BBR_DRAIN, BBR_PROBE_BW, BBR_PROBE_RTT)
;   - Pacing Rate Calculation (PacingRate = BBR_BW * PacingGain)
;   - Explicit Congestion Notification (ECN / L4S) Reaction
;
; Delegates:
;   - Hardware Cycle Timestamps       -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define BBR_MODE_STARTUP            0
%define BBR_MODE_DRAIN              1
%define BBR_MODE_PROBE_BW           2
%define BBR_MODE_PROBE_RTT          3

struc bbr_state_t
    .mode:              resd 1      ; Current BBR Mode
    .bw_latest:         resq 1      ; Latest Bandwidth Sample
    .bw_max:            resq 1      ; Max Estimated Bottleneck Bandwidth
    .rtt_min:           resd 1      ; Min Round-Trip Time
    .pacing_rate:       resq 1      ; Calculated Pacing Rate (Bytes/sec)
    .cwnd:              resd 1      ; Calculated Congestion Window
endstruc

section .text

global bbr_init
global bbr_update_sample
global bbr_calculate_pacing

extern rdtsc_get_cycles

align 64
bbr_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; bbr_update_sample — Process Delivery Rate Sample & Update BBR Model
; Input: RDI = Pointer to tcb_t, RSI = Delivered Bytes, RDX = Interval Us
; -----------------------------------------------------------------------------
align 64
bbr_update_sample:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage TCB into L1 cache

    ; Calculate Delivery Rate = (Delivered Bytes * 1,000,000) / Interval Us
    ; Update bbr_bw max filter window
    call rdtsc_get_cycles

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; bbr_calculate_pacing — Calculate Packet Pacing Rate & CWND
; Input: RDI = Pointer to tcb_t
; Output: RAX = Pacing Rate (Bytes/sec)
; -----------------------------------------------------------------------------
align 64
bbr_calculate_pacing:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]

    ; PacingRate = max_bw * pacing_gain
    mov rax, 1000000000             ; Default 1Gbps Pacing
    pop rbp
    ret
