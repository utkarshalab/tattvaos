; UTM Collector - High-Frequency Sampler
; Pure Assembly Implementation

%ifndef _UTM_SAMPLER_ASM_
%define _UTM_ENTERPRISE_SAMPLER_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_sample_interval_ns  dq SAMPLE_NS

section .data
utm_sampler_running     dq 1

section .bss
align 4096
utm_ring_60hz:
    .header           resb RING_HEADER_SIZE
    .buffer           resb 600 * PROC_SAMPLE_SIZE

utm_ring_1s:
    .header           resb RING_HEADER_SIZE
    .buffer           resb 3600 * AGG_STATS_SIZE

utm_ring_5s:
    .header           resb RING_HEADER_SIZE
    .buffer           resb 720 * AGG_STATS_SIZE

utm_ring_60s:
    .header           resb RING_HEADER_SIZE
    .buffer           resb 1440 * AGG_STATS_SIZE

align 64
utm_current_agg:
    resb AGG_STATS_SIZE

utm_prev_sys_sample:
    resb SYS_SAMPLE_SIZE

section .text

global utm_sampler_main
global utm_sampler_collect
global utm_sampler_sleep_interval
global utm_ring_init_all
global utm_ring_push_60hz
global utm_prev_sys_sample
global utm_aggregator_update
global utm_aggregator_finalize_1s

extern utm_get_monotonic_ns
extern utm_ring_init
extern utm_ring_push
; extern utm_aggregator_update  -- linked at final link stage

utm_sampler_main:
    call utm_ring_init_all
    
    mov rax, SYS_UTM_COLLECTOR_REGISTER
    syscall
    
    call utm_sampler_collect
    
.main_loop:
    cmp qword [utm_sampler_running], 0
    je .exit
    
    call utm_sampler_sleep_interval
    call utm_sampler_collect
    call utm_ring_push_60hz
    
    ; call utm_aggregator_update  -- linked at final link stage
    
    jmp .main_loop

.exit:
    mov rax, SYS_UTM_COLLECTOR_UNREGISTER
    syscall
    ret

utm_sampler_sleep_interval:
    call utm_get_monotonic_ns
    add rax, [utm_sample_interval_ns]
    mov rdi, rax
    
.wait_loop:
    call utm_get_monotonic_ns
    cmp rax, rdi
    jb .wait_loop
    ret

utm_sampler_collect:
    sub rsp, SYS_SAMPLE_SIZE
    mov rdi, rsp
    mov rax, SYS_UTM_GET_SYS_SAMPLE
    syscall
    
    test rax, rax
    jl .error
    
    mov rsi, rsp
    mov rdi, utm_prev_sys_sample
    mov rcx, SYS_SAMPLE_SIZE / 8
    rep movsq
    
    add rsp, SYS_SAMPLE_SIZE
    ret

.error:
    add rsp, SYS_SAMPLE_SIZE
    ret

utm_ring_init_all:
    mov rdi, utm_ring_60hz
    call utm_ring_init
    mov rdi, utm_ring_1s
    call utm_ring_init
    mov rdi, utm_ring_5s
    call utm_ring_init
    mov rdi, utm_ring_60s
    call utm_ring_init
    ret

utm_ring_push_60hz:
    mov rdi, utm_ring_60hz
    call utm_ring_push
    ret

%endif