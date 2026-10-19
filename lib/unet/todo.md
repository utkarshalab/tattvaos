# lib/unet — Tier 6 Data Center Production Grade Roadmap

**Location:** `lib/unet/`  
**Target:** Hyperscale / Tier 6 corporate data center fabric  
**Language:** x86-64 NASM assembly only  
**Deployment:** Bare-metal unikernel, ring 0 only, no syscall boundary  
**ABI:** System V x86-64 internal register convention  
**NO C / NO RUST / NO FFI in production binary** — pure assembly for pure speed  
**Test harnesses may use C only for running tests; never shipped in production.**

---

## How to use this file

- `[ ]` = not started  
- `[/]` = partial / stub exists  
- `[x]` = done  
- **P0** = Blocker. Fabric cannot go live without it.  
- **P1** = Required for production DC (multi-tenant, lossless, high-speed).  
- **P2** = Important for scale and ops (observability, HA, security hardening).  
- **P3** = Future / suggestion (next-gen offload, research).

Register convention: `RDI`=arg1, `RSI`=arg2, `RDX`=arg3, `RCX`=arg4, `R8`=arg5, `R9`=arg6, `RAX`=return.  
Callee-saved: `RBX`, `RBP`, `R12`, `R13`, `R14`, `R15`.

---

## Phase 0 — Build & Release Infrastructure (Corporate Grade)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-001 | P0 | [ ] | `lib/unet/Makefile` | Replace stub Makefile. Full NASM build: assemble `unet.asm` + all `%include`d modules into a single relocatable object / ELF for the unikernel. `ROOT := ../..`. Outputs: `build/unet.o`, `build/unet.elf`, `build/unet.map`. |
| DC-002 | P0 | [ ] | Root build system | Add `lib/unet/` to corporate build order: after `lib/time/`, before `kernel/`. Parallel build via `make -j`. |
| DC-003 | P0 | [ ] | `lib/unet/unet.asm` | Fix all `%include "unet/..."` paths → `lib/unet/...` or pass `-I$(ROOT)/lib/unet` to NASM. Verify after move from root `unet/`. |
| DC-004 | P1 | [ ] | `lib/unet/run_tests.sh` | Corporate test runner: NASM unit tests + C harness only for test binaries (not shipped). Exit codes for CI gating. |
| DC-005 | P1 | [ ] | `lib/unet/` | Deterministic / reproducible builds: embed git SHA + build timestamp into `unet_build_id` symbol for telemetry correlation across fleet. Same source → same binary. |
| DC-006 | P1 | [ ] | `lib/unet/` | Conditional build flags: `%ifdef DC_MINIMAL` (TCP/IP only), `%ifdef DC_FULL` (all domains), `%ifdef DC_RDMA` (RoCE/InfiniBand), `%ifdef DC_NO_PQC` (disable post-quantum for legacy hardware). |
| DC-007 | P2 | [ ] | `scripts/` | Corporate CI pipeline: build on x86-64 NASM, run unit tests, run fuzzers (1 hr), run benchmarks (iperf3, netperf, pktgen), publish artifacts, gate on p99 latency regression. |
| DC-008 | P3 | [ ] | `lib/unet/` | SBOM generation: list every `.asm` file, author, last modified, security review status for compliance audits. |

---

## Phase 1 — Core L2 / L3 / L4 (DC Foundation)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-101 | P0 | [/] | `lib/unet/core/l2/eth.asm`, `arp.asm`, `mac.asm` | Ethernet II, 802.1Q VLAN, 802.1ad QinQ. ARP with ACD, gratuitous ARP, ARP cache with timeout + GC. Gratuitous ARP on IP change for fast failover. |
| DC-102 | P0 | [/] | `lib/unet/core/l3/ip.asm`, `ipv6_tcp.asm`, `icmp.asm`, `igmp.asm` | IPv4 (RFC 791), IPv6 (RFC 8200) dual-stack. ICMPv4/v6. IGMP v1/v2/v3 / MLD v1/v2. IP options: drop or log source-route / record-route (security). |
| DC-103 | P0 | [/] | `lib/unet/core/l4/udp.asm`, `tcp.asm` | UDP (RFC 768) checksum validation. TCP (RFC 793) 11-state FSM. Socket table: 65,536+ entries, hash by 4-tuple, per-VRF isolation. |
| DC-104 | P0 | [ ] | `lib/unet/core/l4/tcp_timer.asm` *(create)* | Timer wheel integration per-TCB: retransmit, persist, keepalive, TIME_WAIT (2×MSL=60s), delayed ACK (40ms). Hierarchical wheel: TVR 256×1ms, TVN1-3 64×256ms… up to 18 hours. O(1) insert/delete/cascade. |
| DC-105 | P0 | [ ] | `lib/unet/core/l4/tcp.asm` | Retransmission queue (per-TCB, ordered by seq, RB-tree or array). Refcounted `net_pkt_t*`. RTO per RFC 6298: `srtt`, `rttvar`, `RTO = srtt + 4×rttvar`, clamp 200ms–60s, exponential backoff ×2. |
| DC-106 | P0 | [ ] | `lib/unet/core/l4/tcp_ooo.asm` *(create)* | Out-of-order reassembly queue per TCB. Deduplication, overlap handling, in-order delivery to socket RX queue, ACK per new segment. FIN handling. Dedicated slab `ooo_segment_cache`. |
| DC-107 | P0 | [ ] | `lib/unet/core/l4/tcp_fastopen.asm` *(create)* | TCP Fast Open (RFC 7413): TFO cookie generation/validation (SipHash or AES-based), data-in-SYN, fallback on middlebox interference. |
| DC-108 | P1 | [ ] | `lib/unet/core/l4/tcp_syncookie.asm` | SYN Cookies (RFC 6528/4987): SipHash-2-4 cookie, 32-bit (3-bit MSS index + 29-bit hash), 128-bit secret from RDRAND/fallback, backlog-full fallback. |
| DC-109 | P1 | [ ] | `lib/unet/core/l4/tcp_ecn.asm` | ECN state machine (RFC 3168/8311): DISABLED→REQUESTED→NEGOTIATED/DISABLED_PEER. ECT(0)/ECT(1)/CE in IP TOS. ECE/CWR TCP flags. CE → cwnd reduction. |
| DC-110 | P1 | [ ] | `lib/unet/core/l3/ipv4_pmtud.asm` | PMTUD / PLPMTUD (RFC 1191/4821/8899): DF bit, ICMP "frag needed", binary search probing, max 3 probes, 1024-bucket hash, 10 min aging. IPv6 PMTUD too. |
| DC-111 | P2 | [ ] | `lib/unet/core/l3/igmp.asm` / `mld.asm` *(create)* | IGMP v3 / MLD v2 for IPv4/IPv6 multicast group membership. Required for DC multicast/anycast. |
| DC-112 | P2 | [ ] | `lib/unet/core/l4/tcp_tls.asm` *(create)* | Native TLS record framing inside TCP (not KTLS yet): TLS 1.3 record layer assembly, AEAD (AES-GCM, ChaCha20-Poly1305), record sequence numbers. |

---

## Phase 2 — DC Transport & Congestion Control (Lossless Fabric)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-201 | P0 | [/] | `lib/unet/core/l4/tcp_cubic.asm` | CUBIC (RFC 8312) wired to TCP `cc_ops`. Cubic window: `W(t) = C×(t−K)³ + W_max`. Fixed-point cubic root. Fast convergence. β=0.7. |
| DC-202 | P0 | [/] | `lib/unet/core/l4/tcp_bbrv2.asm` | BBRv2 (RFC 9402) fully wired: `bbr_update_sample` on ACK, `bbr_calculate_pacing` on send, separate pacing timer (distinct from RTO). Delivery rate: `max_bw = max(delivered/elapsed)`. |
| DC-203 | P0 | [ ] | `lib/unet/core/l4/dctcp.asm` *(create)* | **DCTCP (RFC 8258)** for ECN-based DC: ECN marking fraction `α`, `cwnd` reduction proportional to marked bytes. Required for lossless RoCE/DC fabrics. |
| DC-204 | P0 | [ ] | `lib/unet/core/l4/dcqcn.asm` *(create)* | **DCQCN (RFC 7307-style)** for RoCEv2 lossless Ethernet: CNP generation, rate limiter per flow, AI/AE algorithms, hysteresis, time threshold. |
| DC-205 | P1 | [ ] | `lib/unet/core/l4/tcp_rack.asm` *(create)* | RACK (RFC 8960): time-based loss detection, `rack_no_retrans`, `rack_reo_wnd`. Reduces spurious retransmissions on ACK loss / reordering. |
| DC-206 | P1 | [ ] | `lib/unet/core/l4/tcp_ao.asm` *(create)* | TCP-AO (RFC 5925): MAC authentication option over TCP segments. Key chain integration from `crypto/ucrypt/`. |
| DC-207 | P2 | [/] | `lib/unet/core/l4/mptcp.asm` | MPTCP (RFC 8684): subflow management, ADD_ADDR/REMOVE_ADDR, DSS (Data Sequence Signal), path manager, fallback to regular TCP. |
| DC-208 | P2 | [ ] | `lib/unet/core/l4/sctp.asm` | SCTP (RFC 4960): multi-homing, multi-streaming, partial reliability. For signaling/control plane in DC. |
| DC-209 | P2 | [/] | `lib/unet/core/l4/quic.asm` | QUIC over UDP: connection IDs, packet number encryption, streams, flow control, loss recovery, congestion control. Foundation for HTTP/3. |
| DC-210 | P3 | [ ] | `lib/unet/core/l4/pcc.asm` *(create)* | PCC (Pragmatic Congestion Control): model-based, loss-delay based, for incast-heavy DC storage traffic. |

---

## Phase 3 — RDMA & Storage Fabric (Tier 6 DC Storage Network)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-301 | P0 | [ ] | `lib/unet/hpc/roce.asm` | **RoCEv2 (RDMA over Converged Ethernet, UDP port 4791)**: UD QP creation, send/recv/write/read/atomic ops, MR registration, rkey/lkey handling. |
| DC-302 | P0 | [ ] | `lib/unet/hpc/infiniband.asm` | InfiniBand verbs subset: QP, CQ, SRQ, MR, MW, PD. Send/Receive queues, work completion polling. |
| DC-303 | P0 | [ ] | `lib/unet/hpc/mpi_collectives.asm` | MPI collectives (AllReduce, Broadcast, Gather, Scatter, Reduce-Scatter, AlltoAll) in assembly over RoCE/IB. Ring/tree algorithms. |
| DC-304 | P0 | [ ] | `lib/unet/hpc/gpudirect.asm` | GPUDirect RDMA: register GPU memory (CUDA/IPC) for direct NIC DMA without CPU copy. Zero-copy GPU→NIC. |
| DC-305 | P0 | [ ] | `lib/unet/hpc/rdma_cm.asm` | RDMA Connection Manager: address resolution, route resolution, QP creation handshake, QoS class. |
| DC-306 | P1 | [ ] | `lib/unet/hpc/slingshot.asm` | Cray Slingshot / proprietary fabric support (if hardware present). |
| DC-307 | P1 | [ ] | `lib/unet/san/nvme_of_rdma.asm` | **NVMe-oF over RDMA**: submission/completion queues, admin commands, I/O commands, namespace discovery. |
| DC-308 | P1 | [ ] | `lib/unet/san/nvme_of_tcp.asm` | NVMe-oF over TCP (fallback when RDMA unavailable). |
| DC-309 | P1 | [ ] | `lib/unet/san/iscsi.asm` | iSCSI (RFC 3720): CHAP auth, login, PDU sequencing, data-in/out. |
| DC-310 | P2 | [ ] | `lib/unet/san/fcoe.asm` / `fip.asm` | FCoE / FCoE Initialization Protocol for SAN consolidation. |

---

## Phase 4 — Hardware Acceleration & Offload (SmartNIC / DPU / ASIC)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-401 | P0 | [ ] | `lib/unet/core/link/net_ring.asm` | **Lock-free MPMC rings** for multi-queue NICs. Sequence-lock or `LOCK CMPXCHG16B`. Per-queue RX/TX rings pinned to CPU cores. |
| DC-402 | P0 | [ ] | `lib/unet/core/link/rss.asm` | **RSS (Receive Side Scaling)**: Toeplitz hash over 5-tuple, indirection table programming, flow→queue affinity, per-CPU polling. |
| DC-403 | P0 | [ ] | `lib/unet/core/sys/pktbuf.asm` | **Per-CPU packet slab allocator**: `per_cpu_pkt_cache[64]`, batch refill from global slab. No cross-core cache-line bouncing on `net_pkt_t` alloc/free. |
| DC-404 | P0 | [ ] | `lib/unet/core/sys/avx512_checksum.asm` | AVX-512 vectorized checksum: TCP/UDP/IP with pseudo-header. `VPADDD`/`VPADDQ`, carry folding with `VPSHUFD`/`VEXTRACTI32x4`. |
| DC-405 | P0 | [ ] | `lib/unet/core/sys/avx512_parser.asm` | Vectorized header parse: Ethernet/IPv4/TCP header fields via `VPCMPB`/`VPCMPEQB`. Extract 5-tuple into ZMM registers for flow lookup. |
| DC-406 | P0 | [ ] | `lib/unet/core/l4/tcp.asm` | **Zero-copy TX path**: headers built directly in `net_pkt_t` headroom. `net_pkt_t.next_pkt` scatter-gather lists. No `memcpy` from user buffer to packet. |
| DC-407 | P1 | [ ] | `lib/unet/core/l4/tcp.asm` | **Software TSO/LSO**: If NIC lacks TSO, segment large user buffer into multiple `net_pkt_t` with correct TCP seq numbers in fast path. |
| DC-408 | P1 | [ ] | `lib/unet/core/l3/ip.asm` | **TSO/LRO offload coordination**: negotiate with NIC via ethtool-like interface; build segmentation headers if NIC offloads. |
| DC-409 | P1 | [ ] | `lib/unet/core/link/net_link.asm` | **Doorbell batching**: accumulate TX completions, ring NIC doorbell once per 32 packets or 2µs threshold. |
| DC-410 | P1 | [ ] | `lib/unet/core/link/net_link.asm` | **Interrupt mitigation / NAPI-style polling**: busy-poll RX ring for budget, then sleep. Eliminate interrupt storms at >10M pps. |
| DC-411 | P1 | [ ] | `lib/unet/core/link/net_link.asm` | **Prefetch**: `PREFETCHNTA` on incoming `net_pkt_t` descriptors and payloads before parser touches them. |
| DC-412 | P2 | [ ] | `lib/unet/core/link/net_link.asm` | **Huge pages**: allocate packet pools + descriptor rings on 2 MB / 1 GB huge pages. Integrate with `kernel/mm/huge.asm`. |
| DC-413 | P2 | [ ] | `lib/unet/core/link/net_link.asm` | **NUMA-aware allocation**: packet buffers on same NUMA node as NIC (`kernel/mm/numa.asm`). |
| DC-414 | P2 | [ ] | `lib/unet/drivers/sriov.asm` | **SR-IOV**: enable Virtual Functions, map VF BAR, configure VF queue pairs, PCIe ATS (Address Translation Services). |
| DC-415 | P2 | [ ] | `lib/unet/drivers/` | **DPU / SmartNIC offload**: offload checksum, TCP segmentation, TLS record encryption, firewall rules to programmable NIC/DPU firmware. |
| DC-416 | P2 | [ ] | `lib/unet/ebpf/dpdk.asm` | DPDK poll-mode driver compatibility: mempool, rings, port config, burst RX/TX in pure NASM. |
| DC-417 | P3 | [ ] | `lib/unet/drivers/` | Missing drivers: Intel E810, ConnectX-7/BlueField-3, AMD Pensando, Marvell Prestera, Realtek, USB ethernet (fallback). |
| DC-418 | P3 | [ ] | `lib/unet/drivers/` | **VFIO direct device assignment**: unikernel owns NIC PCI device without hypervisor mediation. |

---

## Phase 5 — Multi-Tenancy & Network Virtualization

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-501 | P1 | [/] | `lib/unet/sdn/vxlan.asm`, `geneve.asm`, `gre.asm`, `ipip.asm`, `nvgre.asm`, `l2tp.asm`, `mpls.asm` | Overlay encapsulation/decapsulation. VXLAN (VNI 24-bit), NVGRE (TSI), Geneve (options), MPLS label stack. |
| DC-502 | P1 | [ ] | `lib/unet/routing/vrf_manager.asm` | **VRF (Virtual Routing and Forwarding)**: multiple independent routing tables per tenant. 4096 VRFs minimum. |
| DC-503 | P1 | [ ] | `lib/unet/routing/netns.asm` | Network namespaces per tenant. Isolation of interfaces, routes, socket tables. |
| DC-504 | P1 | [ ] | `lib/unet/cni/calico.asm`, `cilium.asm`, `flannel.asm`, `kube_proxy.asm`, `weave.asm` | CNI integration: IPAM, pod/container networking, service proxy (kube-proxy userspace). |
| DC-505 | P2 | [ ] | `lib/unet/cgnat/cgnat.asm`, `nat444.asm`, `nat64.asm`, `ds_lite.asm`, `nptv6.asm`, `pcp.asm` | CGNAT for tenant egress. NAT444, NAT64, DS-Lite, NPTv6, PCP port control. |
| DC-506 | P2 | [ ] | `lib/unet/proxy/socks5.asm`, `forward_proxy.asm`, `reverse_proxy.asm` | L4/L7 proxy for tenant traffic steering and observability. |
| DC-507 | P3 | [ ] | `lib/unet/sdn/` | **Segment Routing IPv6 (SRv6)**: SID list processing, endpoint behavior (PSP, USP, DT4/DT6). |

---

## Phase 6 — Security & Zero Trust (Corporate Grade)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-601 | P0 | [/] | `lib/unet/security/tls13_session.asm` | **KTLS (Kernel TLS) zero-copy**: TLS 1.3 record encryption directly from `net_pkt_t` without userspace copy. AES-GCM, ChaCha20-Poly1305. Integrate with TCP send path. |
| DC-602 | P0 | [/] | `lib/unet/security/ipsec.asm` | IPsec (RFC 4301/4303): ESP, AH, IKEv2 (stub), SAD/SP, transport and tunnel mode, AES-GCM, anti-replay window. |
| DC-603 | P1 | [/] | `lib/unet/security/macsec_mon.asm` → `macsec_enc.asm` | **MACsec (IEEE 802.1AE) encryption**: GCM-AES-256 on Ethernet frames. SAK distribution via MKA. Integrate with `eth_output`/`eth_input`. |
| DC-604 | P1 | [/] | `lib/unet/security/wireguard.asm`, `wireguard_blake2s.asm` | WireGuard: Noise IK handshake, ChaCha20-Poly1305, Curve25519, cookie mechanism, roaming. |
| DC-605 | P1 | [/] | `lib/unet/pqc/pqc_wireguard.asm`, `pqc_macsec.asm` | **Post-Quantum**: Kyber KEM + Dilithium signatures for WireGuard/MACsec handshake. Hybrid classical+PQ. |
| DC-606 | P1 | [ ] | `lib/unet/security/firewall.asm`, `ddos.asm` | Stateful firewall: conntrack table (1M+ entries), rate limiting, SYN flood mitigation beyond SYN cookies, L3/L4 ACLs. |
| DC-607 | P1 | [ ] | `lib/unet/security/qkd.asm`, `qrng_entropy.asm` | QKD / QRNG key pipeline: quantum entropy → CSPRNG (`urand/`), key distribution, rotation, zeroization. |
| DC-608 | P2 | [ ] | `lib/unet/security/tpm2.asm` | TPM 2.0: sealed network keys, measured boot, remote attestation for tenant isolation. |
| DC-609 | P2 | [ ] | `lib/unet/security/noise_protocol.asm` | Noise Protocol Framework: IK/XX/NN handshakes, symmetric state, DH over `crypto/ucrypt/asymmetric/`. |
| DC-610 | P2 | [ ] | `lib/unet/ssh/ssh_transport.asm`, `ssh_auth.asm`, `ssh_connection.asm`, `sftp.asm` | SSHv2: transport, auth (password/pubkey/hostbased), connection multiplexing, SFTP. |

---

## Phase 7 — Observability & Telemetry (Corporate Ops)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-701 | P1 | [ ] | `lib/unet/tools/`, `lib/unet/obs/` *(create)* | **Prometheus metrics endpoint**: counters/gauges/histograms exposed over HTTP: `tcp_connections_active`, `rx_packets_total`, `tx_packets_total`, `dropped_packets_total`, `retransmissions_total`, `rto_events_total`, `ecn_ce_events_total`, `cqe_errors_total`, `rdma_write_bytes_total`, `conntrack_entries_total`. |
| DC-702 | P1 | [ ] | `lib/unet/services/ipfix.asm` | **IPFIX / NetFlow v9 / sFlow**: flow records (5-tuple, bytes, packets, timestamps, TCP flags, ECN) exported to collector. Sampling for 100G+ links. |
| DC-703 | P1 | [ ] | `lib/unet/obs/` *(create)* | **Distributed tracing**: W3C traceparent injection/extraction across TCP/QUIC connections. Span IDs in `net_pkt_t` metadata. |
| DC-704 | P1 | [ ] | `lib/unet/security/pattern_matcher.asm` | Deep packet inspection: hyperscan-like multi-pattern matching in assembly (Aho-Corasick or SIMD-accelerated). DLP, malware signature, threat detection. |
| DC-705 | P2 | [ ] | `lib/unet/tools/security/` | **Debug console / kdb**: inspect TCB state, timer wheel, socket tables, ring descriptors, NIC registers without external tools. |
| DC-706 | P2 | [ ] | `lib/unet/tools/route/`, `tools/san/` | Diagnostic tools: `tcpdump`-style capture, `ss`-style socket dump, `netstat`-style routing, `ethtool`-style NIC stats, `rdma` tool. |
| DC-707 | P3 | [ ] | `lib/unet/obs/` | eBPF/XDP JIT in pure NASM: minimal verifier + JIT for programmable packet filtering/observability without kernel. |
| DC-708 | P3 | [ ] | `lib/unet/obs/` | PMU hardware counters: cache misses, branch mispredictions, NIC DMA errors, integrated into metrics. |

---

## Phase 8 — Reliability & High Availability (Five-Nines)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-801 | P1 | [/] | `lib/unet/routing/bgp.asm`, `ospf.asm`, `isis.asm`, `evpn.asm` | BGP (RFC 4271), OSPF, IS-IS, EVPN for DC fabric underlay/overlay. ECMP multipath. Graceful restart. |
| DC-802 | P1 | [/] | `lib/unet/ha/vrrp.asm`, `carp.asm` | VRRP / CARP for default gateway redundancy. Sub-second failover. |
| DC-803 | P1 | [ ] | `lib/unet/routing/pim_dm.asm`, `pim_sm.asm` | PIM-DM / PIM-SM for multicast routing in DC fabric. |
| DC-804 | P1 | [ ] | `lib/unet/core/sys/socket.asm` | **Connection mirroring / checkpointing**: duplicate TCP state to standby node for live migration / graceful restart without dropping flows. |
| DC-805 | P2 | [ ] | `lib/unet/core/sys/epoll.asm` | Epoll/kqueue-style event notification for thousands of concurrent connections per core. |
| DC-806 | P2 | [ ] | `lib/unet/core/sys/batch_rx.asm`, `batch_tx.asm` | Batch RX/TX API: vectorized enqueue/dequeue (DPDK-style), amortize doorbell and lock overhead. |
| DC-807 | P3 | [ ] | `lib/unet/core/l4/tcp.asm` | **TCP connection rate limit**: per-IP/socket connection establishment limiter to prevent SYN flood from exhausting socket table. |

---

## Phase 9 — Traffic Engineering & QoS (DC Fabric)

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-901 | P1 | [/] | `lib/unet/qos/fq_codel.asm`, `tbf.asm`, `slb.asm` | **FQ_Codel**: per-flow queuing, controlled delay, AQM. Token bucket filter (TBF). Strict priority queues. |
| DC-902 | P1 | [ ] | `lib/unet/qos/ebpf_maglev.asm` | Maglev consistent hashing for ECMP / load balancing. |
| DC-903 | P1 | [ ] | `lib/unet/qos/` *(create)* | **PIFO / WFQ**: Push-In First-Out queue for programmable scheduling. Weighted Fair Queueing per tenant. |
| DC-904 | P1 | [ ] | `lib/unet/core/l3/ip.asm` | DSCP / ECN marking and policing. Trust boundary at ingress. |
| DC-905 | P1 | [ ] | `lib/unet/core/l2/eth.asm` | **PFC (Priority Flow Control, IEEE 802.1Qbb)**: lossless Ethernet for RoCEv2. Pause frames per priority. |
| DC-906 | P2 | [ ] | `lib/unet/qos/` | **ETS (Enhanced Transmission Selection, 802.1Qaz)**: bandwidth allocation per priority. |
| DC-907 | P3 | [ ] | `lib/unet/loadbalancer/` *(create)* | L4 load balancer: VIP → RIP, NAT, direct server return (DSR), health checks, active/passive. |

---

## Phase 10 — Production-Grade Hardening (The "Nothing Missed" Layer)

*This phase is what separates a feature list from a production-grade system.*

| ID | Pri | Status | File(s) | Description |
|----|-----|--------|---------|-------------|
| DC-A01 | P0 | [ ] | `lib/unet/tests/` | Unit tests for every parser: Ethernet, IPv4, IPv6, TCP, UDP, ICMP, IGMP, ARP, DHCP, DNS, HTTP. NASM-native test binaries. 100% parser coverage. |
| DC-A02 | P0 | [ ] | `lib/unet/tests/fuzz/` | **Fuzzing harness**: mutation engine feeding raw bytes into every parser entry point. Coverage-guided. Target: malformed headers, truncated packets, oversized lengths, illegal flag combinations, zero-length payloads. |
| DC-A03 | P0 | [ ] | `lib/unet/` | **Memory safety in assembly**: ownership/lifetime annotations (compatible with `asm/safety/` ucheck) for `net_pkt_t` and `socket_t`. Catch use-after-free, double-free, buffer overflow at assembly level. No unchecked pointer arithmetic. |
| DC-A04 | P1 | [ ] | `lib/unet/` | **Formal verification**: TLA+ / PlusCal model for TCP 11-state FSM. Prove: no deadlock, no lost segments, no spurious retransmit, no ACK starvation, no timer wheel corruption. |
| DC-A05 | P1 | [ ] | `lib/unet/bench/` | **Real traffic benchmarks**: iperf3, netperf, pktgen. Sustain 400Gbps per NIC for 72 hours. Measure pps, Gbps, p99 latency, memory/connection (< 1 KB target), RTO events, retransmission rate under loss. |
| DC-A06 | P1 | [ ] | `lib/unet/` | **Baseline comparison**: published numbers vs Linux kernel TCP and DPDK reference. Must meet or exceed p99 tail latency and throughput at same core count. |
| DC-A07 | P1 | [ ] | `scripts/` | **Nightly CI**: build `lib/unet/` x86-64 NASM, run unit tests, fuzzers (1 hr), benchmarks, gate on p99 latency regression. Fail build on any regression. |
| DC-A08 | P1 | [ ] | `lib/unet/` | **Hitless upgrades**: hot-reload congestion control algorithm, firewall rules, QoS policies without dropping existing TCP connections. |
| DC-A09 | P1 | [ ] | `lib/unet/core/sys/socket.asm` | **Graceful shutdown / connection draining**: stop accepting new connections, finish in-flight transactions, then stop. No RST storms on restart. |
| DC-A10 | P1 | [ ] | `lib/unet/core/l4/tcp.asm` | **Connection state persistence**: optional checkpoint of TCB to standby node for live migration. |
| DC-A11 | P2 | [ ] | `lib/unet/` | **Disaster recovery testing**: NIC failure, link flap, PCIe bus error, DMA error, wrong NUMA node, corrupted ring buffer. Verify automatic recovery or safe panic. |
| DC-A12 | P2 | [ ] | `lib/unet/` | **Multi-tenant isolation adversarial testing**: tenant A spoofing tenant B's MAC/IP, VRF route leaks, namespace escape, CGNAT port exhaustion. |
| DC-A13 | P2 | [ ] | `lib/unet/` | **Memory leak detection**: run stack for 72+ hours under load. `net_pkt_t` refcount must return to zero. No socket table growth without bound. |
| DC-A14 | P2 | [ ] | `lib/unet/` | **Watchdog / stall detection**: if `unet_poll` stops advancing timer wheel for > threshold, log and trigger safe recovery. |
| DC-A15 | P2 | [ ] | `lib/unet/` | **Stack overflow / guard pages**: kernel fiber stacks with guard pages. Detect and fatal on overflow rather than silent corruption. |
| DC-A16 | P3 | [ ] | `lib/unet/security/` | **Third-party security audit**: external review of assembly memory management, crypto constant-time guarantees, side-channel resistance. |
| DC-A17 | P3 | [ ] | `lib/unet/` | **Operator runbooks**: build, deploy, tune, debug, upgrade, rollback, incident response for on-call engineers. |

---

## Legend: Dependency Order (Corporate)

```
Phase 0 (Build/CI) 
  → Phase 1 (Core L2/L3/L4) 
    → Phase 2 (DC Congestion) 
      → Phase 3 (RDMA/Storage) 
        → Phase 4 (Hardware Offload) 
          → Phase 5 (Multi-tenancy) 
            → Phase 6 (Security/Zero Trust) 
              → Phase 7 (Observability) 
                → Phase 8 (HA/Reliability) 
                  → Phase 9 (QoS/Traffic Eng) 
                    → Phase 10 (Production Hardening — MUST complete before Tier 6 ship)
```

---

## Ship Criteria (Tier 6 Production Grade)

Before `lib/unet` is declared production-grade for a Tier 6 DC, all **P0** items must be complete, and:

1. Sustained 400Gbps per NIC for 72 hours without stall, crash, or memory growth.
2. p99 latency stable under incast (thousands of simultaneous flows).
3. Every parser fuzzed for ≥1 billion packets with zero crashes.
4. TCP state machine formally verified (TLA+).
5. Hitless upgrade/downgrade tested.
6. Metrics surface alerts that page on-call on retransmission rate spike.
7. Third-party security audit passed.
8. Operator runbooks written and tested.

---

## Notes

- **No C / No Rust / No FFI.** Everything is NASM. C consumers may `extern` against `lib/unet.o` only if absolutely necessary; that is out of scope.
- Every new `.asm` uses the existing header guard: `%ifndef GUARD_... %define GUARD_... ... %endif`.
- All `struc` definitions live in `lib/unet/unet.inc` unless strictly local to one file.
- When adding a protocol domain: add `%include` to `lib/unet/unet.asm`, add its `*_init` call to `unet_init`, add its poll/dispatch to `unet_poll` if needed.
