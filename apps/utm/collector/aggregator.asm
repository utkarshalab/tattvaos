; UTM Collector - Aggregator
; Pure Assembly Implementation

%ifndef _UTM_AGGREGATOR_ASM_
%define _UTM_ENTERPRISE_AGGREGATOR_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .bss
align 64
utm_agg_1s:
    .window_start_ns  resq 1
    .sample_count     resq 1
    .cpu_sum          resq 1
    .cpu_sum_sq       resq 1
    .cpu_min          resd 1
    .cpu_max          resd 1
    .cpu_avg          resd 1
    .mem_sum          resq 1
    .mem_min          resq 1
    .mem_max          resq 1
    .mem_avg          resq 1
    .pad              resb 32

utm_agg_5s:
    .window_start_ns  resq 1
    .sample_count     resq 1
    .cpu_sum          resq 1
    .cpu_sum_sq       resq 1
    .cpu_min          resd 1
    .cpu_max          resd 1
    .cpu_avg          resd 1
    .pad              resb 32

utm_agg_60s:
    .window_start_ns  resq 1
    .sample_count     resq 1
    .cpu_sum          resq 1
    .cpu_sum_sq       resq 1
    .cpu_min          resd 1
    .cpu_max          resd 1
    .cpu_avg          resd 1
    .pad              resb 32

section .text

global utm_aggregator_update
global utm_aggregator_finalize_1s
global utm_aggregator_finalize_5s
global utm_aggregator_finalize_60s
global utm_aggregator_calculate_stats

extern utm_get_monotonic_ns
extern utm_ring_push

utm_aggregator_update:
    call utm_get_monotonic_ns
    
    mov rsi, utm_agg_1s
    mov rdx, rax
    sub rdx, [rsi]
    cmp rdx, NANO_SCALE
    jb .check_5s
    
    call utm_aggregator_finalize_1s
    mov [rsi], rax
    mov qword [rsi + 8], 0
    
.check_5s:
    mov rsi, utm_agg_5s
    mov rdx, rax
    sub rdx, [rsi]
    cmp rdx, 5 * NANO_SCALE
    jb .check_60s
    
    call utm_aggregator_finalize_5s
    mov [rsi], rax
    mov qword [rsi + 8], 0
    
.check_60s:
    mov rsi, utm_agg_60s
    mov rdx, rax
    sub rdx, [rsi]
    cmp rdx, 60 * NANO_SCALE
    jb .done
    
    call utm_aggregator_finalize_60s
    mov [rsi], rax
    mov qword [rsi + 8], 0
    
.done:
    ret

utm_aggregator_calculate_stats:
    mov rax, [rsi]
    mov [rdi + 32], eax
    mov [rdi + 36], eax
    
    xor rcx, rcx
    xor r9, r9
    xor r10, r10
    
.calc_loop:
    cmp rcx, rdx
    jge .calc_done
    
    mov eax, [rsi + rcx*4]
    
    cmp eax, [rdi + 32]
    jae .skip_min
    mov [rdi + 32], eax
.skip_min:
    
    cmp eax, [rdi + 36]
    jae .skip_max
    mov [rdi + 36], eax
.skip_max:
    
    mov r11, rax
    add r9, r11
    
    imul r11, r11
    add r10, r11
    
    inc rcx
    jmp .calc_loop
    
.calc_done:
    mov [rdi + 44], r9
    mov [rdi + 52], r10
    
    mov rax, r9
    xor rdx, rdx
    div rdx
    mov [rdi + 40], eax
    
    ret

utm_aggregator_finalize_1s:
    ret

utm_aggregator_finalize_5s:
    ret

utm_aggregator_finalize_60s:
    ret

%endif