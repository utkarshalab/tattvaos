# lib/hw/uhwloc — Unified Hardware Locality

> Combined queries over ucpu, unuma, uhbm, ugpu, and ucxl — the single
> place that ties the rest of `lib/hw` together, built last since it
> depends on every other subsystem.

| File | Covers |
|---|---|
| [`hwloc.asm`](hwloc.asm) | `uhwloc_current_locality` (topology + NUMA node + bandwidth tier for the running core in one call), `uhwloc_summary` (device/topology counts across every subsystem, for a boot-time report) |

## Why "combined," not "complete"

This does not attempt GPU-to-NUMA-node or CXL-to-NUMA-node locality
(e.g. "which node is this GPU physically closest to"). ACPI exposes that
through each PCI device's `_PXM` object in the DSDT, which needs a
general AML interpreter to evaluate — a different order of complexity
than the fixed-table parsers (SRAT/SLIT/HMAT) everything else in
`lib/hw` is. `uhwloc` combines what the other subsystems already expose;
it doesn't add new discovery of its own.

Part of the `lib/` category in Tattva OS.
