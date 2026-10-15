# utcp - Micro TCP/IP Stack in Pure Assembly

A dependency-free, bare-metal compatible TCP/IP stack written entirely in x86-64 assembly (NASM syntax). Designed for unikernels, OS development, and embedded systems.

## Features Implemented

| Feature | RFC | Status | Files |
|---------|-----|--------|-------|
| **Core TCP/IP** | | | |
| Ethernet II | RFC 894 | ✅ | `utcp_ethernet.asm` |
| IPv4 | RFC 791 | ✅ | `utcp_ipv4.asm` |
| IPv6 | RFC 8200 | ✅ | `ipv6_tcp.asm` |
| UDP | RFC 768 | ✅ | `utcp_udp.asm` |
| TCP | RFC 793 | ✅ | `utcp_tcp.asm` |
| **Transport Reliability** | | | |
| SACK (Selective ACK) | RFC 2018, 6675 | ✅ | `tcp.asm` |
| Out-of-Order Reassembly | RFC 2883 | ✅ | `tcp.asm` |
| Fast Retransmit/Recovery | RFC 6582 | ✅ | `tcp.asm` |
| **Congestion Control** | | | |
| CUBIC | RFC 8312 | ✅ | `tcp_cubic.asm` |
| BBRv2 | RFC 9402 | ✅ | `tcp_bbrv2.asm` |
| RTO Calculation | RFC 6298 | ✅ | `tcp_timer.asm` |
| **Security** | | | |
| SYN Cookies | RFC 6528, 4987 | ✅ | `tcp_syncookie.asm` |
| ECN | RFC 3168, 8311 | ✅ | `tcp_ecn.asm` |
| TCP-AO | RFC 5925 | ✅ | `tcp_ao.asm` |
| **Path Adaptation** | | | |
| PMTUD | RFC 1191, 4821, 8899 | ✅ | `ipv4_pmtud.asm` |
| **Connection Management** | | | |
| TCP Fast Open | RFC 7413 | ✅ | `tcp_fastopen.asm` |
| SYN Cookies | RFC 6528 | ✅ | `tcp_syncookie.asm` |
| **Performance** | | | |
| Timer Wheel | Linux-style | ✅ | `timer_wheel.asm` |
| Batch RX/TX API | DPDK-style | ✅ | `net_batch.asm` |
| AVX-512 Checksum | SIMD | ✅ | `avx512_checksum.asm` |
| AVX-512 Parser | SIMD | ✅ | `avx512_parser.asm` |
| **ICMP/Utilities** | | | |
| ICMP | RFC 792 | ✅ | `utcp_icmp.asm` |
| ARP | RFC 826 | ✅ | `utcp_arp.asm` |
| DHCP/NDP stubs | | ✅ | |

## Architecture

```
utcp/
├── include/
│   ├── utcp.inc          # Assembly constants, structs, macros
│   ├── utcp.h            # C header for integration
│   └── unet_abi.inc      # ABI definitions
├── src/
│   ├── utcp_checksum.asm     # RFC 1071/1141 checksums
│   ├── utcp_ethernet.asm     # Ethernet II frame handling
│   ├── utcp_ipv4.asm         # IPv4 packet handling
│   ├── utcp_ipv6.asm         # IPv6 packet handling (NEW)
│   ├── utcp_udp.asm          # UDP packet handling
│   ├── utcp_tcp.asm          # Core TCP logic
│   ├── utcp_tcp.asm          # Core TCP logic
│   ├── utcp_tcp_timer.asm    # Timer integration
│   ├── utcp_bbrv2.asm        # BBRv2 congestion control (NEW)
│   ├── utcp_syncookie.asm    # SYN cookie DoS protection (NEW)
│   ├── utcp_ecn.asm          # ECN support (NEW)
│   ├── utcp_ao.asm           # TCP-AO authentication (NEW)
│   ├── utcp_fastopen.asm     # TCP Fast Open (NEW)
│   ├── utcp_arp.asm          # ARP cache + resolution
│   ├── utcp_icmp.asm         # ICMP echo/unreach/time exceeded
│   ├── utcp_netif.asm        # Network interface abstraction
│   ├── utcp_example.asm      # Unikernel example
│   ├── ipv6_tcp.asm          # IPv6 TCP support (NEW)
│   ├── ipv4_pmtud.asm        # PMTUD (NEW)
│   ├── tcp_bbrv2.asm         # BBRv2 (NEW)
│   ├── tcp_syncookie.asm     # SYN cookies (NEW)
│   ├── tcp_ecn.asm           # ECN (NEW)
│   ├── tcp_ao.asm            # TCP-AO (NEW)
│   ├── tcp_fastopen.asm      # Fast Open (NEW)
│   ├── tcp_cubic.asm         # CUBIC congestion control
│   ├── mptcp.asm             # MPTCP stub
│   ├── utcp_netif.asm        # Network interface abstraction
│   ├── utcp_example.asm      # Unikernel example
│   └── avx512_checksum.asm   # AVX-512 checksum (NEW)
├── tests/
│   ├── test_checksum.c       # Checksum unit tests
│   ├── test_packets.c        # Packet parsing/building tests
│   ├── test_batch.c          # Batch API tests (NEW)
│   ├── test_avx512_checksum.c # AVX-512 checksum tests (NEW)
│   └── run_tests.sh          # Test runner script
├── unet/                     # tattvaos/unet integration
│   ├── unet.asm              # Master network stack
│   └── core/l3/ipv6_tcp.asm  # IPv6 TCP support
└── Makefile / run_tests.sh
```

## Key Design Principles

1. **Zero-Copy Throughout** - No memcpy in fast path; buffer references only
2. **Batch Processing** - Process packets in vectors (like DPDK/XDP)
3. **Lock-Free Data Structures** - Per-CPU queues, RCU for shared state
4. **Cache-Friendly Layout** - Hot data in same cache line, cold data separated
5. **SIMD-Accelerated** - AVX2/NEON for checksum, CRC, crypto
6. **Deterministic Latency** - No allocations in fast path, bounded worst-case
7. **Protocol Composability** - Layer violations only where performance demands

## Building

```bash
# Requires: nasm, gcc (or clang)
make

# Run tests
make test
# or
./run_tests.sh
```

## Usage

### From Assembly
```nasm
%include "utcp.inc"

section .data
my_packet: times 1500 db 0

section .text
extern eth_hdr_init, ipv4_hdr_init, udp_hdr_init, udp_fill_checksum

; Build UDP packet
mov rdi, my_packet
mov rsi, dst_mac
mov rdx, src_mac
mov rcx, ETH_P_IP
call eth_hdr_init

mov rdi, my_packet + 14
mov rsi, 64
mov rdx, IPPROTO_UDP
mov rcx, 0xc0a80001  ; src IP
mov r8,  0xc0a800c8  ; dst IP
mov r9,  8           ; payload len
call ipv4_hdr_init
call ipv4_hdr_fill_checksum

mov rdi, my_packet + 34
mov rsi, 1234
mov rdx, 53
mov rcx, 8
call udp_hdr_init

; ... copy payload ...

mov rdi, my_packet + 34
mov rsi, 0xc0a80001
mov rdx, 0xc0a800c8
mov rcx, 16
mov r8, payload_ptr
mov r9, 8
push byte 1
call udp_fill_checksum
```

### From C
```c
#include "utcp.h"

uint8_t packet[1500];
struct eth_hdr *eth = (struct eth_hdr*)packet;
struct ipv4_hdr *ip = (struct ipv4_hdr*)(packet + 14);
struct udp_hdr *udp = (struct udp_hdr*)(packet + 34);

eth_hdr_init(eth, dst_mac, src_mac, ETH_P_IP);
ipv4_hdr_init(ip, 64, IPPROTO_UDP, src_ip, dst_ip, 8);
ipv4_hdr_fill_checksum(ip);
udp_hdr_init(udp, 1234, 53, 8);
memcpy((uint8_t*)udp + 8, payload, 8);
udp_fill_checksum(udp, src_ip, dst_ip, 16, payload, 8);
```

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| RX throughput | > 10M pps | 64B pkts, 1 core |
| TX throughput | > 15M pps | 64B pkts, 1 core |
| TCP throughput | > 40 Gbps | 1500B MTU, 1 flow |
| TCP latency (RTT) | < 5 µs | Loopback, no NIC |
| Connection setup | < 2 µs | SYN→SYN-ACK→ACK |
| Memory/connection | < 2 KB | TCB + buffers |

## Roadmap

### Phase 1: Core (Current)
- ✅ Checksum (scalar + AVX-512)
- ✅ Ethernet, IPv4, UDP, TCP headers
- ✅ Packet buffer pool
- ✅ Batch RX/TX API
- ✅ Timer wheel

### Phase 2: TCP Complete
- ✅ TCB with lock-free send/recv rings
- ✅ Retransmission queue (RB-tree by seq)
- ✅ CUBIC congestion control
- ✅ SACK processing
- ✅ Fast retransmit/recovery

### Phase 3: IPv6 & Performance
- ✅ IPv6 dual stack
- ✅ AVX-512 checksum
- ✅ TSO/LRO support
- ✅ RSS/RFS flow steering

### Phase 4: Advanced
- ✅ BBRv2
- ✅ SYN Cookies
- ✅ ECN
- ✅ PMTUD
- ✅ TCP Fast Open
- ✅ TCP-AO

### Phase 5: Hardening
- [ ] Fuzzing all parsers
- [ ] Formal verification (TCP state)
- [ ] Certification (DO-178C, ISO 26262)

## License

0BSD - Public domain equivalent. Use freely in any project.

## Acknowledgments

- Inspired by smoltcp, lwIP, DPDK, XDP, Linux kernel TCP
- Built for TattvaOS unikernel OS
- Designed for bare-metal, unikernel, and embedded deployment