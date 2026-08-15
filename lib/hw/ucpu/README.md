# lib/hw/ucpu — CPU Hardware Layer

> CPU topology, feature detection, and cache-control access for Tattva OS.

| File | Covers |
|---|---|
| [`mtrr.asm`](mtrr.asm) | Memory Type Range Registers — per-range cache policy (UC/WC/WT/WP/WB) |
| [`pat.asm`](pat.asm) | Page Attribute Table — page-level cache policy, PAT MSR |
| [`topology.asm`](topology.asm) | SMT/core/package decode via CPUID leaf 0x1F/0x0B; cache hierarchy via leaf 0x04 |
| [`pinning.asm`](pinning.asm) | SMT-sibling and LLC-domain queries, package affinity-mask construction |

`topology.asm` decodes the *currently executing* logical processor on each
core's own init path (`ucpu_topology_decode_current`, called after
`percpu_init` so `gs:percpu_t.cpu_id` is live) and records it into a table
indexed by `cpu_id`. `pinning.asm` builds on that table only — it has no
NUMA or scheduler dependency. Combine it with `lib/hw/unuma` for
memory-aware placement and with `kernel/sched` for the actual context
switch.

`ucpu_share_llc` is a package-granularity approximation: correct when a
socket has one shared last-level cache domain, imprecise on multi-die/CCX
parts where distinct clusters within a package have separate LLCs. Fixing
that needs the leaf 0x1F Module/Tile levels, which `topology.asm` doesn't
currently decode (it stops at SMT/Core/Package).

Part of the `lib/` category in Tattva OS.
