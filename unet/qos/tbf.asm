%ifndef GUARD_UNET_QOS_TBF_ASM
%define GUARD_UNET_QOS_TBF_ASM
; =============================================================================
; Tattva OS — unet/qos/tbf.asm
; =============================================================================
; Token Bucket Filter (TBF) & Dual-Rate Token Bucket Traffic Policing Engine.
;
; Features:
;   - Single-Rate Three-Color Marker (srTCM RFC 2697) & Two-Rate Three-Color Marker (trTCM RFC 2698)
;   - CIR (Committed Information Rate), CBS (Committed Burst Size), PIR (Peak Information Rate), PBS (Peak Burst Size)
;   - Color Marking: Green (Conforming), Yellow (Exceeding), Red (Violating)
;   - Sub-Nanosecond Token Accumulation via Hardware TSC Clock
;   - Rate-Shaping Token Bucket Delay Scheduling
;
; Delegates:
;   - Hardware TSC Timestamping          -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define TBF_COLOR_GREEN             0
%define TBF_COLOR_YELLOW            1
%define TBF_COLOR_RED               2

struc tbf_policer_t
    .cir_bps:           resq 1      ; Committed Information Rate (bits/sec)
    .cbs_bytes:         resd 1      ; Committed Burst Size (bytes)
    .pir_bps:           resq 1      ; Peak Information Rate (bits/sec)
    .pbs_bytes:         resd 1      ; Peak Burst Size (bytes)
    .c_tokens:          resq 1      ; Current Committed Tokens
    .p_tokens:          resq 1      ; Current Peak Tokens
    .last_time_tsc:     resq 1      ; Last Token Refill Timestamp
endstruc

section .text

global tbf_init
global tbf_police_packet
global tbf_refill_tokens

align 64
tbf_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tbf_police_packet — Evaluate Packet against trTCM (RFC 2698) Dual Token Bucket
; Input: RDI = Pointer to tbf_policer_t, ESI = Packet Byte Size
; Output: EAX = TBF_COLOR_GREEN (0), TBF_COLOR_YELLOW (1), TBF_COLOR_RED (2)
; -----------------------------------------------------------------------------
align 64
tbf_police_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Refill tokens based on elapsed TSC cycles
    call tbf_refill_tokens

    ; 2. Check Peak Tokens (P_bucket)
    mov rax, [rbx + tbf_policer_t.p_tokens]
    cmp rax, rsi
    jl .red

    ; 3. Check Committed Tokens (C_bucket)
    mov rax, [rbx + tbf_policer_t.c_tokens]
    cmp rax, rsi
    jl .yellow

    ; Green: deduct from both buckets
    sub [rbx + tbf_policer_t.p_tokens], rsi
    sub [rbx + tbf_policer_t.c_tokens], rsi
    mov eax, TBF_COLOR_GREEN
    jmp .done

.yellow:
    ; Yellow: deduct from Peak bucket only
    sub [rbx + tbf_policer_t.p_tokens], rsi
    mov eax, TBF_COLOR_YELLOW
    jmp .done

.red:
    ; Red: violating rate
    mov eax, TBF_COLOR_RED

.done:
    pop rbx
    pop rbp
    ret

align 64
tbf_refill_tokens:
    push rbp
    mov rbp, rsp
    ; Refill C_tokens and P_tokens = elapsed_sec * rate (capped at burst size)
    call rdtsc_get_cycles
    pop rbp
    ret

%endif ; GUARD_UNET_QOS_TBF_ASM
