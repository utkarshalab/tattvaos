; UTM Kernel - Container Statistics
; Pure Assembly Implementation

%ifndef _UTM_CONTAINER_STATS_ASM_
%define _UTM_ENTERPRISE_CONTAINER_STATS_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_container_stats_lock dq 0

section .bss
align 64
global utm_container_stats
utm_container_stats:
    resb MAX_CONTAINERS * CONTAINER_SAMPLE_SIZE

section .text

global utm_container_stats_init
global utm_container_register
global utm_container_account_io
global utm_container_account_net
global utm_container_fill_sample
global utm_cgroup_get_info

utm_container_stats_init:
    mov rdi, utm_container_stats
    mov rcx, MAX_CONTAINERS * CONTAINER_SAMPLE_SIZE / 8
    xor rax, rax
    rep stosq
    ret

utm_container_register:
    mov r8, utm_container_stats
    add r8, rdi
    imul rdi, CONTAINER_SAMPLE_SIZE
    add r8, rdi
    mov rdi, r8
    mov rcx, CONTAINER_SAMPLE_SIZE / 8
    rep movsq
    ret

utm_container_account_io:
    ret

utm_container_account_net:
    ret

utm_container_fill_sample:
    mov rax, utm_container_stats
    mov rdx, rdi
    imul rdx, CONTAINER_SAMPLE_SIZE
    add rax, rdx
    mov rcx, CONTAINER_SAMPLE_SIZE / 8
    rep movsq
    ret

utm_cgroup_get_info:
    ret

%endif