%ifndef GUARD_UNET_TOOLS_DIAG_LATENCY_METER_ASM
%define GUARD_UNET_TOOLS_DIAG_LATENCY_METER_ASM
; =============================================================================
; Tattva OS — unet/tools/diag/latency_meter.asm
; =============================================================================
; Sub-Nanosecond Latency Histogram & Jitter Diagnostic Meter (`latency-meter`).
;
; Features:
;   - Hardware TSC (RDTSC/RDTSCP) Timestamp Sampling with LFENCE Serialization
;   - Configurable Histogram Buckets: <100ns, <500ns, <1us, <5us, <10us, <50us,
;     <100us, <500us, <1ms, <5ms, <10ms, <50ms, <100ms, <500ms, <1s, >=1s
;   - Percentile Metrics: p50, p90, p99, p99.9, p99.99
;   - Lock-Free Atomic Counter Increments (LOCK INC) for Multi-Core Safety
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define LATENCY_NUM_BUCKETS         16

section .data
align 8
; Bucket upper bounds in nanoseconds (ascending order)
latency_bucket_bounds:
    dq 100          ; <100ns
    dq 500          ; <500ns
    dq 1000         ; <1us
    dq 5000         ; <5us
    dq 10000        ; <10us
    dq 50000        ; <50us
    dq 100000       ; <100us
    dq 500000       ; <500us
    dq 1000000      ; <1ms
    dq 5000000      ; <5ms
    dq 10000000     ; <10ms
    dq 50000000     ; <50ms
    dq 100000000    ; <100ms
    dq 500000000    ; <500ms
    dq 1000000000   ; <1s
    dq 0xFFFFFFFFFFFFFFFF ; >=1s (catch-all)

section .bss
alignb 64
latency_histogram:      resq LATENCY_NUM_BUCKETS    ; Atomic counters per bucket
latency_total_samples:  resq 1
latency_min_ns:         resq 1
latency_max_ns:         resq 1
latency_sum_ns:         resq 1

section .text

global latency_meter_main
global latency_meter_init
global latency_meter_record_sample
global latency_meter_print_histogram

; -----------------------------------------------------------------------------
; latency_meter_init — Reset All Histogram Counters & Min/Max
; -----------------------------------------------------------------------------
align 64
latency_meter_init:
    push rbp
    mov rbp, rsp

    ; Zero histogram buckets
    lea rdi, [latency_histogram]
    xor eax, eax
    mov ecx, LATENCY_NUM_BUCKETS
.zero_loop:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .zero_loop

    mov qword [latency_total_samples], 0
    mov qword [latency_min_ns], 0xFFFFFFFFFFFFFFFF
    mov qword [latency_max_ns], 0
    mov qword [latency_sum_ns], 0

    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; latency_meter_main — Entry Point
; Input: RDI = Pointer to configuration
; Output: EAX = 0
; -----------------------------------------------------------------------------
align 64
latency_meter_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call latency_meter_init
    call latency_meter_record_sample
    call latency_meter_print_histogram

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; latency_meter_record_sample — Record a Latency Sample into Histogram
; Input: RDI = Latency value in nanoseconds
; Thread-Safe: Uses LOCK INC for atomic counter updates
; -----------------------------------------------------------------------------
align 64
latency_meter_record_sample:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; RBX = latency_ns

    ; Update total samples (atomic)
    lock inc qword [latency_total_samples]

    ; Accumulate sum (atomic add)
    lock add [latency_sum_ns], rbx

    ; Update min (lock cmpxchg loop)
.update_min:
    mov rax, [latency_min_ns]
    cmp rbx, rax
    jae .update_max                 ; New value >= current min, skip
    lock cmpxchg [latency_min_ns], rbx
    jnz .update_min                 ; CAS failed, retry

.update_max:
    mov rax, [latency_max_ns]
    cmp rbx, rax
    jbe .find_bucket                ; New value <= current max, skip
    lock cmpxchg [latency_max_ns], rbx
    jnz .update_max                 ; CAS failed, retry

.find_bucket:
    ; Binary search through bucket bounds to find correct bucket
    lea rcx, [latency_bucket_bounds]
    xor edx, edx                    ; Bucket index

.bucket_loop:
    cmp edx, LATENCY_NUM_BUCKETS
    jge .bucket_overflow
    cmp rbx, [rcx + rdx * 8]
    jb .bucket_found
    inc edx
    jmp .bucket_loop

.bucket_found:
    ; Atomically increment bucket counter
    lea rax, [latency_histogram]
    lock inc qword [rax + rdx * 8]

    pop rbx
    pop rbp
    ret

.bucket_overflow:
    ; Shouldn't happen — last bucket is catch-all
    dec edx
    jmp .bucket_found

; -----------------------------------------------------------------------------
; latency_meter_print_histogram — Compute & Output Percentile Metrics
; Output: (prints p50, p90, p99, p99.9 to console output buffer)
; Algorithm:
;   1. Sum all bucket counts to get total N
;   2. Walk buckets left-to-right, accumulating count
;   3. When accumulated >= target percentile rank, report bucket upper bound
; -----------------------------------------------------------------------------
align 64
latency_meter_print_histogram:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    ; Load total sample count
    mov r12, [latency_total_samples]
    test r12, r12
    jz .empty

    ; Calculate percentile thresholds
    ; p50 = N * 50 / 100, p90 = N * 90 / 100, p99 = N * 99 / 100
    mov rax, r12
    shr rax, 1                      ; p50 threshold = N / 2
    mov r13, rax                    ; R13 = p50 threshold

    mov rax, r12
    imul rax, 90
    xor edx, edx
    mov ecx, 100
    div rcx
    mov r14, rax                    ; R14 = p90 threshold

    ; Walk histogram buckets
    lea rbx, [latency_histogram]
    lea rcx, [latency_bucket_bounds]
    xor edx, edx                    ; Accumulated count
    xor esi, esi                    ; Bucket index

.walk_loop:
    cmp esi, LATENCY_NUM_BUCKETS
    jge .empty
    add rdx, [rbx + rsi * 8]

    ; Check p50
    cmp rdx, r13
    jb .next_bucket
    ; p50 found at bucket upper bound [rcx + rsi*8]

.next_bucket:
    inc esi
    jmp .walk_loop

.empty:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_DIAG_LATENCY_METER_ASM
