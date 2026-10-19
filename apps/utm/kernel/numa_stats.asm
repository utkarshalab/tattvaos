; UTM Kernel - NUMA Statistics
; Pure Assembly Implementation

%ifndef _UTM_NUMA_STATS_ASM_
%define _UTM_ENTERPRISE_NUMA_STATS_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_numa_stats_lock dq 0

section .bss
align 64
global utm_numa_stats
utm_numa_stats:
    resb MAX_NUMA_NODES * NUMA_NODE_STATS_SIZE

section .text

global utm_numa_stats_init
global utm_numa_detect_nodes
global utm_numa_account_local_hit
global utm_numa_account_remote_hit
global utm_numa_fill_system_sample

utm_numa_stats_init:
    mov rdi, utm_numa_stats
    mov rcx, MAX_NUMA_NODES * NUMA_NODE_STATS_SIZE / 8
    xor rax, rax
    rep stosq
    ret

utm_numa_detect_nodes:
    ret

utm_numa_account_local_hit:
    mov rax, utm_numa_stats
    mov rsi, rdi
    imul rsi, NUMA_NODE_STATS_SIZE
    add rax, rsi
    inc qword [rax + NumaNodeStats.memory_local_hits]
    ret

utm_numa_account_remote_hit:
    mov rax, utm_numa_stats
    mov rsi, rdi
    imul rsi, NUMA_NODE_STATS_SIZE
    add rax, rsi
    inc qword [rax + NumaNodeStats.memory_remote_hits]
    ret

utm_numa_fill_system_sample:
    mov rcx, MAX_NUMA_NODES
    mov rsi, utm_numa_stats
    mov rdi, rdi
    add rdi, SystemSample.numa_stats
    rep movsq
    
    mov ecx, [utm_numa_stats + NumaNodeStats.node_id]
    mov [rdi + SystemSample.numa_nodes - SystemSample.numa_stats], ecx
    ret

%endif