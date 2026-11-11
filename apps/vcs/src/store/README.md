# src/store

Object store on UXFS: repository metadata, snapshots, refs and atomic ownership
transfers. There is no tracing garbage collector.

Implemented in `repository.asm`, `object_store.asm`, `chunk_pipeline.asm`, `file_object.asm`, `ownership.asm`,
`history.asm`, `stage.asm`, `refs.asm`, `worktree.asm`, and `identity.asm`: UXFS initialization, repository
discovery, full-file snapshot manifests, unchanged blob reuse, status comparison,
selective persistent staging, branches/tags, forced checkout, transactional
commit, SHA-256 integrity records/checking, immutable repository identities,
Ed25519 signature sidecars, and newest-first log. Private seeds are supplied as
explicit 32-byte files and are never stored inside `.vcs`. See `include/repository.inc` and the
storage specification.

`object_store.asm` implements the scalable v3 chunk primitive independently of
the pending allocator ABI: domain-separated SHA-256 IDs, checksummed envelopes,
explicit-locator extent images, complete read verification and atomic bounded
copy-out. The caller owns allocation and durable publication; the codec never
guesses physical locators or publishes a partial object.

`chunk_pipeline.asm` feeds the content-defined chunker into that codec for a
complete caller-bounded file. It emits ordered source ranges, reuses existing or
earlier chunks only after full ID, length and byte comparison, rejects collision
candidates, and writes genuinely new objects into caller-provided allocation
slots. Failed plans leave result counters unpublished so their staging buffers
can be discarded by the owning transaction.

`file_object.asm` converts ordered chunks into reverse-hashed canonical file
pages and a file root, including the domain-separated reconstructed-byte hash.
Its reader validates resolved page and chunk records, every complete object ID,
chain index, link, length and byte total before atomically copying reconstructed
data to the caller.

`ownership.asm` derives exact immutable dependency edges only after full file
verification, validates strict catalog ordering and duplicate exclusion, and
provides the explicit reclamation proof. An object is reclaimable only when its
validated catalog has no inbound edge and the caller reports no active reader
pin; transaction and migration pins remain ordinary durable owner edges.

The older segment/WAL modules remain scaffolding and are excluded from the
native build. The old GC scaffold was removed. UXFS provides the atomic volume
transaction; object removal must be an explicit operation that proves no live
ref, manifest, or integrity record owns the object before freeing its record.
