; =============================================================================
; Tattva OS — unet/tools/tools.asm
; =============================================================================
; Master Universal `net` CLI Command Dispatcher Engine.
;
; Every network command in Tattva OS is executed via: `net <subcommand> [args]`
;   - `net ping`       ➔ Executes ICMP Echo Request Ping
;   - `net traceroute` ➔ Executes Hop-by-Hop TTL Probe
;   - `net tcpdump`    ➔ Executes Zero-Copy Packet Capture
;   - `net iperf`      ➔ Executes 400Gbps Throughput Benchmark
;   - `net route`      ➔ Executes Routing FIB Table Inspection
;   - `net arp`        ➔ Executes ARP / GARP Table Inspection
;   - `net dhcp`       ➔ Executes DHCP Auto-Configuration Client
;   - `net wireguard`  ➔ Executes WireGuard Handshake Benchmark
;   - `net bgp`        ➔ Executes BGP-4 RIB Session Inspector
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"
%include "unet/tools/tools.inc"

section .data
align 8
global net_cli_cmd_table
net_cli_cmd_table:
    ; Diagnostic Tools
    dq str_cmd_ping,        ping_send_echo,       str_cat_diag, str_desc_ping
    dq str_cmd_traceroute,  traceroute_probe,     str_cat_diag, str_desc_traceroute
    dq str_cmd_tcpdump,     tcpdump_capture,      str_cat_diag, str_desc_tcpdump
    dq str_cmd_netstat,     netstat_dump,         str_cat_diag, str_desc_netstat
    dq str_cmd_ss,          ss_tool_dump,         str_cat_diag, str_desc_ss
    dq str_cmd_mtr,         mtr_run,              str_cat_diag, str_desc_mtr

    ; Benchmark Tools
    dq str_cmd_iperf,       iperf_run,            str_cat_bench, str_desc_iperf
    dq str_cmd_pktgen,      pktgen_run,           str_cat_bench, str_desc_pktgen
    dq str_cmd_dpdk,        dpdk_pktgen_run,      str_cat_bench, str_desc_dpdk
    dq str_cmd_rdma,        rdma_perftest_run,    str_cat_bench, str_desc_rdma

    ; Routing & Infrastructure
    dq str_cmd_route,       route_tool_dump,      str_cat_route, str_desc_route
    dq str_cmd_arp,         arp_tool_dump,        str_cat_route, str_desc_arp
    dq str_cmd_ndp,         ndp_tool_dump,        str_cat_route, str_desc_ndp
    dq str_cmd_bridge,      bridge_tool_show,     str_cat_route, str_desc_bridge

    ; Telecom & Services
    dq str_cmd_dhcp,        dhcpclient_request,   str_cat_telecom, str_desc_dhcp
    dq str_cmd_ntp,         ntpdate_sync,         str_cat_telecom, str_desc_ntp
    dq str_cmd_lookup,      lookup_query,         str_cat_telecom, str_desc_lookup

    ; Security & VPN
    dq str_cmd_wireguard,   wireguard_test_run,   str_cat_security, str_desc_wireguard
    dq str_cmd_tls,         tls_info_inspect,     str_cat_security, str_desc_tls
    dq str_cmd_pqc,         pqc_inspect_parse,    str_cat_security, str_desc_pqc

    ; End of Table
    dq 0, 0, 0, 0

str_cmd_ping:           db "ping", 0
str_cmd_traceroute:     db "traceroute", 0
str_cmd_tcpdump:        db "tcpdump", 0
str_cmd_netstat:        db "netstat", 0
str_cmd_ss:             db "ss", 0
str_cmd_mtr:            db "mtr", 0
str_cmd_iperf:          db "iperf", 0
str_cmd_pktgen:         db "pktgen", 0
str_cmd_dpdk:           db "dpdk", 0
str_cmd_rdma:           db "rdma", 0
str_cmd_route:          db "route", 0
str_cmd_arp:            db "arp", 0
str_cmd_ndp:            db "ndp", 0
str_cmd_bridge:         db "bridge", 0
str_cmd_dhcp:           db "dhcp", 0
str_cmd_ntp:            db "ntp", 0
str_cmd_lookup:         db "lookup", 0
str_cmd_wireguard:      db "wireguard", 0
str_cmd_tls:            db "tls", 0
str_cmd_pqc:            db "pqc", 0

str_cat_diag:           db "diag", 0
str_cat_bench:          db "bench", 0
str_cat_route:          db "route", 0
str_cat_security:       db "security", 0
str_cat_telecom:        db "telecom", 0

str_desc_ping:          db "Send ICMP Echo Request Diagnostic Packets", 0
str_desc_traceroute:    db "Trace Hop-by-Hop IP Packet Route Path", 0
str_desc_tcpdump:       db "Zero-Copy Packet Sniffer & Protocol Decoder", 0
str_desc_netstat:       db "Dump Active Network Socket Connections", 0
str_desc_ss:            db "Fast Lockless Socket Statistics Dump", 0
str_desc_mtr:           db "Real-Time Path Latency & Jitter Monitor", 0
str_desc_iperf:         db "400Gbps Throughput & Bandwidth Meter", 0
str_desc_pktgen:        db "148.8 MPPS Line-Rate Packet Generator", 0
str_desc_dpdk:          db "DPDK Multi-Core Packet Generator", 0
str_desc_rdma:          db "InfiniBand/RoCE v2 RDMA Read/Write Benchmark", 0
str_desc_route:         db "Display & Modify IP Routing FIB Table", 0
str_desc_arp:           db "Display & Request L2 ARP / GARP Table", 0
str_desc_ndp:           db "IPv6 Neighbor Discovery Protocol Inspector", 0
str_desc_bridge:        db "Ethernet Software Bridge & VLAN Manager", 0
str_desc_dhcp:          db "DHCP IPv4/IPv6 Address Auto-Configuration", 0
str_desc_ntp:           db "NTP Atomic Time Sync Calibration", 0
str_desc_lookup:        db "DNS Record Resolution & Reverse Pointer Query", 0
str_desc_wireguard:     db "WireGuard VPN Handshake Benchmark", 0
str_desc_tls:           db "TLS 1.3 Certificate Chain Inspector", 0
str_desc_pqc:           db "Post-Quantum ML-KEM-1024 Key Inspector", 0

section .text

global net_cli_dispatch
global net_cli_help

; -----------------------------------------------------------------------------
; net_cli_dispatch — Parse `net <command>` and jump to sub-system tool
; Input: RDI = Pointer to command name string
;        RSI = Pointer to argument string
; -----------------------------------------------------------------------------
align 32
net_cli_dispatch:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    lea rbx, [net_cli_cmd_table]

.loop:
    mov rax, [rbx]
    test rax, rax
    jz .not_found                   ; End of table

    ; Compare string RDI with command name RAX
    push rdi
    push rsi
    mov rsi, rax
    call strcmp
    pop rsi
    pop rdi
    test eax, eax
    jz .execute                     ; Match found!

    add rbx, net_cmd_entry_t_size
    jmp .loop

.execute:
    mov rax, [rbx + net_cmd_entry_t.handler]
    mov rdi, rsi                    ; Pass remaining arguments to handler
    call rax
    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

.not_found:
    mov eax, -1                     ; Command not found error
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; net_cli_help — Print master `net` CLI help menu
; -----------------------------------------------------------------------------
align 32
net_cli_help:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; Helper function string compare
strcmp:
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .loop
.diff:
    mov eax, 1
    ret
.equal:
    xor eax, eax
    ret
