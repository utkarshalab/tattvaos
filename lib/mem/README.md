# lib/mem — kernel memory

The memory subsystem owns E820 validation, physical-page allocation, NUMA
bookkeeping, page tables, and the higher-level heap/arena/slab allocators.

## Physical-memory contract

- The loaders provide a contiguous identity mapping for `[0, 4 GiB)`.
- During early kernel initialization, canonical usable E820 extents above
  4 GiB are mapped sparsely at `PA == VA`, verified leaf by leaf, and only
  then published to the physical allocator.
- The sparse identity window ends at the lower of the CPU's `MAXPHYADDR`
  ceiling and 512 GiB. The 512 GiB boundary is reserved for existing kernel
  virtual windows; `direct_map_limit` therefore remains 4 GiB and means only
  the guaranteed contiguous aperture.
- Firmware holes and undescribed gaps above 4 GiB stay unmapped. Allocation
  ownership is tracked separately from occupancy, so double frees and attempts
  to free permanent metadata are rejected before memory is zeroed.
- Occupancy and ownership bitmaps use qword-rounded storage. If metadata for
  the candidate sparse span cannot fit in mapped low usable RAM, initialization
  falls back to a low-only bitmap and leaves all high RAM offline.
- NUMA topology becomes allocator authority only when a checksum-valid,
  structurally bounded SRAT covers every PMM-managed E820 page exactly once.
  Early ACPI discovery dereferences only complete tables inside the guaranteed
  low direct map; inaccessible or partial firmware topology falls back to UMA.

This is deliberately not petabyte-scale yet: the current metadata is flat and
the mapping is identity-based. Scaling beyond 512 GiB requires chunked or
extent-based metadata plus a collision-free high-half direct map (and likely
LA57 for larger virtual layouts), rather than more hard-coded RAM tiers.

The high-memory BIOS, OVMF, NMI-recovery, metadata-fallback, edge, and two-node
SRAT/SLIT harnesses require mapping and read/write/free milestones. Native tests
reject wrapped/overlapping E820 maps plus inaccessible, corrupt, overlapping,
partial, truncated, or overflowing ACPI NUMA topology.
