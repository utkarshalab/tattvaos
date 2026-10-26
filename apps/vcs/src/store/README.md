# src/store

Object store on UXFS: repository metadata, snapshots, refs and atomic ownership
transfers. There is no tracing garbage collector.

Implemented in `repository.asm`, `history.asm`, `stage.asm`, `refs.asm`,
`worktree.asm`, and `identity.asm`: UXFS initialization, repository
discovery, full-file snapshot manifests, unchanged blob reuse, status comparison,
selective persistent staging, branches/tags, forced checkout, transactional
commit, SHA-256 integrity records/checking, immutable repository identities,
Ed25519 signature sidecars, and newest-first log. Private seeds are supplied as
explicit 32-byte files and are never stored inside `.vcs`. See `include/repository.inc` and the
storage specification. The history addition is awaiting build/test validation.

The older chunk/segment/WAL modules remain scaffolding and are excluded from the
native build. The old GC scaffold was removed. UXFS provides the atomic volume
transaction; object removal must be an explicit operation that proves no live
ref, manifest, or integrity record owns the object before freeing its record.
