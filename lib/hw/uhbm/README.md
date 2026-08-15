# lib/hw/uhbm — HBM / Bandwidth-Tier Memory Layout

> Real per-node-pair bandwidth figures from ACPI HMAT, used to tell
> high-bandwidth memory (HBM) tiers apart from ordinary DDR nodes.

| File | Covers |
|---|---|
| [`layout.asm`](layout.asm) | HMAT Type-1 (System Locality Latency/Bandwidth) parse; node-pair bandwidth queries; relative HBM-tier classification |

## Why HMAT, not SRAT/SLIT

`lib/mem/numa` already gives node topology (SRAT) and a relative distance
byte per node pair (SLIT) — but SLIT's distance is an abstract cost
number, not a real MB/s figure, so it can't tell a DDR node from an HBM
node on its own. ACPI HMAT is the table that actually reports bandwidth
(and latency, not parsed here — nothing downstream needs it yet).

`layout.asm` reuses the HMAT physical address `numa_detect_init` now
locates during its existing RSDP → XSDT/RSDT walk (`numa_hmat_phys_addr`,
added alongside the SRAT/SLIT export `lib/hw/unuma` already uses) instead
of walking those tables a third time. Must run after `numa_detect_init`.

## Classification is relative, not absolute

`uhbm_is_high_bandwidth_node` has no fixed "this is HBM" flag to key off
— HMAT doesn't provide one. It flags a node as high-bandwidth when its
best recorded incoming bandwidth is at least 4x the system's lowest
recorded non-zero bandwidth. DDR5 vs. HBM3 commonly differs by an order
of magnitude, so a 4x threshold has margin against ordinary DDR
channel-count/speed variation between nodes on the same system, without
hardcoding a specific MB/s cutoff that would need updating as memory
technologies change.

Part of the `lib/` category in Tattva OS.
