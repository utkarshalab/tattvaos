# lib/hw/unuma — NUMA Topology & Affinity

> Real, SRAT-derived CPU-to-node mapping and the placement decisions built
> on top of it. Complements `lib/mem/numa`, does not duplicate it.

| File | Covers |
|---|---|
| [`detect.asm`](detect.asm) | ACPI SRAT Type 0/2 (Processor APIC/x2APIC Affinity) parse: `apic_id -> node_id` |
| [`affinity.asm`](affinity.asm) | Locality checks for the currently executing core |
| [`distance.asm`](distance.asm) | CPU-granularity distance queries, and best-node selection for the current core |

## Why this exists next to lib/mem/numa

`lib/mem/numa/numa_detect.asm` already parses SRAT Memory Affinity (Type 1)
entries and SLIT into `numa_ranges`/`numa_distance_matrix`, and
`lib/mem/numa/numa.asm` already answers `numa_get_node_by_phys` /
`numa_get_distance` against that data. None of it touches SRAT's
*Processor* Affinity entries (Type 0 / Type 2), so nothing in the tree had
real firmware data for "which node is this CPU core on" — the closest
existing thing, `lib/mem/virt/rt_safe/sched_affinity.asm`'s `cpu_to_node`
table, is a hardcoded placeholder (its own comment: "Initialize default
CPU-to-Node mapping: CPUs 0-7 mapped to Node 0, CPUs 8-15 mapped to Node
1"). `detect.asm` fills that specific gap.

`detect.asm` reuses the SRAT physical address `numa_detect_init` already
locates (exported as `numa_srat_phys_addr`) instead of re-walking
RSDP → XSDT/RSDT itself, so it must run after `numa_detect_init`.

## Scope note

`affinity.asm` and `distance.asm` are deliberately scoped to the
*currently executing* core (`gs:percpu_t.lapic_id`). Kernel-owned SMP now
gives every online AP a private `percpu_t` and records its firmware APIC ID.
There is still no exported cross-core placement API over that topology, so a
multi-core "closest free CPU for this address" query remains a later scheduler
integration point.

Part of the `lib/` category in Tattva OS.
