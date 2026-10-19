; UTM Kernel - Network I/O Accounting
; Pure Assembly Implementation

%ifndef _UTM_NET_ACCOUNTING_ASM_
%define _UTM_ENTERPRISE_NET_ACCOUNTING_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_net_accounting_lock dq 0

section .bss
align 64
global utm_global_net_stats
utm_global_net_stats:
    resb GLOBAL_NET_STATS_SIZE

section .text

global utm_net_accounting_init
global utm_net_probe_interfaces
global utm_net_register_interface
global utm_net_account_packet
global utm_net_account_error
global utm_net_fill_system_sample
global utm_net_get_interface_info

utm_net_accounting_init:
    mov rdi, utm_global_net_stats
    mov rcx, GLOBAL_NET_STATS_SIZE / 8
    xor rax, rax
    rep stosq
    
    call utm_net_probe_interfaces
    ret

utm_net_probe_interfaces:
    ret

utm_net_register_interface:
    mov r8, utm_global_net_stats
    add r8, GlobalNetStats.iface_info
    add r8, rdi
    imul rdi, NET_IFACE_INFO_SIZE
    add r8, rdi
    mov rdi, r8
    mov rcx, NET_IFACE_INFO_SIZE / 8
    rep movsq
    ret

utm_net_account_packet:
    mov r9, utm_global_net_stats
    imul rdi, 8
    
    test rdx, rdx
    jz .rx
.tx:
    add [r9 + GlobalNetStats.tx_bytes + rdi], rsi
    add [r9 + GlobalNetStats.tx_packets + rdi], rcx
    test r8, r8
    jz .done
    add [r9 + GlobalNetStats.tx_errors + rdi], r8
    test r8, 1
    jz .done
    inc qword [r9 + GlobalNetStats.tx_dropped + rdi]
    ret

.rx:
    add [r9 + GlobalNetStats.rx_bytes + rdi], rsi
    add [r9 + GlobalNetStats.rx_packets + rdi], rcx
    test r8, r8
    jz .done
    add [r9 + GlobalNetStats.rx_errors + rdi], r8
    test r8, 1
    jz .done
    inc qword [r9 + GlobalNetStats.rx_dropped + rdi]
    ret
.done:
    ret

utm_net_account_error:
    ret

utm_net_fill_system_sample:
    mov rcx, MAX_NET_IFACES
    mov rsi, utm_global_net_stats
.fill_loop:
    mov rax, [rsi + GlobalNetStats.rx_bytes + rcx*8 - 8]
    mov [rdi + SystemSample.net_rx_bytes + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.tx_bytes + rcx*8 - 8]
    mov [rdi + SystemSample.net_tx_bytes + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.rx_packets + rcx*8 - 8]
    mov [rdi + SystemSample.net_rx_packets + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.tx_packets + rcx*8 - 8]
    mov [rdi + SystemSample.net_tx_packets + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.rx_errors + rcx*8 - 8]
    mov [rdi + SystemSample.net_rx_errors + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.tx_errors + rcx*8 - 8]
    mov [rdi + SystemSample.net_tx_errors + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.rx_dropped + rcx*8 - 8]
    mov [rdi + SystemSample.net_rx_dropped + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.tx_dropped + rcx*8 - 8]
    mov [rdi + SystemSample.net_tx_dropped + rcx*8 - 8], rax
    
    mov rax, [rsi + GlobalNetStats.speed_bps + rcx*8 - 8]
    mov [rdi + SystemSample.net_speed_bps + rcx*8 - 8], rax
    
    dec rcx
    jnz .fill_loop
    ret

utm_net_get_interface_info:
    mov r8, utm_global_net_stats
    add r8, GlobalNetStats.iface_info
    imul rdi, NET_IFACE_INFO_SIZE
    add r8, rdi
    mov rcx, NET_IFACE_INFO_SIZE / 8
    rep movsq
    ret

%endif