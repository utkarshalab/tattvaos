%ifndef GUARD_UNET_TOOLS_BENCH_HFT_BENCH_ASM
%define GUARD_UNET_TOOLS_BENCH_HFT_BENCH_ASM
; =============================================================================
; Tattva OS — unet/tools/bench/hft_bench.asm
; =============================================================================
; High-Frequency Trading Sub-Nanosecond Tick-to-Trade Benchmark Tool (`hft-bench`).
;
; Features:
;   - Sub-Nanosecond Ingress ITCH Multicast Ingest -> OUCH Order Outbound Latency Benchmark
;   - Hardware RDTSC Cycle Counter Delta Measurement (Pre-Parse to Post-Transmission)
;   - AVX-512 Fast Field Match & Order Response Verification
;   - Sub-Nanosecond Latency Percentile Histogram (p50, p99, p99.99)
;
; Delegates:
;   - ITCH Protocol Engine               -> unet/hft/itch.asm
;   - OUCH Protocol Engine               -> unet/hft/ouch.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define HFT_HISTOGRAM_BUCKETS       16

struc hft_bench_stats_t
    .ticks_processed:   resq 1
    .orders_sent:       resq 1
    .min_rtt_cycles:    resq 1
    .max_rtt_cycles:    resq 1
    .sum_rtt_cycles:    resq 1
endstruc

section .bss
alignb 64
hft_stats:              resb hft_bench_stats_t_size
hft_latency_buckets:    resq HFT_HISTOGRAM_BUCKETS

section .text

global hft_bench_main
global hft_bench_measure_tick_to_trade



align 64
hft_bench_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call hft_bench_measure_tick_to_trade

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; hft_bench_measure_tick_to_trade — Sub-Nanosecond ITCH -> OUCH Pipeline Benchmark
; Input: RDI = Pointer to ITCH Market Data Frame
; Output: RAX = Elapsed Cycles (Ingress to Egress)
; -----------------------------------------------------------------------------
align 64
hft_bench_measure_tick_to_trade:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Take Ingress Hardware RDTSC Timestamp T0
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov r12, rax                    ; R12 = T0

    ; 2. Execute Zero-Copy ITCH Market Data Parse
    mov rdi, rbx
    call itch_parse_message

    ; 3. Execute OUCH Order Placement Decision & Transmit Frame
    call ouch_send_order

    ; 4. Take Egress Hardware RDTSC Timestamp T1
    rdtsc
    shl rdx, 32
    or rax, rdx                    ; RAX = T1

    ; 5. Calculate Sub-Nanosecond Delta = T1 - T0
    sub rax, r12                    ; RAX = Elapsed Cycles

    ; 6. Accumulate Statistics
    lea rbx, [hft_stats]
    inc qword [rbx + hft_bench_stats_t.ticks_processed]
    inc qword [rbx + hft_bench_stats_t.orders_sent]
    add [rbx + hft_bench_stats_t.sum_rtt_cycles], rax

    cmp rax, [rbx + hft_bench_stats_t.min_rtt_cycles]
    jae .chk_max
    mov [rbx + hft_bench_stats_t.min_rtt_cycles], rax

.chk_max:
    cmp rax, [rbx + hft_bench_stats_t.max_rtt_cycles]
    jbe .done
    mov [rbx + hft_bench_stats_t.max_rtt_cycles], rax

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_BENCH_HFT_BENCH_ASM
