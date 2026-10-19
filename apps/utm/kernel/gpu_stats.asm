; UTM Kernel - GPU Statistics
; Pure Assembly Implementation

%ifndef _UTM_GPU_STATS_ASM_
%define _UTM_ENTERPRISE_GPU_STATS_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_gpu_stats_lock dq 0

section .bss
align 64
global utm_global_gpu_state
utm_global_gpu_state:
    resb GLOBAL_GPU_STATE_SIZE

section .text

global utm_gpu_stats_init
global utm_gpu_detect
global utm_gpu_read_nvidia
global utm_gpu_read_amd
global utm_gpu_read_intel
global utm_gpu_fill_system_sample

extern utm_get_monotonic_ns

utm_gpu_stats_init:
    mov rdi, utm_global_gpu_state
    mov rcx, GLOBAL_GPU_STATE_SIZE / 8
    xor rax, rax
    rep stosq
    
    call utm_gpu_detect
    ret

utm_gpu_detect:
    ret

utm_gpu_read_nvidia:
    ret

utm_gpu_read_amd:
    ret

utm_gpu_read_intel:
    ret

utm_gpu_fill_system_sample:
    mov rcx, MAX_GPUS
    mov rsi, utm_global_gpu_state + GlobalGpuState.gpu_util
    mov rdi, rdi
    add rdi, SystemSample.gpu_util_pct
    rep movsd
    
    mov rcx, MAX_GPUS
    mov rsi, utm_global_gpu_state + GlobalGpuState.gpu_mem_used
    mov rdi, rdi
    add rdi, SystemSample.gpu_mem_used
    rep movsq
    
    mov rcx, MAX_GPUS
    mov rsi, utm_global_gpu_state + GlobalGpuState.gpu_mem_total
    mov rdi, rdi
    add rdi, SystemSample.gpu_mem_total
    rep movsq
    
    mov rcx, MAX_GPUS
    mov rsi, utm_global_gpu_state + GlobalGpuState.gpu_temp
    mov rdi, rdi
    add rdi, SystemSample.gpu_temp_c
    rep movsd
    
    mov rcx, MAX_GPUS
    mov rsi, utm_global_gpu_state + GlobalGpuState.gpu_power
    mov rdi, rdi
    add rdi, SystemSample.gpu_power_w
    rep movsd
    
    mov eax, [utm_global_gpu_state + GlobalGpuState.gpu_count]
    mov [rdi + SystemSample.gpu_count - SystemSample.gpu_temp_c], eax
    ret

%endif