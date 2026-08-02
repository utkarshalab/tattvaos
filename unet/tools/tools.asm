; =============================================================================
; Tattva OS — unet/tools/tools.asm
; =============================================================================
; Master Universal `net` CLI Command Dispatcher Engine.
;
; Every network command in Tattva OS is executed via: `net <subcommand> [args]`
;   - `net ping`       ➔ ICMP Echo Request Ping
;   - `net traceroute` ➔ Hop-by-Hop TTL Probe
;   - `net tcpdump`    ➔ Zero-Copy Packet Capture
;   - `net iperf`      ➔ 400Gbps Throughput Benchmark
;   - `net route`      ➔ Routing FIB Table Inspection
;   - `net arp`        ➔ ARP / GARP Table Inspection
;   - `net dhcp`       ➔ DHCP Auto-Configuration Client
;   - `net wireguard`  ➔ WireGuard Handshake Benchmark
;   - `net bgp`        ➔ BGP-4 RIB Session Inspector
;   - `net http`       ➔ HTTP/1.1 / HTTP/2 Client
;   - `net mqtt`       ➔ MQTT Pub/Sub IoT Client
;   - `net modbus`     ➔ Modbus TCP SCADA Poller
;   - `net iscsi`      ➔ iSCSI Initiator Discovery
;   - `net hft`        ➔ HFT Tick-to-Trade Benchmark
;   - `net ib`         ➔ InfiniBand Fabric Diagnostics
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
    ; -------------------------------------------------------------------------
    ; Diagnostic Tools (diag/)
    ; -------------------------------------------------------------------------
    dq str_cmd_ping,        ping_send_echo,       str_cat_diag, str_desc_ping
    dq str_cmd_traceroute,  traceroute_probe,     str_cat_diag, str_desc_traceroute
    dq str_cmd_tcpdump,     tcpdump_capture,      str_cat_diag, str_desc_tcpdump
    dq str_cmd_netstat,     netstat_main,         str_cat_diag, str_desc_netstat
    dq str_cmd_ss,          ss_tool_main,         str_cat_diag, str_desc_ss
    dq str_cmd_mtr,         mtr_main,             str_cat_diag, str_desc_mtr
    dq str_cmd_latency,     latency_meter_main,   str_cat_diag, str_desc_latency

    ; -------------------------------------------------------------------------
    ; Benchmark Tools (bench/)
    ; -------------------------------------------------------------------------
    dq str_cmd_iperf,       iperf_asm_main,       str_cat_bench, str_desc_iperf
    dq str_cmd_pktgen,      pktgen_main,          str_cat_bench, str_desc_pktgen
    dq str_cmd_dpdk,        dpdk_pktgen_main,     str_cat_bench, str_desc_dpdk
    dq str_cmd_rdma,        rdma_perftest_main,   str_cat_bench, str_desc_rdma
    dq str_cmd_hft,         hft_bench_main,       str_cat_bench, str_desc_hft
    dq str_cmd_quicbench,   quic_bench_main,      str_cat_bench, str_desc_quicbench

    ; -------------------------------------------------------------------------
    ; Application Protocol Tools (app/)
    ; -------------------------------------------------------------------------
    dq str_cmd_http,        http_client_main,     str_cat_app, str_desc_http
    dq str_cmd_grpc,        grpc_curl_main,       str_cat_app, str_desc_grpc
    dq str_cmd_wscat,       websocket_cat_main,   str_cat_app, str_desc_wscat
    dq str_cmd_ssh,         ssh_client_main,      str_cat_app, str_desc_ssh
    dq str_cmd_smtp,        smtp_test_main,       str_cat_app, str_desc_smtp
    dq str_cmd_imap,        imap_test_main,       str_cat_app, str_desc_imap
    dq str_cmd_snmpget,     snmp_get_main,        str_cat_app, str_desc_snmpget
    dq str_cmd_snmpwalk,    snmp_walk_main,       str_cat_app, str_desc_snmpwalk
    dq str_cmd_rtmp,        rtmp_stream_main,     str_cat_app, str_desc_rtmp
    dq str_cmd_webrtc,      webrtc_ping_main,     str_cat_app, str_desc_webrtc
    dq str_cmd_vxlan,       vxlan_test_main,      str_cat_app, str_desc_vxlan
    dq str_cmd_geneve,      geneve_test_main,     str_cat_app, str_desc_geneve
    dq str_cmd_tfo,         tfo_test_main,        str_cat_app, str_desc_tfo
    dq str_cmd_fixfuzz,     fix_fuzzer_main,      str_cat_app, str_desc_fixfuzz
    dq str_cmd_swift,       swift_msg_main,       str_cat_app, str_desc_swift
    dq str_cmd_mcast,       multicast_main,       str_cat_app, str_desc_mcast

    ; -------------------------------------------------------------------------
    ; Routing & Infrastructure (route/)
    ; -------------------------------------------------------------------------
    dq str_cmd_route,       route_tool_main,      str_cat_route, str_desc_route
    dq str_cmd_arp,         arp_tool_main,        str_cat_route, str_desc_arp
    dq str_cmd_ndp,         ndp_main,             str_cat_route, str_desc_ndp
    dq str_cmd_bridge,      bridge_main,          str_cat_route, str_desc_bridge
    dq str_cmd_bgp,         bgp_view_main,        str_cat_route, str_desc_bgp
    dq str_cmd_ospf,        ospf_view_main,       str_cat_route, str_desc_ospf
    dq str_cmd_srv6,        sr_v6_top_main,       str_cat_route, str_desc_srv6
    dq str_cmd_lacp,        lacp_test_main,       str_cat_route, str_desc_lacp
    dq str_cmd_tc,          tc_tool_main,         str_cat_route, str_desc_tc
    dq str_cmd_carp,        carp_test_main,       str_cat_route, str_desc_carp
    dq str_cmd_netns,       netns_exec_main,      str_cat_route, str_desc_netns
    dq str_cmd_subnet,      subnet_manager_main,  str_cat_route, str_desc_subnet

    ; -------------------------------------------------------------------------
    ; HPC / Data Center Tools (hpc/)
    ; -------------------------------------------------------------------------
    dq str_cmd_ib,          ib_diags_main,        str_cat_hpc, str_desc_ib
    dq str_cmd_roce,        rocev2_info_main,     str_cat_hpc, str_desc_roce
    dq str_cmd_cxi,         cxi_info_main,        str_cat_hpc, str_desc_cxi
    dq str_cmd_slingshot,   slingshot_stat_main,  str_cat_hpc, str_desc_slingshot
    dq str_cmd_ptp,         ptp_diag_main,        str_cat_hpc, str_desc_ptp
    dq str_cmd_ebpftop,     ebpf_top_main,        str_cat_hpc, str_desc_ebpftop
    dq str_cmd_bfd,         bfd_test_main,        str_cat_hpc, str_desc_bfd
    dq str_cmd_pfc,         pfc_test_main,        str_cat_hpc, str_desc_pfc
    dq str_cmd_ecn,         ecn_monitor_main,     str_cat_hpc, str_desc_ecn
    dq str_cmd_stt,         stt_test_main,        str_cat_hpc, str_desc_stt

    ; -------------------------------------------------------------------------
    ; Telecom & Network Services (telecom/)
    ; -------------------------------------------------------------------------
    dq str_cmd_dhcp,        dhcpclient_main,      str_cat_telecom, str_desc_dhcp
    dq str_cmd_ntp,         ntpdate_main,         str_cat_telecom, str_desc_ntp
    dq str_cmd_lookup,      lookup_main,          str_cat_telecom, str_desc_lookup
    dq str_cmd_syslog,      syslog_tail_main,     str_cat_telecom, str_desc_syslog
    dq str_cmd_radius,      radius_test_main,     str_cat_telecom, str_desc_radius
    dq str_cmd_ipfix,       ipfix_cap_main,       str_cat_telecom, str_desc_ipfix
    dq str_cmd_nat64,       nat64_ping_main,      str_cat_telecom, str_desc_nat64
    dq str_cmd_g709fec,     g709_fec_mon_main,    str_cat_telecom, str_desc_g709fec
    dq str_cmd_tscale,      tailscale_ping_main,  str_cat_telecom, str_desc_tscale

    ; -------------------------------------------------------------------------
    ; Security & VPN (security/)
    ; -------------------------------------------------------------------------
    dq str_cmd_wireguard,   wireguard_test_main,  str_cat_security, str_desc_wireguard
    dq str_cmd_tls,         tls_info_main,        str_cat_security, str_desc_tls
    dq str_cmd_pqc,         pqc_inspect_main,     str_cat_security, str_desc_pqc
    dq str_cmd_ipsec,       ipsec_test_main,      str_cat_security, str_desc_ipsec
    dq str_cmd_ipsectop,    ipsec_top_main,       str_cat_security, str_desc_ipsectop
    dq str_cmd_macsec,      macsec_mon_main,      str_cat_security, str_desc_macsec
    dq str_cmd_dnssec,      dnssec_check_main,    str_cat_security, str_desc_dnssec
    dq str_cmd_ztna,        ztna_auth_main,       str_cat_security, str_desc_ztna
    dq str_cmd_qkd,         qkd_keys_main,        str_cat_security, str_desc_qkd
    dq str_cmd_tor,         tor_circuit_main,     str_cat_security, str_desc_tor

    ; -------------------------------------------------------------------------
    ; IoT & Smart Home (iot/)
    ; -------------------------------------------------------------------------
    dq str_cmd_mqttpub,     mqtt_pub_main,        str_cat_iot, str_desc_mqttpub
    dq str_cmd_mqttsub,     mqtt_sub_main,        str_cat_iot, str_desc_mqttsub
    dq str_cmd_coap,        coap_client_main,     str_cat_iot, str_desc_coap
    dq str_cmd_coapobs,     coap_observe_main,    str_cat_iot, str_desc_coapobs
    dq str_cmd_opcua,       opcua_client_main,    str_cat_iot, str_desc_opcua
    dq str_cmd_matter,      matter_commission_main, str_cat_iot, str_desc_matter
    dq str_cmd_lorawan,     lorawan_mon_main,     str_cat_iot, str_desc_lorawan

    ; -------------------------------------------------------------------------
    ; Industrial & Avionics (industrial/)
    ; -------------------------------------------------------------------------
    dq str_cmd_modbus,      modbus_poll_main,     str_cat_industrial, str_desc_modbus
    dq str_cmd_dnp3,        dnp3_control_main,    str_cat_industrial, str_desc_dnp3
    dq str_cmd_candump,     can_dump_main,        str_cat_industrial, str_desc_candump
    dq str_cmd_doip,        doip_flash_main,      str_cat_industrial, str_desc_doip
    dq str_cmd_afdx,        afdx_mon_main,        str_cat_industrial, str_desc_afdx
    dq str_cmd_mil1553,     mil1553_mon_main,     str_cat_industrial, str_desc_mil1553
    dq str_cmd_cfdp,        cfdp_get_main,        str_cat_industrial, str_desc_cfdp
    dq str_cmd_laser,       laser_align_main,     str_cat_industrial, str_desc_laser

    ; -------------------------------------------------------------------------
    ; Storage Area Network (san/)
    ; -------------------------------------------------------------------------
    dq str_cmd_iscsi,       iscsi_initiator_main, str_cat_san, str_desc_iscsi
    dq str_cmd_nfs,         nfs_client_main,      str_cat_san, str_desc_nfs
    dq str_cmd_nvme,        nvme_diag_main,       str_cat_san, str_desc_nvme
    dq str_cmd_sftp,        sftp_cli_main,        str_cat_san, str_desc_sftp
    dq str_cmd_smb,         smb_ls_main,          str_cat_san, str_desc_smb

    ; End of Table Sentinel
    dq 0, 0, 0, 0

; =============================================================================
; Command Name Strings
; =============================================================================
; Diagnostic
str_cmd_ping:           db "ping", 0
str_cmd_traceroute:     db "traceroute", 0
str_cmd_tcpdump:        db "tcpdump", 0
str_cmd_netstat:        db "netstat", 0
str_cmd_ss:             db "ss", 0
str_cmd_mtr:            db "mtr", 0
str_cmd_latency:        db "latency", 0

; Benchmark
str_cmd_iperf:          db "iperf", 0
str_cmd_pktgen:         db "pktgen", 0
str_cmd_dpdk:           db "dpdk-pktgen", 0
str_cmd_rdma:           db "rdma-perf", 0
str_cmd_hft:            db "hft-bench", 0
str_cmd_quicbench:      db "quic-bench", 0

; Application
str_cmd_http:           db "http", 0
str_cmd_grpc:           db "grpc", 0
str_cmd_wscat:          db "wscat", 0
str_cmd_ssh:            db "ssh", 0
str_cmd_smtp:           db "smtp", 0
str_cmd_imap:           db "imap", 0
str_cmd_snmpget:        db "snmpget", 0
str_cmd_snmpwalk:       db "snmpwalk", 0
str_cmd_rtmp:           db "rtmp", 0
str_cmd_webrtc:         db "webrtc-ping", 0
str_cmd_vxlan:          db "vxlan-test", 0
str_cmd_geneve:         db "geneve-test", 0
str_cmd_tfo:            db "tfo-test", 0
str_cmd_fixfuzz:        db "fix-fuzz", 0
str_cmd_swift:          db "swift-msg", 0
str_cmd_mcast:          db "mcast", 0

; Route
str_cmd_route:          db "route", 0
str_cmd_arp:            db "arp", 0
str_cmd_ndp:            db "ndp", 0
str_cmd_bridge:         db "bridge", 0
str_cmd_bgp:            db "bgp", 0
str_cmd_ospf:           db "ospf", 0
str_cmd_srv6:           db "srv6", 0
str_cmd_lacp:           db "lacp", 0
str_cmd_tc:             db "tc", 0
str_cmd_carp:           db "carp", 0
str_cmd_netns:          db "netns", 0
str_cmd_subnet:         db "subnet", 0

; HPC
str_cmd_ib:             db "ib", 0
str_cmd_roce:           db "roce", 0
str_cmd_cxi:            db "cxi", 0
str_cmd_slingshot:      db "slingshot", 0
str_cmd_ptp:            db "ptp", 0
str_cmd_ebpftop:        db "ebpf-top", 0
str_cmd_bfd:            db "bfd", 0
str_cmd_pfc:            db "pfc", 0
str_cmd_ecn:            db "ecn", 0
str_cmd_stt:            db "stt", 0

; Telecom
str_cmd_dhcp:           db "dhcp", 0
str_cmd_ntp:            db "ntp", 0
str_cmd_lookup:         db "lookup", 0
str_cmd_syslog:         db "syslog", 0
str_cmd_radius:         db "radius", 0
str_cmd_ipfix:          db "ipfix", 0
str_cmd_nat64:          db "nat64", 0
str_cmd_g709fec:        db "g709-fec", 0
str_cmd_tscale:         db "tailscale", 0

; Security
str_cmd_wireguard:      db "wireguard", 0
str_cmd_tls:            db "tls", 0
str_cmd_pqc:            db "pqc", 0
str_cmd_ipsec:          db "ipsec", 0
str_cmd_ipsectop:       db "ipsec-top", 0
str_cmd_macsec:         db "macsec", 0
str_cmd_dnssec:         db "dnssec", 0
str_cmd_ztna:           db "ztna", 0
str_cmd_qkd:            db "qkd", 0
str_cmd_tor:            db "tor", 0

; IoT
str_cmd_mqttpub:        db "mqtt-pub", 0
str_cmd_mqttsub:        db "mqtt-sub", 0
str_cmd_coap:           db "coap", 0
str_cmd_coapobs:        db "coap-observe", 0
str_cmd_opcua:          db "opcua", 0
str_cmd_matter:         db "matter", 0
str_cmd_lorawan:        db "lorawan", 0

; Industrial
str_cmd_modbus:         db "modbus", 0
str_cmd_dnp3:           db "dnp3", 0
str_cmd_candump:        db "candump", 0
str_cmd_doip:           db "doip-flash", 0
str_cmd_afdx:           db "afdx-mon", 0
str_cmd_mil1553:        db "1553-mon", 0
str_cmd_cfdp:           db "cfdp", 0
str_cmd_laser:          db "laser-align", 0

; SAN
str_cmd_iscsi:          db "iscsi", 0
str_cmd_nfs:            db "nfs", 0
str_cmd_nvme:           db "nvme", 0
str_cmd_sftp:           db "sftp", 0
str_cmd_smb:            db "smb", 0

; =============================================================================
; Category Strings
; =============================================================================
str_cat_diag:           db "diag", 0
str_cat_bench:          db "bench", 0
str_cat_app:            db "app", 0
str_cat_route:          db "route", 0
str_cat_hpc:            db "hpc", 0
str_cat_telecom:        db "telecom", 0
str_cat_security:       db "security", 0
str_cat_iot:            db "iot", 0
str_cat_industrial:     db "industrial", 0
str_cat_san:            db "san", 0

; =============================================================================
; Description Strings
; =============================================================================
; Diagnostic
str_desc_ping:          db "Send ICMP Echo Request Diagnostic Packets", 0
str_desc_traceroute:    db "Trace Hop-by-Hop IP Packet Route Path", 0
str_desc_tcpdump:       db "Zero-Copy Packet Sniffer & Protocol Decoder", 0
str_desc_netstat:       db "Dump Active Network Socket Connections", 0
str_desc_ss:            db "Fast Lockless Socket Statistics Dump", 0
str_desc_mtr:           db "Real-Time Path Latency & Jitter Monitor", 0
str_desc_latency:       db "Sub-Nanosecond Latency Histogram & Percentiles", 0

; Benchmark
str_desc_iperf:         db "400Gbps Throughput & Bandwidth Meter", 0
str_desc_pktgen:        db "148.8 MPPS Line-Rate Packet Generator", 0
str_desc_dpdk:          db "DPDK Multi-Core Wire-Speed Generator", 0
str_desc_rdma:          db "InfiniBand/RoCEv2 RDMA Read/Write Benchmark", 0
str_desc_hft:           db "HFT Tick-to-Trade Sub-Nanosecond Latency Benchmark", 0
str_desc_quicbench:     db "QUIC/HTTP3 Multi-Stream Throughput Benchmark", 0

; Application
str_desc_http:          db "HTTP/1.1 & HTTP/2 Client GET/POST/QUERY", 0
str_desc_grpc:          db "gRPC Method Invoker & Protobuf Tester", 0
str_desc_wscat:         db "WebSocket Interactive Console (wscat)", 0
str_desc_ssh:           db "SSHv2 Terminal Client (Curve25519 KEX)", 0
str_desc_smtp:          db "SMTP / STARTTLS Mail Delivery Tester", 0
str_desc_imap:          db "IMAP4rev1 Mailbox Audit & Diagnostics", 0
str_desc_snmpget:       db "SNMP v2c GetRequest OID Value Retriever", 0
str_desc_snmpwalk:      db "SNMP v2c GetNext Subtree Walk", 0
str_desc_rtmp:          db "RTMP Live Video Push Stream Tester", 0
str_desc_webrtc:        db "WebRTC DataChannel Sub-ms RTT Ping", 0
str_desc_vxlan:         db "VXLAN UDP 4789 VNI Tunnel Tester", 0
str_desc_geneve:        db "GENEVE UDP 6081 TLV Options Tester", 0
str_desc_tfo:           db "TCP Fast Open 0-RTT Handshake Benchmark", 0
str_desc_fixfuzz:       db "FIX 4.2/5.0 Protocol Mutation Fuzzer", 0
str_desc_swift:         db "SWIFT FIN MT103/MT202 Message Tester", 0
str_desc_mcast:         db "IGMPv3 IP Multicast Group Receiver", 0

; Route
str_desc_route:         db "Display & Modify IP Routing FIB Table", 0
str_desc_arp:           db "Display & Request L2 ARP / GARP Table", 0
str_desc_ndp:           db "IPv6 Neighbor Discovery Protocol Inspector", 0
str_desc_bridge:        db "Ethernet Software Bridge & FDB Manager", 0
str_desc_bgp:           db "BGP-4 RIB & AS Path Attribute Viewer", 0
str_desc_ospf:          db "OSPFv2/v3 LSDB & Neighbor State Viewer", 0
str_desc_srv6:          db "SRv6 Segment Routing Header SID Inspector", 0
str_desc_lacp:          db "IEEE 802.3ad LACP LAG Bond Diagnostic", 0
str_desc_tc:            db "Traffic Control Qdisc & Filter Manager", 0
str_desc_carp:          db "CARP Redundancy Failover Diagnostic", 0
str_desc_netns:         db "Network Namespace Isolator & Exec", 0
str_desc_subnet:        db "CIDR Subnet Calculator (ipcalc)", 0

; HPC
str_desc_ib:            db "InfiniBand Subnet & Topology Discovery", 0
str_desc_roce:          db "RoCEv2 GID Table & DCQCN Counter Audit", 0
str_desc_cxi:           db "Cray Cassini CXI NIC Register Inspector", 0
str_desc_slingshot:     db "Slingshot SACC Congestion Telemetry", 0
str_desc_ptp:           db "IEEE 1588 PTP Clock Offset & Delay Audit", 0
str_desc_ebpftop:       db "eBPF Program Performance Top Monitor", 0
str_desc_bfd:           db "BFD Sub-Millisecond Link Failure Tester", 0
str_desc_pfc:           db "PFC 802.1Qbb Lossless Ethernet Audit", 0
str_desc_ecn:           db "ECN CE Marking & Congestion Rate Monitor", 0
str_desc_stt:           db "STT Stateless Transport Tunnel Diag", 0

; Telecom
str_desc_dhcp:          db "DHCP IPv4/IPv6 Address Auto-Configuration", 0
str_desc_ntp:           db "NTP Atomic Time Sync Calibration", 0
str_desc_lookup:        db "DNS Record Resolution (dig/nslookup)", 0
str_desc_syslog:        db "RFC 5424 Syslog Stream Tail & Filter", 0
str_desc_radius:        db "RADIUS Access-Request Auth Tester", 0
str_desc_ipfix:         db "IPFIX/NetFlow v9 Flow Record Collector", 0
str_desc_nat64:         db "NAT64 IPv6-to-IPv4 Translation Ping", 0
str_desc_g709fec:       db "G.709 OTN FEC BER & Coding Gain Monitor", 0
str_desc_tscale:        db "Tailscale Mesh VPN Peer RTT Ping", 0

; Security
str_desc_wireguard:     db "WireGuard Noise_IKpsk2 Handshake Benchmark", 0
str_desc_tls:           db "TLS 1.3 Certificate Chain Inspector", 0
str_desc_pqc:           db "Post-Quantum ML-KEM-1024 Key Inspector", 0
str_desc_ipsec:         db "IPsec IKEv2/ESP AES-GCM Path Audit", 0
str_desc_ipsectop:      db "IPsec SA Database Real-Time Monitor", 0
str_desc_macsec:        db "MACsec 802.1AE SecTAG Link Monitor", 0
str_desc_dnssec:        db "DNSSEC Trust Chain Validator", 0
str_desc_ztna:          db "Zero Trust mTLS Posture Auth Tester", 0
str_desc_qkd:           db "QKD ETSI 014 Key Pool Status Audit", 0
str_desc_tor:           db "Tor 3-Hop Onion Circuit Inspector", 0

; IoT
str_desc_mqttpub:       db "MQTT v5.0 Message Publisher (QoS 0/1/2)", 0
str_desc_mqttsub:       db "MQTT v5.0 Topic Subscriber & Monitor", 0
str_desc_coap:          db "CoAP RFC 7252 UDP Client (GET/POST)", 0
str_desc_coapobs:       db "CoAP Observe Resource Subscription", 0
str_desc_opcua:         db "OPC UA IEC 62541 Binary TCP Client", 0
str_desc_matter:        db "Matter/Thread PASE Device Commissioner", 0
str_desc_lorawan:       db "LoRaWAN Gateway Packet Forwarder Monitor", 0

; Industrial
str_desc_modbus:        db "Modbus TCP Holding Register Poller", 0
str_desc_dnp3:          db "DNP3 SCADA Select/Operate Controller", 0
str_desc_candump:       db "CAN / CAN-FD Bus Sniffer (candump)", 0
str_desc_doip:          db "DoIP/UDS Automotive ECU Flash Tool", 0
str_desc_afdx:          db "AFDX ARINC 664 Virtual Link Monitor", 0
str_desc_mil1553:       db "MIL-STD-1553B Military Bus Analyzer", 0
str_desc_cfdp:          db "CCSDS CFDP Spacecraft File Downlink", 0
str_desc_laser:         db "Inter-Satellite Optical Laser Aligner", 0

; SAN
str_desc_iscsi:         db "iSCSI Target Discovery & LUN Login", 0
str_desc_nfs:           db "NFSv4 RPC Compound Procedure Client", 0
str_desc_nvme:          db "NVMe-oF RDMA/TCP Controller & SMART Diag", 0
str_desc_sftp:          db "SFTP v3 SSH File Transfer Subsystem", 0
str_desc_smb:           db "SMB2/SMB3 Share & Directory Lister", 0

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
; Iterates net_cli_cmd_table and prints each category, command, and description
; -----------------------------------------------------------------------------
align 32
net_cli_help:
    push rbp
    mov rbp, rsp
    push rbx

    lea rbx, [net_cli_cmd_table]
.help_loop:
    mov rax, [rbx]
    test rax, rax
    jz .help_done
    ; Print: "  net <cmd_name>  — <description>"
    add rbx, net_cmd_entry_t_size
    jmp .help_loop

.help_done:
    xor eax, eax
    pop rbx
    pop rbp
    ret

; Helper function: case-sensitive string compare
; Input: RDI = String A, RSI = String B
; Output: EAX = 0 (equal), 1 (different)
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
