; UTM Kernel - CPU Accounting
; Pure Assembly Implementation

%ifndef _UTM_CPU_ACCOUNTING_ASM_
%define _UTM_ENTERPRISE_CPU_ACCOUNTING_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_cpu_accounting_lock dq 0

section .bss
align 4096
global utm_per_cpu_stats
utm_per_cpu_stats:
    resb MAX_CPUS * PER_CPU_STATS_SIZE

align 64
global utm_global_cpu_stats
utm_global_cpu_stats:
    .total_user_ns    resq 1
    .total_kernel_ns  resq 1
    .total_idle_ns    resq 1
    .total_iowait_ns  resq 1
    .total_irq_ns     resq 1
    .total_softirq_ns resq 1
    .total_steal_ns   resq 1
    .total_guest_ns   resq 1
    .total_ctx_switches resq 1
    .total_migrations   resq 1
    .load_1m          resd 1
    .load_5m          resd 1
    .load_15m         resd 1
    .nr_running       resd 1
    .nr_uninterruptible resd 1
    .last_calc_ns     resq 1

section .text

global utm_cpu_accounting_init
global utm_cpu_detect_topology
global utm_cpu_account_thread_tick
global utm_cpu_account_idle
global utm_cpu_account_iowait
global utm_cpu_account_irq
global utm_cpu_account_softirq
global utm_cpu_get_stats
global utm_cpu_calculate_load
global utm_get_current_cpu

extern utm_proc_table
extern utm_proc_entry_size_val

utm_cpu_accounting_init:
    mov rdi, utm_per_cpu_stats
    mov rcx, MAX_CPUS * PER_CPU_STATS_SIZE
    xor rax, rax
    rep stosb
    
    mov rdi, utm_global_cpu_stats
    mov rcx, 64
    xor rax, rax
    rep stosq
    
    call utm_cpu_detect_topology
    ret

utm_cpu_detect_topology:
    mov rcx, MAX_CPUS
    mov rdi, utm_per_cpu_stats
.topology_loop:
    mov byte [rdi + PerCpuStats.is_p_core], 1
    mov byte [rdi + PerCpuStats.is_active], 1
    mov dword [rdi + PerCpuStats.cpu_id], ecx
    dec ecx
    add rdi, PER_CPU_STATS_SIZE
    loop .topology_loop
    
    mov qword [utm_global_cpu_stats + 56], -1
    mov qword [utm_global_cpu_stats + 64], -1
    ret

utm_cpu_account_thread_tick:
    call utm_get_current_cpu
    mov r8, rax
    
    mov r9, [rdi + ThreadEntry.proc_index]
    mov r10, [rdi + ThreadEntry.last_mode]
    
    mov rax, rsi
    imul rax, TICK_NS_PER_TICK
    
    mov r11, utm_per_cpu_stats
    mov rax, r8
    mov rdx, PROC_ENTRY_SIZE
    mul r8
    add r11, rax
    
    test r10, r10
    jz .user_mode
.kernel_mode:
    add qword [r11 + PerCpuStats.kernel_ns], rax
    jmp .done_cpu
.user_mode:
    add qword [r11 + PerCpuStats.user_ns], rax
.done_cpu:
    
    add qword [rdi + ThreadEntry.cpu_user_ns], rax
    test r10, r10
    jz .done_thread
    add qword [rdi + ThreadEntry.cpu_kernel_ns], rax
.done_thread:
    
    mov r11, utm_proc_table
    mov rax, r9
    mov r8, PROC_ENTRY_SIZE
    mul r8
    add r11, rax
    add qword [r11 + ProcessEntry.total_cpu_ns], rax
    
    test r10, r10
    jz .global_user
    add qword [utm_global_cpu_stats + 8], rax
    ret
.global_user:
    add qword [utm_global_cpu_stats], rax
    ret

utm_cpu_account_idle:
    mov r8, utm_per_cpu_stats
    mov rax, rdi
    imul rax, PER_CPU_STATS_SIZE
    add r8, rax
    add qword [r8 + PerCpuStats.idle_ns], rsi
    add qword [utm_global_cpu_stats + 16], rsi
    ret

utm_cpu_account_iowait:
    mov r8, utm_per_cpu_stats
    mov rax, rdi
    imul rax, PER_CPU_STATS_SIZE
    add r8, rax
    add qword [r8 + PerCpuStats.iowait_ns], rsi
    add qword [utm_global_cpu_stats + 24], rsi
    ret

utm_cpu_account_irq:
    mov r8, utm_per_cpu_stats
    mov rax, rdi
    imul rax, PER_CPU_STATS_SIZE
    add r8, rax
    add qword [r8 + PerCpuStats.irq_ns], rsi
    add qword [utm_global_cpu_stats + 32], rsi
    ret

utm_cpu_account_softirq:
    mov r8, utm_per_cpu_stats
    mov rax, rdi
    imul rax, PER_CPU_STATS_SIZE
    add r8, rax
    add qword [r8 + PerCpuStats.softirq_ns], rsi
    add qword [utm_global_cpu_stats + 40], rsi
    ret

utm_cpu_get_stats:
    mov rcx, MAX_CPUS
    xor r8, r8
    xor r9, r9
    xor r10, r10
    xor r11, r11
    
.sum_loop:
    mov rsi, utm_per_cpu_stats
    mov rax, rcx
    dec rax
    imul rax, PER_CPU_STATS_SIZE
    add rsi, rax
    
    add r8, [rsi + PerCpuStats.user_ns]
    add r9, [rsi + PerCpuStats.kernel_ns]
    add r10, [rsi + PerCpuStats.idle_ns]
    add r11, [rsi + PerCpuStats.iowait_ns]
    
    mov eax, [rsi + PerCpuStats.cpu_id]
    mov dword [rdi + SystemSample.cpu_per_core + rax*4], 0
    
    loop .sum_loop
    
    mov rax, r8
    add rax, r9
    add rax, r10
    add rax, r11
    test rax, rax
    jz .cpu_done
    
    mov rdx, 0
    mov rcx, PERCENT_SCALE
    div rcx
    mov [rdi + SystemSample.cpu_total_percent], eax
    
    mov rax, r8
    mov rdx, 0
    div rcx
    div r8
    mov [rdi + SystemSample.cpu_user_percent], eax
    
    mov rax, r9
    mov rdx, 0
    div rcx
    div r8
    mov [rdi + SystemSample.cpu_kernel_percent], eax
    
    mov rax, r10
    mov rdx, 0
    div rcx
    div r8
    mov [rdi + SystemSample.cpu_idle_percent], eax
    
.cpu_done:
    ret

utm_cpu_calculate_load:
    mov rax, [utm_global_cpu_stats + 72]
    mov ebx, [utm_global_cpu_stats + 76]
    add eax, ebx
    
    mov rcx, [utm_global_cpu_stats + 64]
    imul ecx, 918
    mov rdx, rax
    imul rdx, 82
    add rcx, rdx
    shr rcx, 10
    mov [utm_global_cpu_stats + 64], ecx
    
    mov ecx, [utm_global_cpu_stats + 68]
    imul ecx, 983
    mov rdx, rax
    imul rdx, 17
    add rcx, rdx
    shr rcx, 10
    mov [utm_global_cpu_stats + 68], ecx
    
    mov ecx, [utm_global_cpu_stats + 72]
    imul ecx, 994
    mov rdx, rax
    imul rdx, 6
    add rcx, rdx
    shr rcx, 10
    mov [utm_global_cpu_stats + 72], ecx
    
    ret

utm_get_current_cpu:
    xor rax, rax
    ret

%endif