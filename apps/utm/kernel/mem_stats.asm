; UTM Kernel - Memory Statistics
; Pure Assembly Implementation

%ifndef _UTM_MEM_STATS_ASM_
%define _UTM_ENTERPRISE_MEM_STATS_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_mem_stats_lock dq 0

section .bss
align 64
global utm_global_mem_stats
utm_global_mem_stats:
    .total_pages      resq 1
    .free_pages       resq 1
    .available_pages  resq 1
    .cached_pages     resq 1
    .buffer_pages     resq 1
    .shared_pages     resq 1
    .slab_pages       resq 1
    .swap_total_pages resq 1
    .swap_free_pages  resq 1
    .compressed_pages resq 1
    .page_faults      resq 1
    .maj_faults       resq 1
    .pageins          resq 1
    .pageouts         resq 1
    .swapins          resq 1
    .swapouts         resq 1
    .anon_pages       resq 1
    .file_pages       resq 1
    .unevictable_pages resq 1
    .mlocked_pages    resq 1
    .nr_zones         resd 1
    .zone_info        resb 16 * 64

section .text

global utm_mem_stats_init
global utm_mem_detect_topology
global utm_mem_account_page_fault
global utm_mem_account_pagein
global utm_mem_account_pageout
global utm_mem_account_swapin
global utm_mem_account_swapout
global utm_mem_update_global
global utm_mem_get_process_stats
global utm_mem_calculate_pressure
global utm_mem_fill_system_sample
global utm_mem_estimate_process_energy

utm_mem_stats_init:
    mov rdi, utm_global_mem_stats
    mov rcx, 256
    xor rax, rax
    rep stosq
    
    call utm_mem_detect_topology
    ret

utm_mem_detect_topology:
    mov dword [utm_global_mem_stats + 144], 1
    ret

utm_mem_account_page_fault:
    inc qword [utm_global_mem_stats + 80]
    test rsi, rsi
    jz .minor
    inc qword [utm_global_mem_stats + 88]
.minor:
    ret

utm_mem_account_pagein:
    inc qword [utm_global_mem_stats + 96]
    ret

utm_mem_account_pageout:
    inc qword [utm_global_mem_stats + 104]
    ret

utm_mem_account_swapin:
    inc qword [utm_global_mem_stats + 112]
    ret

utm_mem_account_swapout:
    inc qword [utm_global_mem_stats + 120]
    ret

utm_mem_update_global:
    ret

utm_mem_get_process_stats:
    mov rax, UTM_ERR_NOTSUPP
    ret

utm_mem_calculate_pressure:
    mov rax, [utm_global_mem_stats]
    sub rax, [utm_global_mem_stats + 8]
    sub rax, [utm_global_mem_stats + 24]
    test rax, rax
    jz .zero
    
    mov rdx, [utm_global_mem_stats]
    sub rdx, [utm_global_mem_stats + 8]
    sub rdx, [utm_global_mem_stats + 24]
    sub rdx, [utm_global_mem_stats + 16]
    
    mov rcx, PERCENT_SCALE
    mul rcx
    div rax
    ret

.zero:
    xor rax, rax
    ret

utm_mem_fill_system_sample:
    mov rax, [utm_global_mem_stats]
    mov [rdi + SystemSample.mem_total], rax
    imul rax, PAGE_SIZE
    
    mov rax, [utm_global_mem_stats + 8]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_free], rax
    
    mov rax, [utm_global_mem_stats + 16]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_available], rax
    
    mov rax, [utm_global_mem_stats + 24]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_cached], rax
    
    mov rax, [utm_global_mem_stats + 16]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_buffers], rax
    
    mov rax, [utm_global_mem_stats + 32]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_shared], rax
    
    mov rax, [utm_global_mem_stats + 40]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_slab], rax
    
    mov rax, [utm_global_mem_stats + 48]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_swap_total], rax
    
    mov rax, [utm_global_mem_stats + 56]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_swap_free], rax
    
    mov rax, [utm_global_mem_stats + 48]
    sub rax, [utm_global_mem_stats + 56]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_swap_used], rax
    
    mov rax, [utm_global_mem_stats + 64]
    imul rax, PAGE_SIZE
    mov [rdi + SystemSample.mem_compressed], rax
    
    mov rax, [utm_global_mem_stats + 80]
    mov [rdi + SystemSample.mem_page_faults], rax
    
    mov rax, [utm_global_mem_stats + 88]
    mov [rdi + SystemSample.mem_maj_faults], rax
    
    mov rax, [utm_global_mem_stats + 96]
    mov [rdi + SystemSample.mem_pageins], rax
    
    mov rax, [utm_global_mem_stats + 104]
    mov [rdi + SystemSample.mem_pageouts], rax
    
    mov rax, [utm_global_mem_stats + 112]
    mov [rdi + SystemSample.mem_swapins], rax
    
    mov rax, [utm_global_mem_stats + 120]
    mov [rdi + SystemSample.mem_swapouts], rax
    
    ret

utm_mem_estimate_process_energy:
    xor rax, rax
    ret

%endif