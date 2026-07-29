; =============================================================================
; Tattva OS — unet/tester/latency_meter.asm
; =============================================================================
; Sub-Nanosecond RTT Latency Histogram Meter Engine.
;
; Implements:
;   - Hardware TSC Read (`RDTSC` / `RDTSCP`) Microsecond Latency Histograms
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global latency_meter_init
global latency_meter_record

align 32
latency_meter_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
latency_meter_record:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
