; UTM Kernel - Disk I/O Accounting
; Pure Assembly Implementation

%ifndef _UTM_DISK_ACCOUNTING_ASM_
%define _UTM_ENTERPRISE_DISK_ACCOUNTING_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_disk_accounting_lock dq 0

section .bss
align 64
global utm_global_disk_stats
utm_global_disk_stats:
    resb GLOBAL_DISK_STATS_SIZE

section .text

global utm_disk_accounting_init
global utm_disk_probe_devices
global utm_disk_register_device
global utm_disk_account_io
global utm_disk_account_queue
global utm_disk_update_utilization
global utm_disk_fill_system_sample
global utm_disk_get_device_info

utm_disk_accounting_init:
    mov rdi, utm_global_disk_stats
    mov rcx, GLOBAL_DISK_STATS_SIZE / 8
    xor rax, rax
    rep stosq
    
    call utm_disk_probe_devices
    ret

utm_disk_probe_devices:
    ret

utm_disk_register_device:
    mov r8, utm_global_disk_stats
    add r8, GlobalDiskStats.device_info
    add r8, rdi
    imul rdi, DISK_DEVICE_INFO_SIZE
    add r8, rdi
    mov rdi, r8
    mov rcx, DISK_DEVICE_INFO_SIZE / 8
    rep movsq
    ret

utm_disk_account_io:
    mov r9, utm_global_disk_stats
    imul rdi, 8
    
    cmp rdx, 0
    je .read_op
    cmp rdx, 1
    je .write_op
    cmp rdx, 2
    je .flush_op
    cmp rdx, 3
    je .discard_op
    ret

.read_op:
    add [r9 + GlobalDiskStats.read_bytes + rdi], rsi
    inc qword [r9 + GlobalDiskStats.read_ops + rdi]
    jmp .latency

.write_op:
    add [r9 + GlobalDiskStats.write_bytes + rdi], rsi
    inc qword [r9 + GlobalDiskStats.write_ops + rdi]
    jmp .latency

.flush_op:
    inc qword [r9 + GlobalDiskStats.flush_ops + rdi]
    ret

.discard_op:
    inc qword [r9 + GlobalDiskStats.discard_ops + rdi]
    add [r9 + GlobalDiskStats.discard_bytes + rdi], rsi
    ret

.latency:
    sub r8, rcx
    test rdx, rdx
    jz .read_lat
    add [r9 + GlobalDiskStats.write_latency_ns + rdi], r8
    ret
.read_lat:
    add [r9 + GlobalDiskStats.read_latency_ns + rdi], r8
    ret

utm_disk_account_queue:
    mov r8, utm_global_disk_stats
    imul rdi, 4
    mov [r8 + GlobalDiskStats.queue_depth + rdi], esi
    ret

utm_disk_update_utilization:
    ret

utm_disk_fill_system_sample:
    mov rcx, MAX_DISKS
    mov rsi, utm_global_disk_stats
.fill_loop:
    mov rax, [rsi + GlobalDiskStats.read_bytes + rcx*8 - 8]
    mov [rdi + SystemSample.disk_read_bytes + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalDiskStats.write_bytes + rcx*8 - 8]
    mov [rdi + SystemSample.disk_write_bytes + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalDiskStats.read_ops + rcx*8 - 8]
    mov [rdi + SystemSample.disk_read_ops + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalDiskStats.write_ops + rcx*8 - 8]
    mov [rdi + SystemSample.disk_write_ops + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalDiskStats.read_latency_ns + rcx*8 - 8]
    mov rdx, [rsi + GlobalDiskStats.read_ops + rcx*8 - 8]
    test rdx, rdx
    jz .no_read_lat
    div rdx
    mov [rdi + SystemSample.disk_read_lat_ns + rcx*8 - 8], rax
.no_read_lat:
    
    mov rax, [rsi + GlobalDiskStats.write_latency_ns + rcx*8 - 8]
    mov rdx, [rsi + GlobalDiskStats.write_ops + rcx*8 - 8]
    test rdx, rdx
    jz .no_write_lat
    div rdx
    mov [rdi + SystemSample.disk_write_lat_ns + rcx*8 - 8], rax
.no_write_lat:
    
    mov eax, [rsi + GlobalDiskStats.queue_depth + rcx*4 - 4]
    mov [rdi + SystemSample.disk_util_pct + rcx*4 - 4], eax
    mov [rdi + SystemSample.disk_queue_depth + rcx*4 - 4], eax
    
    dec rcx
    jnz .fill_loop
    ret

utm_disk_get_device_info:
    mov r8, utm_global_disk_stats
    add r8, GlobalDiskStats.device_info
    imul rdi, DISK_DEVICE_INFO_SIZE
    add r8, rdi
    mov rcx, DISK_DEVICE_INFO_SIZE / 8
    rep movsq
    ret

%endif