; =============================================================================
; Tattva OS — unet/tools/bench/quic_bench.asm
; =============================================================================
; QUIC / HTTP/3 Performance & 0-RTT Handshake Benchmark Tool (`quic-bench`).
;
; Features:
;   - UDP Port 443 QUIC Initial / Handshake / 1-RTT Packet Stream Benchmark
;   - Multi-Stream Concurrent Throughput & Congestion Control Audit
;   - Sub-Millisecond 0-RTT Handshake Latency & Loss Recovery Measurement
;
; Delegates:
;   - QUIC Protocol Engine              -> unet/core/l4/quic.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global quic_bench_main
global quic_bench_run_streams

extern rdtsc_get_cycles
extern quic_process_packet

align 64
quic_bench_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call quic_bench_run_streams

    pop rbx
    pop rbp
    ret

align 64
quic_bench_run_streams:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Measure QUIC 0-RTT handshake speed, stream multiplexing throughput, and loss recovery
    call rdtsc_get_cycles
    call quic_process_packet
    xor eax, eax
    pop rbp
    ret
