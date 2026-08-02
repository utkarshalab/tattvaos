# unet/tools — Network Diagnostic, Benchmark & Protocol Tools

> 90 Network diagnostic, debugging, benchmarking, and protocol tools for Tattva OS.
> All tools are invoked via the universal `net <subcommand> [args]` CLI interface.

## Tool Categories

### Diagnostic (`diag/`) — 7 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net ping` | ping.asm | Sub-microsecond ICMP Echo Request & RTT Statistics |
| `net traceroute` | traceroute.asm | TTL Probe Hop-by-Hop Path Trace |
| `net tcpdump` | tcpdump_asm.asm | Zero-Copy Packet Sniffer & Protocol Decoder |
| `net netstat` | netstat_asm.asm | Socket Table & Interface Statistics Inspector |
| `net ss` | ss_tool.asm | Fast Lockless Socket Statistics (cwnd, RTT, RTO) |
| `net mtr` | mtr.asm | Combined Traceroute/Ping Per-Hop Latency Monitor |
| `net latency` | latency_meter.asm | Sub-Nanosecond Latency Histogram (p50/p90/p99) |

### Benchmark (`bench/`) — 6 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net iperf` | iperf_asm.asm | TCP/UDP 400Gbps Multi-Stream Throughput Meter |
| `net pktgen` | pktgen.asm | 148.8 Mpps Line-Rate 64-Byte Packet Generator |
| `net dpdk-pktgen` | dpdk_pktgen.asm | DPDK PMD Multi-Core Wire-Speed Generator |
| `net rdma-perf` | rdma_perftest.asm | InfiniBand/RoCEv2 RDMA Read/Write Benchmark |
| `net hft-bench` | hft_bench.asm | HFT Sub-Nanosecond Tick-to-Trade Latency Benchmark |
| `net quic-bench` | quic_bench.asm | QUIC/HTTP3 Multi-Stream 0-RTT Throughput Benchmark |

### Application Protocol (`app/`) — 16 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net http` | http_client.asm | HTTP/1.1 & HTTP/2 Client (GET/POST/QUERY) |
| `net grpc` | grpc_curl.asm | gRPC Method Invoker & Protobuf Tester |
| `net wscat` | websocket_cat.asm | RFC 6455 WebSocket Interactive Console |
| `net ssh` | ssh_client.asm | SSHv2 Client (Curve25519 KEX, PTY Shell) |
| `net smtp` | smtp_test.asm | SMTP / STARTTLS Mail Delivery Tester |
| `net imap` | imap_test.asm | IMAP4rev1 Mailbox Audit & Diagnostics |
| `net snmpget` | snmp_get.asm | SNMP v2c GetRequest OID Value Retriever |
| `net snmpwalk` | snmp_walk.asm | SNMP v2c GetNext Subtree Walk |
| `net rtmp` | rtmp_stream.asm | RTMP Live Video Push Stream Tester |
| `net webrtc-ping` | webrtc_ping.asm | WebRTC DataChannel Sub-ms RTT Ping |
| `net vxlan-test` | vxlan_test.asm | VXLAN UDP 4789 VNI Tunnel Tester |
| `net geneve-test` | geneve_test.asm | GENEVE UDP 6081 TLV Options Tester |
| `net tfo-test` | tfo_test.asm | TCP Fast Open 0-RTT Handshake Benchmark |
| `net fix-fuzz` | fix_fuzzer.asm | FIX 4.2/5.0 Protocol Mutation Fuzzer |
| `net swift-msg` | swift_msg.asm | SWIFT FIN MT103/MT202 Message Tester |
| `net mcast` | multicast.asm | IGMPv3 Multicast Group Sender/Receiver |

### Routing & Infrastructure (`route/`) — 12 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net route` | route_tool.asm | IP Routing FIB Table Manager (Add/Del/Flush) |
| `net arp` | arp_tool.asm | ARP Cache Inspector & Gratuitous ARP |
| `net ndp` | ndp.asm | IPv6 Neighbor Discovery Protocol Inspector |
| `net bridge` | bridge.asm | Ethernet L2 Bridge FDB & STP Manager |
| `net bgp` | bgp_view.asm | BGP-4 RIB & AS Path Attribute Viewer |
| `net ospf` | ospf_view.asm | OSPFv2/v3 LSDB & Neighbor State Viewer |
| `net srv6` | sr_v6_top.asm | SRv6 Segment Routing Header SID Inspector |
| `net lacp` | lacp_test.asm | IEEE 802.3ad LACP LAG Bond Diagnostic |
| `net tc` | tc_tool.asm | Traffic Control Qdisc & Filter Manager |
| `net carp` | carp_test.asm | CARP Redundancy Failover Diagnostic |
| `net netns` | netns_exec.asm | Network Namespace Isolator & Command Exec |
| `net subnet` | subnet_manager.asm | CIDR Subnet Calculator (ipcalc) |

### HPC / Data Center (`hpc/`) — 10 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net ib` | ib_diags.asm | InfiniBand Subnet Topology Discovery |
| `net roce` | rocev2_info.asm | RoCEv2 GID Table & DCQCN Counter Audit |
| `net cxi` | cxi_info.asm | Cray Cassini CXI NIC Register Inspector |
| `net slingshot` | slingshot_stat.asm | Slingshot SACC Congestion Telemetry |
| `net ptp` | ptp_diag.asm | IEEE 1588 PTP Clock Offset & Delay Audit |
| `net ebpf-top` | ebpf_top.asm | eBPF Program Performance Top Monitor |
| `net bfd` | bfd_test.asm | BFD Sub-Millisecond Link Failure Tester |
| `net pfc` | pfc_test.asm | PFC 802.1Qbb Lossless Ethernet Audit |
| `net ecn` | ecn_monitor.asm | ECN CE Marking & Congestion Rate Monitor |
| `net stt` | stt_test.asm | STT Stateless Transport Tunnel Diagnostic |

### Telecom & Services (`telecom/`) — 9 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net dhcp` | dhcpclient.asm | DHCP IPv4/IPv6 Address Auto-Configuration |
| `net ntp` | ntpdate.asm | NTP Atomic Time Sync Calibration |
| `net lookup` | lookup.asm | DNS Record Resolution (dig/nslookup) |
| `net syslog` | syslog_tail.asm | RFC 5424 Syslog Stream Tail & Filter |
| `net radius` | radius_test.asm | RADIUS Access-Request Auth Tester |
| `net ipfix` | ipfix_cap.asm | IPFIX/NetFlow v9 Flow Record Collector |
| `net nat64` | nat64_ping.asm | NAT64 IPv6-to-IPv4 Translation Ping |
| `net g709-fec` | g709_fec_mon.asm | G.709 OTN FEC BER & Coding Gain Monitor |
| `net tailscale` | tailscale_ping.asm | Tailscale Mesh VPN Peer RTT Ping |

### Security & VPN (`security/`) — 10 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net wireguard` | wireguard_test.asm | WireGuard Noise_IKpsk2 Handshake Benchmark |
| `net tls` | tls_info.asm | TLS 1.3 Certificate & Cipher Suite Inspector |
| `net pqc` | pqc_inspect.asm | Post-Quantum ML-KEM-1024 Key Inspector |
| `net ipsec` | ipsec_test.asm | IPsec IKEv2/ESP AES-GCM Path Audit |
| `net ipsec-top` | ipsec_top.asm | IPsec SA Database Real-Time Monitor |
| `net macsec` | macsec_mon.asm | MACsec 802.1AE SecTAG Link Monitor |
| `net dnssec` | dnssec_check.asm | DNSSEC Trust Chain Validator |
| `net ztna` | ztna_auth.asm | Zero Trust mTLS Posture Auth Tester |
| `net qkd` | qkd_keys.asm | QKD ETSI 014 Key Pool Status Audit |
| `net tor` | tor_circuit.asm | Tor 3-Hop Onion Circuit Inspector |

### IoT & Smart Home (`iot/`) — 7 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net mqtt-pub` | mqtt_pub.asm | MQTT v5.0 Message Publisher (QoS 0/1/2) |
| `net mqtt-sub` | mqtt_sub.asm | MQTT v5.0 Topic Subscriber & Monitor |
| `net coap` | coap_client.asm | CoAP RFC 7252 UDP Client (GET/POST) |
| `net coap-observe` | coap_observe.asm | CoAP Observe Resource Subscription |
| `net opcua` | opcua_client.asm | OPC UA IEC 62541 Binary TCP Client |
| `net matter` | matter_commission.asm | Matter/Thread PASE Device Commissioner |
| `net lorawan` | lorawan_mon.asm | LoRaWAN Gateway Packet Forwarder Monitor |

### Industrial & Avionics (`industrial/`) — 8 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net modbus` | modbus_poll.asm | Modbus TCP Register Poller |
| `net dnp3` | dnp3_control.asm | DNP3 SCADA Select/Operate Controller |
| `net candump` | can_dump.asm | CAN / CAN-FD Bus Sniffer (candump) |
| `net doip-flash` | doip_flash.asm | DoIP/UDS Automotive ECU Flash Tool |
| `net afdx-mon` | afdx_mon.asm | AFDX ARINC 664 Virtual Link Monitor |
| `net 1553-mon` | mil1553_mon.asm | MIL-STD-1553B Military Bus Analyzer |
| `net cfdp` | cfdp_get.asm | CCSDS CFDP Spacecraft File Downlink |
| `net laser-align` | laser_align.asm | Inter-Satellite Optical Laser Aligner |

### Storage Area Network (`san/`) — 5 Tools
| Command | Tool | Description |
|---------|------|-------------|
| `net iscsi` | iscsi_initiator.asm | iSCSI Target Discovery & LUN Login |
| `net nfs` | nfs_client.asm | NFSv4 RPC Compound Procedure Client |
| `net nvme` | nvme_diag.asm | NVMe-oF RDMA/TCP Controller & SMART Diagnostic |
| `net sftp` | sftp_cli.asm | SFTP v3 SSH File Transfer Subsystem |
| `net smb` | smb_ls.asm | SMB2/SMB3 Share & Directory Lister |

---

Part of the `unet/` network stack in Tattva OS.
