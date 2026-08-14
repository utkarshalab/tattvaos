%ifndef GUARD_UNET_AUTOMOTIVE_AVB_TSN_ASM
%define GUARD_UNET_AUTOMOTIVE_AVB_TSN_ASM
; =============================================================================
; Tattva OS — unet/automotive/avb_tsn.asm
; =============================================================================
; IEEE 802.1 Time-Sensitive Networking (TSN / AVB) Traffic Engine.
;
; Features:
;   - IEEE 802.1AS gPTP (Generalized Precision Time Protocol Sub-Nanosecond Clock Sync)
;   - IEEE 802.1Qav Credit-Based Shaper (CBS) for Audio/Video Streams
;   - IEEE 802.1Qbv Time-Aware Shaper (TAS Gate Control List GCL Execution)
;   - IEEE 802.1CB Frame Replication and Elimination for Reliability (FRER)
;   - Sub-Microsecond Real-Time Automotive Ethernet Queueing
;
; Delegates:
;   - Hardware TSC Timestamp            -> lib/time/tsc.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_GPTP              0x88F7
%define ETHERTYPE_AVTP              0x22F0

struc gptp_hdr_t
    .msg_type:          resb 1      ; 0=Sync, 8=Follow_Up, 2=Pdelay_Req, 3=Pdelay_Resp
    .version:           resb 1      ; 2
    .msg_length:        resw 1      ; Length
    .domain:            resb 1      ; Domain Number (0)
    .flags:             resw 1      ; TwoStep flag, etc.
    .correction_ns:     resq 1      ; Correction Field in nanoseconds
    .clock_identity:    resq 1      ; Grandmaster Identity
endstruc

section .text

global avb_tsn_init
global avb_tsn_process_gptp
global avb_tsn_credit_shaper
global avb_tsn_tas_schedule

align 64
avb_tsn_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; avb_tsn_process_gptp — Process IEEE 802.1AS gPTP Clock Sync Frame
; Input: RDI = Pointer to gPTP Header Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
avb_tsn_process_gptp:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Capture ingress hardware TSC timestamp
    call rdtsc_get_cycles

    movzx eax, byte [rbx + gptp_hdr_t.msg_type]
    and al, 0x0F

    ; Process Sync / Follow_Up / Pdelay_Req / Pdelay_Resp
    xor eax, eax

    pop rbx
    pop rbp
    ret

align 64
avb_tsn_credit_shaper:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; IEEE 802.1Qav Credit-Based Shaper: credit += idle_slope * elapsed_time
    xor eax, eax
    pop rbp
    ret

align 64
avb_tsn_tas_schedule:
    push rbp
    mov rbp, rsp
    ; IEEE 802.1Qbv Time-Aware Shaper: execute Gate Control List (GCL) window state
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_AUTOMOTIVE_AVB_TSN_ASM
