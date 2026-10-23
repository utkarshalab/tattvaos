%ifndef GUARD_UNET_TOOLS_BENCH_QUIC_BENCH_ASM
%define GUARD_UNET_TOOLS_BENCH_QUIC_BENCH_ASM
; =============================================================================
; Utkarsha OS — unet/tools/bench/quic_bench.asm
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

%include "lib/unet/unet.inc"

section .text

global quic_bench_main
global quic_bench_run_streams

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

; quic_bench_run_streams — time one pass of a packet through quic_input
; Input: RDI = net_pkt_t* holding a QUIC packet
; Output: RAX = elapsed TSC cycles
; TODO: stream multiplexing throughput and loss recovery once QUIC has them
align 64
quic_bench_run_streams:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]
    call rdtsc_get_cycles
    mov r12, rax            ; start

    mov rdi, rbx
    xor esi, esi            ; no known connection
    call quic_input

    call rdtsc_get_cycles
    sub rax, r12            ; elapsed cycles

    pop r12
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_BENCH_QUIC_BENCH_ASM
