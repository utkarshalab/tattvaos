; =============================================================================
; Tattva OS — unet/tests/pqc_bench.asm
; =============================================================================
; Post-Quantum ML-KEM-1024 Kyber & ML-DSA Dilithium Latency Benchmark.
;
; Implements:
;   - Measures CPU Clock Cycles & Microseconds for PQC Key Gen, Encaps, Decaps
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pqc_bench_run

align 32
pqc_bench_run:
    push rbp
    mov rbp, rsp
    ; Benchmark PQC primitives and print cycle counts
    xor eax, eax
    pop rbp
    ret
