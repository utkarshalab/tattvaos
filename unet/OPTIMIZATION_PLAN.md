# TattvaOS/unet - Optimization & Completion Plan

## Current State Assessment

| Component | Status | Gap |
|-----------|--------|-----|
| **Packet Buffer (net_pkt_t)** | ✅ Working | Per-CPU cache, size classes, hugepages |
| **DMA Ring (net_ring)** | ✅ Lockless SPSC | MPMC for multi-queue NICs |
| **RSS/Steering** | ✅ Basic Toeplitz | AVX2/AVX-512 acceleration |
| **Timer Wheel** | ✅ Hierarchical | Not integrated with TCP |
| **TCP State Machine** | ✅ Basic RFC 793 | **No retransmission, no SACK, no OOO** |
| **BBR v2** | 🔧 Stub only | Not wired to TCP |
| **IPv6** | ✅ Parsing | Not fully integrated |
| **HTTP/1.1, TLS, QUIC** | ✅ Higher layers | Depend on TCP completeness |
| **Drivers** | ✅ Many (e1000, virtio, ixgbe, mlx5) | Need multi-queue RSS support |

---

## Phase 1: Critical TCP Completeness (Week 1-2)

### 1.1 TCP Timer Wheel Integration
**File:** `unet/core/l4/tcp.asm` → new `tcp_timer.asm`

```asm
; Per-TCB timer entry embedded in TCB
; Timer wheel callbacks: retransmit, persist, keepalive, TIME_WAIT
; RTO calculation: srtt + 4*rttvar (RFC 6298)
```

### 1.2 Retransmission Queue
**Data Structure:** Per-TCB RB-tree keyed by sequence number
- Insert on send, remove on ACK
- Retransmit head on RTO expiry
- Fast retransmit on 3 DUPACKs

### 1.3 SACK Processing (RFC 2018)
- Parse SACK blocks from incoming ACKs
- Update TCB.sack_blocks[]
- Selective retransmission of only missing segments

### 1.4 Out-of-Order Reassembly Queue
- Per-TCB segment queue (RB-tree by seq)
- Deliver in-order to socket rx queue
- Generate ACK for each new segment

---

## Phase 2: Performance Optimization (Week 2-3)

### 2.1 Per-CPU Packet Cache
```asm
; pktbuf.asm: Add per-CPU cache layer
; struct per_cpu_pkt_cache { net_pkt_t* cache[64]; int count; }
; Batch refill from global slab when empty
```

### 2.2 Batch RX/TX API
```asm
; net_ring.asm: Extend to batch enqueue/dequeue
; net_ring_enqueue_batch(ring, pkts[], count)
; net_ring_dequeue_batch(ring, pkts[], max_count)
```

### 2.3 AVX-512 Checksum
```asm
; tcp_checksum_calc: AVX-512 vectorized
; ip_checksum_calc: AVX-512 (already in avx512_parser.asm?)
```

### 2.4 Zero-Copy TX Path
- Eliminate header copies in `tcp_send_data`
- Build headers directly in packet headroom
- Use `net_pkt_t.next_pkt` for SG lists

---

## Phase 3: Advanced Features (Week 3-4)

### 3.1 Full BBR v2 Integration
- Wire `bbr_update_sample` to ACK processing
- Wire `bbr_calculate_pacing` to send path
- Implement pacing timer (separate from RTO)

### 3.2 Window Scaling (RFC 7323)
- Negotiate in SYN/SYN-ACK
- Apply scale to advertised window
- Handle 32-bit window internally

### 3.3 TCP Timestamps (RFC 7323)
- Enable per-connection
- Use for RTT measurement (PAWS)

### 3.4 Multi-Queue NIC Support
- RSS indirection table configuration
- Per-queue net_ring + per-CPU polling
- Flow-to-queue affinity

---

## Phase 4: Hardening (Week 4+)

### 4.1 Fuzzing All Parsers
- Ethernet, IPv4, IPv6, TCP, UDP, ICMP
- TLS record layer, HTTP/2 frames

### 4.2 Formal Verification
- TCP state machine (TLA+)
- Timer wheel correctness

### 4.3 Documentation & Testing
- Architecture diagrams
- Integration tests (iperf3, netperf)

---

## Immediate Implementation Priority

### TODAY: TCP Timer + Retransmission
This is the **single biggest gap** - without it, packet loss = connection death.

### Implementation Approach:
1. Create `tcp_timer.asm` with per-TCB timer entries
2. Integrate with `lib/time/timer_wheel.asm`
3. Add retransmission queue (RB-tree by seq)
4. Implement `tcp_timer_tick` to process expired timers
5. Add fast retransmit on 3 DUPACKs

Let me start implementing the critical pieces now.