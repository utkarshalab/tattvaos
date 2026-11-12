# VCS Enterprise Execution Roadmap

This is the canonical implementation order for taking the current bounded VCS
to the enterprise design described in
[`vcs-enterprise-plan-ufs-native.md`](vcs-enterprise-plan-ufs-native.md).
The product plan explains the destination; this file decides what is built next.

## Operating rules

- Production code is pure assembly. Host Python is allowed only for tests and
  reference differentials.
- Utkarsha OS and UXFS are the native platform. Do not add a POSIX compatibility
  layer or a hosted runtime.
- x86-64 and NASM are the active target. AArch64 and RISC-V wait for utasm.
- Memory and storage ownership are explicit. There is no tracing or background
  garbage collector. Reclamation must prove that no live owner remains.
- Every input, output, arena, packet, path, object and collection is bounded.
- On-disk and wire formats are versioned, checksummed and fail closed.
- Preserve Git interoperability without making Git the native object model.
- Do not start a later milestone while an earlier milestone has an unmet exit
  gate, unless the work is an isolated test or documentation dependency.
- Each source file receives its own detailed commit. Run the milestone's focused
  gate before committing and push only explicitly scoped paths.

## Status legend

- `[x]` implemented and covered by the active test gate.
- `[~]` implemented for the current bounded repository but requires enterprise
  scale or fidelity work.
- `[ ]` not implemented in the active production path.
- `[D]` intentionally deferred until its named prerequisite exists.

## Current baseline

The following capabilities are already real, persistent and tested:

- [x] UXFS-backed repository discovery, formatting and recovery.
- [x] Status, staging, snapshot commits, multiline messages, log and diff.
- [x] Checkout, restore, branches, tags and detached history.
- [x] Three-way merge, conflict records, resolve/continue/abort and signed merge.
- [x] Rebase, cherry-pick, revert, stash, bisect and blame.
- [x] Signed identities, trust policy and key revocation.
- [x] Custom bounded sync framing, planning, client/server state and bundles.
- [x] Git protocol-v2 upload serving and SHA-256 PACK generation.
- [x] Bounded Git fast-import/export snapshots with real-Git differentials.
- [x] Deterministic content-defined chunking, exact-capacity preflight and atomic
  output failure.
- [x] Persistent recovery tests and BIOS/OVMF QEMU application gates.

The baseline remains deliberately small: at most 15 tracked files, 4,096 bytes
per file and 64 UXFS records. Removing these limits is the next critical path.

## Milestone 1: Scalable UXFS object storage

**Priority:** P0. **Start here.**

### 1.1 Freeze the scalable object contract

- [x] Confirm the UXFS calls available for transactions, durable flush,
  allocation, snapshots, journal cursors and subtree hashes.
- [x] Replace draft assumptions in `00-ufs-contract.md`, `01-object-model.md`,
  `02-hashing-and-ids.md` and `04-storage-layout.md` with exact layouts and
  result codes.
- [x] Define versioned chunk, file, tree, commit, ref, signature and ownership
  records with overflow-safe size calculations.
- [x] Define upgrade, rollback and interrupted-migration behavior from the
  current repository format.

### 1.2 Store large files as owned chunk lists

- [x] Feed `vcs_chunk_count` and `vcs_chunk` into the production object writer.
- [x] Hash chunks through the existing crypto library with domain separation.
- [x] Deduplicate identical chunks without trusting hashes alone; verify length
  and bytes before reuse.
- [x] Store ordered chunk IDs and exact file length in a file descriptor object.
- [x] Reassemble files with bounds, missing-chunk and corruption checks.
- [ ] Publish chunks, descriptors, manifests and HEAD in one recoverable UXFS
  transaction.
- [x] Reclaim only through explicit ownership accounting; never add GC.

### 1.3 Remove fixed repository limits

- [x] Replace fixed 15-file manifests with bounded paged tree objects.
- [ ] Replace the 64-record assumption with allocator-backed object tables.
- [ ] Support empty, tiny, multi-chunk and maximum-policy-sized files.
- [ ] Make status, commit, checkout, restore and diff operate on the new objects.
- [ ] Keep the old format readable until migration is committed successfully.

### Exit gate

- [ ] Round-trip at least 100,000 files and files larger than 4 GiB in the host
  model without fixed-array overflow.
- [ ] Prove deduplication for identical chunks and correct copy-on-write updates.
- [ ] Pass torn-write, disk-full, checksum-corruption and migration-interruption
  matrices with the previous repository still recoverable.
- [ ] Pass `make -C apps/vcs test`, `make -C apps/ush test` and both BIOS and OVMF
  `ush-vcs-test` gates.

## Milestone 2: Scalable graph, refs and history queries

**Prerequisite:** Milestone 1.

- [ ] Add validated generation numbers and first-parent/topology indexes.
- [ ] Add per-path Bloom filters with a scalar reference and false-negative ban.
- [ ] Add reachability acceleration without changing immutable commits.
- [ ] Page branch, tag, remote-ref and reflog namespaces transactionally.
- [ ] Make log, blame, merge-base, bisect and ancestry checks proportional to
  relevant history rather than total repository size.
- [ ] Persist index rebuild checkpoints and safely discard/rebuild derived data.

### Exit gate

- [ ] Validate histories of at least one million commits, including corruption,
  cycles, missing objects and divergent branches.
- [ ] Differentially compare indexed results with a full graph walk.
- [ ] Demonstrate that dropping every derived index does not lose repository
  history and that rebuilding produces identical query results.

## Milestone 3: Native UXFS working copies

**Prerequisites:** Milestones 1 and 2.

- [ ] Drive status from durable UXFS journal cursors instead of record scans.
- [ ] Use UXFS snapshots for commit, checkout, workspace and rollback boundaries.
- [ ] Add sparse path profiles with atomic profile changes.
- [ ] Add lazy hydration only after UXFS exposes a bounded native hook.
- [ ] Make nested repositories, ignore rules and metadata exclusion scale without
  walking unrelated paths.
- [ ] Persist operation checkpoints so power loss cannot strand an in-progress
  checkout or restore.

### Exit gate

- [ ] Status cost scales with changed paths on a one-million-file repository.
- [ ] Snapshot checkout and rollback survive injected failure at every write.
- [ ] Sparse and hydrated views never expose or silently omit tracked content.

## Milestone 4: Complete native history semantics

**Prerequisites:** Milestones 1 through 3.

- [ ] Promote conflicts to immutable first-class objects owned by commits.
- [ ] Add rename and copy detection with explicit ambiguity thresholds.
- [ ] Add a durable operation log and universal undo for every mutating command.
- [ ] Add stable change IDs and stacked changes without rewriting immutable
  historical objects.
- [ ] Propagate recorded conflict resolutions only when base/ours/theirs identity
  proves they apply.
- [ ] Add advisory locks for configured binary paths.

### Exit gate

- [ ] Property-test merge symmetry, replay, abort and undo invariants.
- [ ] Kill every operation at every persistence boundary and recover to either
  the old or fully published new state.
- [ ] Self-host TattvaOS development history in a shadow VCS repository.

## Milestone 5: Lossless Git bridge

**Prerequisites:** Milestones 1 and 2. May proceed alongside Milestones 3 and 4
after their object formats are frozen.

- [ ] Import and export branches, tags, merges, file modes, deletes, renames,
  symlinks and identities without flattening history.
- [ ] Preserve arbitrary binary blobs and valid Git path quoting at scale.
- [ ] Implement protocol-v2 receive/push service with atomic ref validation.
- [ ] Add SHA-1 repository interoperability beside the current SHA-256 path
  without weakening the native hash policy.
- [ ] Add shallow, filtered and resumed clone/fetch round trips against real Git.
- [ ] Maintain an explicit, tested rejection list for unsupported Git features.

### Exit gate

- [ ] Import, export and re-import large real repositories with identical Git
  object graphs for the supported subset.
- [ ] Pass real Git clone, fetch and push tests over fragmented native transport.
- [ ] Fuzz fast-import, pkt-line, request, PACK and ref-update parsers.

## Milestone 6: Production sync and server

**Prerequisites:** Milestones 1, 2 and the required portions of Milestone 5.

- [ ] Integrate the native DNS resolver; no hosted resolver fallback.
- [ ] Add authenticated sessions, capability negotiation and replay protection.
- [ ] Add resumable object transfer with verified checkpoints and bounded retry.
- [ ] Add concurrent clients with per-client arenas, quotas and cancellation.
- [ ] Add partial fetch, prefetch and object hydration through the native protocol.
- [ ] Add atomic push/land validation and protected ref updates.
- [ ] Add replication, backup and restore using UXFS-native snapshots or send.

### Exit gate

- [ ] Deterministic simulation covers disconnects, duplicates, reordering,
  partitions, clock skew, server restart and quota exhaustion.
- [ ] Load tests prove bounded memory and fairness under slow or hostile clients.
- [ ] Backup restore reproduces refs, objects, ownership and audit roots exactly.

## Milestone 7: Enterprise identity, policy and audit

**Prerequisite:** Milestone 6 session identity and Milestone 2 namespaces.

- [ ] Add roles and path ACLs with deny-by-default hidden-path behavior.
- [ ] Add protected namespaces, required signatures, size policies and code-owner
  approval hooks.
- [ ] Add service identities and short-lived credentials using native crypto.
- [ ] Add append-only audit records for reads, writes and administrative actions.
- [ ] Add a Merkle transparency log for ref updates and consistency proofs.
- [ ] Add retention, legal hold and explicit redaction workflows that preserve an
  auditable record.
- [ ] Add per-tenant quotas, encryption-key ownership and rotation hooks.

### Exit gate

- [ ] Exhaustive ACL matrices prove no data, object ID, subtree hash, size or
  timing-derived namespace leak for denied paths.
- [ ] Tampering, truncation and rollback of audit/transparency records are
  detected on mount and verification.
- [ ] Key rotation and revocation tests preserve readable authorized history.

## Milestone 8: Content intelligence and developer interfaces

**Prerequisite:** Stable scalable storage from Milestone 1.

- [ ] Implement bounded extension, magic and content classification.
- [ ] Add assembly tokenization, symbol indexes and symbol-level blame/diff.
- [ ] Treat unknown and compressed data as binary-safe and non-mergeable.
- [ ] Add generated-file metadata, binary advisory locks and size budgets.
- [ ] Add structured command output, stable exit codes and an IDE protocol.
- [ ] Add `affected`, sparse, workspace, doctor and operation-log commands.

### Exit gate

- [ ] Classification has no false text treatment for binary fuzz corpora.
- [ ] Semantic results always fall back safely to byte/line behavior when the
  parser cannot prove a structure.
- [ ] CLI and IDE outputs have versioned executable conformance vectors.

## Milestone 9: Performance kernels and architecture readiness

**Prerequisites:** Correct scalar formats and large-scale benchmarks.

- [ ] Repair and validate x86 CPU/OS feature detection before enabling SIMD.
- [ ] Implement AVX2 and then AVX-512 hashing, chunking, diff and scan kernels.
- [ ] Require exact scalar parity, guarded dispatch and illegal-instruction tests.
- [ ] Add benchmark gates for status, commit, checkout, merge, graph queries,
  clone and server throughput.
- [D] Port shared code to utasm before AArch64 or RISC-V implementation.
- [D] Implement other-architecture kernels only after identical conformance
  vectors run under their emulators.

### Exit gate

- [ ] Every optimized path matches scalar output for fixed, random and fuzzed
  inputs and falls back safely when unavailable.
- [ ] Performance targets have reproducible measurements and documented gaps;
  correctness and bounds are never relaxed to meet a target.

## Milestone 10: Hardening, migration and release

**Prerequisites:** Milestones 1 through 9 for the selected release scope.

- [ ] Continuous fuzzing for every untrusted parser and persistent reader.
- [ ] Long-duration soak, crash, power-loss, disk-full and memory-pressure runs.
- [ ] Upgrade and rollback tests across every supported storage/wire version.
- [ ] Shadow migration from Git with bidirectional parity reporting.
- [ ] Signed reproducible ULF packages, boot images, SBOM and offline updates.
- [ ] Operator documentation for backup, restore, repair, key rotation and
  incident response.
- [ ] External security review with no unresolved critical or high findings.
- [ ] Physical-hardware qualification after BIOS and OVMF emulator gates.

### Exit gate

- [ ] Release checklist, compatibility matrix and recovery drills are signed.
- [ ] A pilot repository runs production workloads with tested backup/restore.
- [ ] Every deferred item is either scheduled with a prerequisite or explicitly
  excluded from the release contract.

## Immediate queue

Execute these tasks in order; this is the only active queue until Milestone 1.1
is complete:

1. Inventory the exact UXFS transaction, allocation, journal, snapshot and hash
   interfaces already available to assembly callers.
2. Freeze the scalable object and ownership record layouts.
3. Define the current-format-to-scalable-format migration transaction.
4. Implement chunk object write/read/verify using the existing chunker and crypto
   library.
5. Implement file descriptors containing ordered chunk ownership.
6. Add deduplication collision verification and explicit reclamation accounting.
7. Replace fixed manifests with paged tree objects.
8. Migrate status, commit, checkout and recovery one operation at a time.
9. Run large-file, large-tree, corruption and interrupted-migration gates.
10. Only then begin Milestone 2 graph indexes.

## Required validation at every milestone

At minimum:

```text
make -C apps/vcs test
make -C apps/ush test
```

Run focused assembly/shared-object tests before the complete gates. Storage,
network, boot-visible or format changes additionally require the BIOS and OVMF
`ush-vcs-test` gate. Hardware claims require real hardware; QEMU success is
reported as emulator qualification only.
