# Monorepo VCS on UFS: Enterprise Product Plan (v3, Utkarsha OS)

*Working title. A native, git-interoperable version control system written entirely in assembly, built directly on the Utkarsha File System (UFS).*

---

## 0. What Changed in This Replan

UFS already provides a change journal, snapshots, and subtree hashing. The VCS therefore stops being a layer that imitates a filesystem and becomes a layer that **uses** one. Consequences:

- No virtual-filesystem driver project (the largest risk in v1 of the plan is gone).
- One Merkle structure shared by filesystem and VCS: a commit reads hashes UFS already maintains.
- Checkout, branching, and server-side forking become snapshot operations.
- Scope narrows to **Utkarsha OS only**: no other operating systems, no portable tier, no OS abstraction layer, no ABI definitions. The VCS calls Utkarsha OS and UFS directly.
- **x86-64 first.** AArch64 and RISC-V 64-bit have reserved places in the code tree but no work until x86-64 is done.
- **NASM now, utasm later.** NASM supports x86 only, so other architectures wait for utasm.

**Scope:** assembly-only projects: source, includes, macros, data, and the assets those projects ship or test with. It is not a general-purpose VCS, which lets every algorithm be tuned for assembly and removes generic-language features.

**Assumptions to confirm:** native object model with a two-way git bridge; UFS also offers lazy hydration (fetch file contents on first read). Section 4 lists everything the plan asks of UFS.

---

## 1. Vision and Goals

Build the fastest, safest, most scalable version control system available, and make it the default for monorepos that outgrow git.

1. **Constant-time feel at any size.** Cost scales with what you touch, never with repository size.
2. **Nothing is lost or stuck.** Every operation is undoable; conflicts are data, not emergencies.
3. **Enterprise trust by construction.** Signed history, path-level access control, and tamper-evident audit live in the core.
4. **Filesystem and VCS as one system.** The strongest guarantees (integrity, atomicity, speed) come from UFS itself.
5. **Drop-in coexistence.** A two-way git bridge lets teams adopt gradually.

**Design targets.** Existing tools (git with a filesystem monitor, Sapling) already reach tens of milliseconds for status, so matching them is not a goal. Because everything is assembly on a filesystem built for this, the only remaining costs are hardware: NVMe flush latency and network round trips. Targets sit close to those floors, at headroom of 100 million files and 1 billion commits, and are to be validated by benchmarks on UFS.

| Operation | Target | Stretch | What sets the floor |
| --- | --- | --- | --- |
| Status and diff, any repository size | Under 1 ms | 100 µs | Journal read; cost grows with changes only |
| Commit of a small change (durable) | Under 1 ms | 200 µs | Hashing takes microseconds; NVMe flush dominates |
| Switch to another change | Under 10 ms | 2 ms | Snapshot clone, constant time |
| Branch, fork, or CI workspace | Under 5 ms | 1 ms | Snapshot clone |
| Log, blame, or bisect step on one file | Under 5 ms | 1 ms | Generation numbers and path bloom filters |
| Symbol-level blame (label or macro) | Under 10 ms | 2 ms | Symbol index |
| Rebase of a 20-change stack | Under 100 ms | 20 ms | Tree-hash reuse, in-memory merge |
| Clone to first usable file | Under 1 s | 300 ms | Network round trip |
| Landing throughput per server shard | 20,000+ per second | 100,000+ per second | Group commit, consensus latency, NVMe |
| Client memory use (idle) | Under 16 MB | 4 MB | Arena allocation, no runtime |

---

## 2. Landscape: What Exists and What We Take

| Tool | Strength to adopt | Limit we remove |
| --- | --- | --- |
| Git | Universal ecosystem, content-addressed DAG | Whole-history clones, working-tree scans, binary bloat, blocking conflicts |
| Perforce | Central scale, large binaries, path permissions | Not distributed, weak branching, no offline work |
| Sapling and EdenFS | Virtual filesystem, stacked changes, scalable server | Heavy server stack, filesystem emulated on top of another one |
| Jujutsu | First-class conflicts, operation log, automatic rebase | Single-machine focus, git storage limits |
| Pijul | Patch-based merge correctness | Small ecosystem, weak scale story |
| Google Piper | Trunk-based flow, virtual workspaces, atomic global commits | Proprietary and unavailable |

The table summarizes public information at a high level; verify details before external use. Our position: take the best idea from each, and gain the one advantage none of them have, a filesystem built for the VCS.

---

## 3. Strategy: Utkarsha-Native, Architecture-Ready

| Dimension | Decision |
| --- | --- |
| Operating system | Utkarsha OS only. No other operating systems, no OS abstraction layer, no ABI definitions |
| Working copy | UFS directly: snapshots, journal, and subtree hashes come from the filesystem |
| Architecture | x86-64 first; AArch64 and RISC-V 64-bit reserved in the tree |
| Assembler | NASM now; utasm later (required for AArch64 and RISC-V, since NASM is x86-only) |
| Interoperability | Git bridge only; the repository format is the VCS's own |

Rules: architecture-specific code is isolated under `src/arch/<arch>` and `src/kernels/<arch>`, so adding an architecture never touches shared modules. The object model, wire protocol, and repository format are architecture-independent (fixed byte order and layout), so repositories and servers on different architectures interoperate.

---

## 4. UFS Interface Contract

Phase 0 freezes the exact interface. This table is the starting list.

| Capability | Status | Use in the VCS |
| --- | --- | --- |
| Change journal with cursors | Available | Instant status; incremental indexing; watch mode |
| Snapshots (create, clone, delete) | Available | Commits' working states, checkout, branches, undo points |
| Subtree hashing | Available | Tree objects; diff and sync skip unchanged subtrees; commit without rehashing |
| Lazy hydration hooks | To confirm | Clone in seconds; sparse and partial working copies |
| Snapshot diff (changed paths between two snapshots) | To confirm | Fast diff, affected-target queries, replication |
| Snapshot send and receive | To confirm | Server replication, backups, repository fork across servers |
| Atomic multi-path commit or transaction | To confirm | Atomic landing; crash-safe ref updates |
| Extended attributes | To confirm | Object metadata, ownership labels |
| Per-volume quotas and encryption keys | To confirm | Multi-tenancy |
| Content-defined chunk dedup | To confirm | Shared storage between working files and the object store |

**Key design rule:** the VCS tree-object hash **is** the UFS subtree hash (same algorithm, same domain separation). A commit stores a root hash that the filesystem already knows.

---

## 5. Architecture

```
 Developer machine                      Server side (UFS volumes)
+------------------------+            +--------------------------------+
| CLI + IDE protocol     |            | Frontends (stateless)          |
| UFS working copy       | <- wire -> | Auth, path ACL, rate limits    |
| Object store (on UFS)  |  protocol  +----------------+---------------+
| Merge engine, op log   |            | Commit queue   | Metadata store|
+-----------+------------+            | (atomic land)  | (refs, graph) |
            |                         +----------------+---------------+
   Git bridge (import/export)         | Chunk and object store (UFS)   |
                                      | Snapshot replication, caches   |
                                      | Audit log, transparency log    |
                                      +--------------------------------+
```

**Components**

1. **CLI and control API:** commands, JSON output, stable exit codes.
2. **UFS integration layer:** snapshots, journal cursors, subtree hash queries, hydration hooks.
3. **Object store:** chunks, trees, commits, changes, conflicts, operations, stored on UFS.
4. **Commit graph and indexes:** generation numbers, per-path bloom filters, reachability bitmaps.
5. **Merge and diff engine:** text, binary, and assembly-aware.
6. **Operation log:** every command recorded; powers undo and audit.
7. **Sync client:** partial fetch, prefetch, resumable transfer.
8. **Git bridge:** import, export, git-protocol gateway.
9. **Architecture layer:** per-architecture entry points, atomics, barriers, and SIMD kernels (x86-64 now; AArch64 and RISC-V reserved).
10. **Server frontends, commit queue, metadata store, object shards, edge caches.**
11. **Policy, audit, and transparency log.**
12. **Observability:** metrics, traces, structured logs.

---

## 6. Core Capabilities

1. **One Merkle tree.** Filesystem subtree hashes are the tree objects, so diff, status, and sync cost is proportional to the change.
2. **Snapshot-based commits and checkout.** Creating, switching, and forking changes are snapshot operations, constant time at any size.
3. **Journal-driven status.** Status reads the UFS change journal; it never walks the tree.
4. **Partial everything.** Lazy clone, sparse profiles, and on-demand history.
5. **Stacked changes with stable change IDs.** Edit any change; descendants rebase automatically; IDs survive rewrites.
6. **First-class conflicts.** Conflicts are stored inside commits, so rebases never stop midway and resolutions propagate forward.
7. **Operation log and universal undo.** Every command is recorded; any prior state can be restored, backed by snapshots.
8. **Atomic landing at scale.** A global commit queue lands changes atomically and linearly, with pre-land validation.
9. **Path-level permissions and ownership,** enforced by the server per path; hidden paths do not exist for unauthorized users.
10. **Fast history queries.** Generation numbers and per-path bloom indexes keep log, blame, and bisect independent of total history.
11. **Affected-target queries.** The exact set of packages and tests a change touches, for any build or CI system.
12. **Git bridge.** Lossless import and export, a git-protocol gateway, and identity mapping.
13. **Verifiable history.** Signed commits and a Merkle transparency log make history rewrites detectable.
14. **Snapshot replication.** Servers replicate, back up, and fork repositories by shipping snapshot differences.

---

## 7. Core Specifications (Phase 0)

Written, reviewed, and frozen with test vectors before engine work scales.

| Spec | What it defines |
| --- | --- |
| UFS interface contract | Exact calls, semantics, errors, and guarantees the VCS depends on (Section 4) |
| Object model | Chunk, file, tree, commit, change, conflict, operation, signature; canonical encoding; versioning |
| Hashing and IDs | Shared hash domain with UFS subtree hashes; 128-bit change IDs; domain separation |
| Chunking | Content-defined sizes, determinism across hosts, alignment with UFS dedup |
| Storage layout | How the object store sits on UFS; compaction and garbage collection |
| Commit graph and indexes | Generation numbers, bloom filters, bitmaps |
| Working copy and journal | Snapshot lifecycle, journal cursor handling, hydration |
| Merge model | Three-way tree merge, conflict objects, rename detection, assembly-aware merge, resolution propagation |
| Operation log | Records, views, undo semantics |
| Refs and namespaces | Bookmarks, remote refs, protected namespaces, atomic updates |
| Wire protocol | Negotiation, partial fetch, push, land, streaming, resumable, version negotiation |
| Access control | Path ACLs, policy language, identity mapping, hidden-path semantics |
| Git bridge | Object mapping, lossless round trip, protocol gateway |
| Threat model | Assets, adversaries, controls |

---

## 8. Server and Scale (on UFS)

- **Stateless frontends** with per-path authentication and authorization on every request.
- **Repository per UFS volume:** isolation, quotas, and per-tenant encryption keys.
- **Sharded metadata store** by repository and path prefix, with consensus-backed refs.
- **Commit queue:** validates changes, speculatively merges independent ones, lands atomically in order.
- **Snapshot replication:** zones and regions stay in sync by shipping snapshot differences; backups and point-in-time restore use the same mechanism.
- **Instant forks:** a new repository, branch, or CI workspace is a snapshot clone.
- **Edge caches** near offices and CI farms, prefetching recently active paths.
- **Online operations:** rolling upgrades and shard rebalancing without downtime.

---

## 9. Enterprise Capabilities

- **Identity:** SSO (OIDC, SAML), SCIM, service accounts for CI, short-lived tokens.
- **Access control:** roles plus path-level ACLs, hidden paths, code owners enforced at land time.
- **Policy as code:** protected namespaces, required reviews and signatures, size budgets, banned patterns, secret scanning on push.
- **Audit:** append-only, tamper-evident log of reads, writes, and admin actions, with SIEM export.
- **Data governance:** retention, legal hold, data residency per tenant, auditable secret redaction.
- **Compliance:** evidence packs for SOC 2 and ISO 27001 style audits.
- **Deployment:** single server image for Utkarsha OS, ULF package, on-premise and air-gapped installs, offline update bundles.
- **Availability:** multi-zone deployment, defined RPO and RTO, regularly tested restores.
- **Licensing and support:** offline-verifiable license keys, LTS channels, support SLAs.
- **Migration:** git, Perforce, and Mercurial importers; shadow-mode mirror with parity checks.

---

## 10. Security and Trust

1. **Signed history** with optional mandatory signatures, hardware keys, and signature agility for post-quantum schemes.
2. **Transparency log** of ref updates with consistency proofs, so silent rewrites are detectable.
3. **Encryption** in transit (mutual TLS) and at rest, with per-tenant keys and rotation.
4. **Hidden-path guarantees:** subtree hashes of unreadable paths are masked for unauthorized clients.
5. **End-to-end integrity:** UFS checksums plus VCS hashes, with continuous scrubbing.
6. **Supply chain:** signed, reproducible releases with an SBOM.
7. **Secret protection:** push-time scanning and an audited redaction workflow.
8. **Hardened parsing:** every untrusted input path fuzzed; bounded memory by design.
9. **Vulnerability handling:** public disclosure policy and patch SLAs.

---

## 11. Developer Experience

| Command | Purpose |
| --- | --- |
| `clone` | Lazy clone with a sparse profile |
| `status`, `diff` | Instant, journal-based |
| `commit`, `amend` | Edit the stack; descendants rebase automatically |
| `stack`, `land` | View a stack and land it through the commit queue |
| `undo`, `op log` | Restore any earlier state |
| `resolve` | Resolve first-class conflicts at any time |
| `log`, `blame`, `bisect` | Indexed history queries |
| `affected` | Packages and tests touched by a change |
| `sparse` | Edit the path profile |
| `fork`, `workspace` | Constant-time branches and CI workspaces |
| `git import`, `git export`, `git serve` | The git bridge |
| `doctor` | Diagnostics and repair |

Also: a language-server-style protocol for IDEs, review and CI hooks, shell completion, man pages.

---

## 12. Assembly-Specific Advantages

- **Syntax-aware diff and merge:** tokenizes labels, sections, macros, directives, and instruction lines, so moved blocks and renamed labels merge cleanly.
- **Symbol-level history:** blame and log by label or macro, not only by line.
- **Binary awareness:** section-level diff for object files, flat binaries, and custom formats.
- **Multi-ISA awareness:** shared and per-architecture directories with cross-architecture change views.
- **Build integration:** `affected` maps changed files to targets for any build system.
- **Zero-abstraction speed:** hand-tuned SIMD for hashing, chunking, and diff; direct access to Utkarsha OS and UFS with no runtime.

### 12.1 Content Types the VCS Must Recognise

Assembly is the only language that gets semantic treatment. A browser project (and the rest of the stack) still carries other files, and the VCS must classify them so storage, diff, and merge behave correctly. Classification uses extension, magic bytes, and content sniffing; per-path rules in the repository config always win. Unknown files default to binary-safe handling.

| Category | Examples | Treatment |
| --- | --- | --- |
| Assembly source | NASM, utasm, GAS-style, AArch64, RISC-V (`.asm`, `.s`, `.inc`) | Semantic diff and merge, symbol index |
| Linker and layout files | Linker scripts, memory maps, ULF, TVX, TVFS layout specs | Text diff, layout-aware validation |
| Specs and docs | Markdown, plain text, RFC and standards text | Line diff, no semantic merge |
| Web test inputs | HTML, CSS, JavaScript, JSON, SVG, XML used as browser fixtures | Opaque text: line diff only, never parsed or executed by the VCS |
| Data tables | Unicode (UCD) data, CSV, generated tables, test vectors | Line diff, chunking for large files, generated-file flag |
| Images (test and golden) | PNG, JPEG, WebP, GIF, BMP | Binary: chunk dedup, no merge, optional pixel diff later |
| Audio | WAV, FLAC, MP3, Ogg, Opus, AAC | Binary: chunk dedup (strong only for uncompressed WAV), no merge, lazy fetch |
| Video | MP4, WebM, MKV, AVI | Binary: lazy fetch only, per-path size budgets, no merge |
| Fonts | TTF, OTF, WOFF, WOFF2 | Binary: chunk dedup, no merge |
| Certificates and key material | PEM, DER, test certificates | Text or binary by sniffing; secret scanning on private keys |
| Binary artifacts | ELF, flat binaries, boot images, object files | Binary, with section-aware diff for known formats |
| Archives and compressed data | zip, gz, xz, tar | Binary: opaque; unpack-aware dedup later |
| Config | TOML, INI, key=value | Line diff |
| Generated files | Anything marked generated | Stored and flagged; excluded from blame and ownership |

Encoding rules for the browser work: UTF-8 is the default; UTF-16 and Latin-1 are detected; line endings (LF, CRLF, CR) are stored byte-exact and never normalized silently. Large web test corpora use sparse profiles, and golden screenshots get per-path size budgets.

Media handling: compressed formats (JPEG, PNG, MP3, MP4, and similar) dedup poorly, because a small edit re-encodes the whole file. Media is therefore detected by magic bytes, never delta-compressed, fetched lazily, and held to per-path size budgets. Since binaries cannot be merged, any binary path can carry an advisory lock, so two people do not edit the same file in parallel. This list of content types is considered complete for v1; anything else falls back to binary-safe handling.

---

## 13. Implementation Strategy

- **Target:** Utkarsha OS only. x86-64 first; AArch64 and RISC-V 64-bit have reserved places in the tree and wait for utasm.
- **Assembler:** NASM now; migrate to utasm later.
- **System access:** the VCS calls Utkarsha OS and UFS directly. There is no OS abstraction layer and no ABI definition; UFS calls live in their own module.
- **Memory:** arenas and regions; no general heap on hot paths.
- **SIMD:** Blake3, chunking, diff, and scans with AVX-512 and AVX2 paths plus a scalar reference, checked against reference vectors; NEON and RISC-V vector kernels are reserved.
- **Concurrency:** one worker per core, asynchronous I/O queues, lock-free queues, share-nothing shards.
- **Crash safety:** write-ahead logging, atomic operations through UFS, checksums on every segment.
- **Testing:** deterministic server simulation (faults, partitions, clock skew), fuzzing, differential tests against git for the bridge, long soak tests.
- **Self-hosting:** the project's own source moves into the VCS from Phase 2.
- **Code layout:** see Section 19 (Project Folder Structure).
- **Standards:** coding standards (including register usage), macro rules, and a review checklist written before code starts.

---

## 14. Roadmap

Durations are planning estimates for a small focused team. Phases 1 to 3 already form a useful standalone VCS.

| Phase | Duration | Deliverables | Exit criteria |
| --- | --- | --- | --- |
| 0. Specification | 3 to 5 weeks | All Section 7 specs including the UFS contract, test vectors, threat model, coding standards | Specs frozen at v1.0; UFS contract confirmed by UFS maintainers |
| 1. Local core on UFS | 6 to 8 weeks | UFS layer, allocators, Blake3, chunking, object store, commit graph, snapshot commits, basic CLI | Repos of 1M files; status and commit hit targets; kill -9 and disk-full tests pass |
| 2. Merge, stacks, undo | 6 to 8 weeks | Merge engine, first-class conflicts, operation log, stacks, sparse profiles, watch mode | Undo restores any state; project self-hosts |
| 3. Git bridge | 6 to 8 weeks | Import, export, lossless round trip, git-protocol gateway | Round trip on large real repos; differential tests green |
| 4. Server and protocol | 8 to 10 weeks | Wire protocol, partial fetch, frontends, metadata store, commit queue, object shards, snapshot replication | Multi-user clone and land; target landing rate met in load tests |
| 5. Enterprise layer | 8 to 10 weeks | SSO, path ACLs, policy engine, audit, transparency log, signing, redaction, tenancy | ACL and leak tests pass; audit log verifies; evidence pack produced |
| 6. Scale and hardening | 8 to 10 weeks | 10M-file benchmarks, geo-replication, edge caches, fuzz campaigns, external security review | Section 1 targets met or gap list agreed; no open high-severity issues |
| 7. Release | 4 to 6 weeks | Docs, importers, ULF packages, boot images, LTS policy, pilots | Pilot teams in production; GA checklist signed |
| 8. Other architectures (after v1) | To be planned | AArch64 and RISC-V arch code and kernels, after the utasm migration | The same conformance, vector, and benchmark suites pass on each architecture |

---

## 15. Quality Assurance

- **Conformance:** spec-derived vectors and golden files for every format and error message.
- **Simulation and chaos:** deterministic fault injection, including UFS failure modes.
- **Differential testing:** against git for the bridge; against reference implementations for Blake3 and chunking.
- **Fuzzing:** continuous, on parsers, protocol, store reader, and merge engine.
- **Performance gates:** every commit benchmarked against Section 1 targets, with regression alerts.
- **Real corpora:** large public repositories and the project's own monorepo.
- **Security tests:** ACL bypass, hash-masking leaks, cache poisoning, protocol downgrade.
- **Compatibility:** upgrade and rollback tests across object-model and protocol versions; vector tests run against the scalar reference and every SIMD kernel.

---

## 16. Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Data loss or store corruption | Critical | Write-ahead log, UFS plus VCS checksums, continuous scrubbing, simulation, backups |
| Hidden-path information leaks | Critical | Design review, leak tests, external audit |
| Signing key compromise | Critical | HSM-backed keys, rotation, revocation, transparency-log monitoring |
| Tight coupling to UFS and Utkarsha OS limits adoption | High | Versioned interface contract frozen in Phase 0; git bridge keeps data portable |
| UFS interfaces change under the VCS | High | Versioned UFS contract frozen in Phase 0; conformance tests run on both sides |
| Git bridge fidelity gaps | High | Differential tests, shadow mode, documented unsupported features |
| Wrong merge results | High | Property-based tests; ambiguity becomes a recorded conflict, never a guess |
| Memory-safety bugs in assembly | High | Bounded arenas, fuzzing, strict conventions, review checklist |
| Ecosystem expects git | High | Gateway, IDE protocol, importers |
| Scope exceeds team capacity | High | Strict phase gates; ship Phases 1 to 3 as a standalone VCS first |
| Format or protocol mistakes locked in | High | Version negotiation, reserved fields, Phase 0 reviews |

---

## 17. Open Decisions

1. Confirm native format with a git bridge, versus a git-compatible storage format.
2. Confirm which "to confirm" UFS capabilities in Section 4 exist today, and which UFS must gain.
3. Whether the VCS object store shares UFS chunk dedup directly, or keeps its own chunk index.
4. Ref consensus: a Raft-class protocol versus single-writer shards with failover.
5. Wire protocol: custom binary versus HTTP/2 or HTTP/3 transport.
6. Signature schemes at launch, including a post-quantum option.
7. Whether code review is built in for v1 or integration-only.
8. Licensing model, tiers, naming, and branding.

---

## 18. Immediate Next Steps

1. Walk through Section 4 against UFS and mark each capability confirmed or missing.
2. Write the UFS contract, object model, hashing and ID, and chunking specs first, with test vectors.
3. Set up the repository, benchmark CI, and the simulation harness.
4. Define coding standards and the module layout.
5. Build a small prototype of snapshot commit plus journal status on UFS to validate the speed targets early.

---

## 19. Project Folder Structure

```
utkarsha-vcs/
  README.md  LICENSE  CHANGELOG.md  SECURITY.md  CONTRIBUTING.md  STRUCTURE.md
  include/                shared NASM macros, constants, struct layouts
  src/
    core/                 arenas, bytes and strings, errors, logging, time
    arch/
      x86_64/             entry points, atomics, barriers, cache and timer access
      aarch64/            reserved (needs utasm)
      riscv64/            reserved (needs utasm)
    kernels/
      avx512/ avx2/ scalar/   x86-64 SIMD kernels and the scalar reference
      aarch64/ riscv64/       reserved
    ufs/                  UFS integration: snapshots, journal, subtree hashes, hydration
    store/                object store, segments, write-ahead log, GC
    graph/                commit graph, bloom filters, bitmaps
    merge/                diff, three-way merge, assembly-aware tokenizer, conflicts, content-type classifier
    oplog/                operation log and undo
    sync/                 client protocol, partial fetch, prefetch
    bridge/               git import, export, gateway
    server/               frontends, commit queue, metadata, replication, caches
    policy/               ACLs, policy engine, audit, transparency log, signing
    cli/                  commands and JSON output
    ide/                  IDE protocol
  tests/
    unit/ golden/ vectors/ conformance/ differential/
  fuzz/  sim/  bench/  tools/  scripts/
  bootstrap/              stage 0 NASM builder
  packaging/
    ulf/ images/          ULF packages and bootable Utkarsha OS images
  examples/
  docs/
    plan/ specs/ standards/ adr/ manual/
```

Rules:

1. Every directory has a README stating its purpose.
2. Architecture-specific code lives only in `src/arch/<arch>` and `src/kernels/<arch>`.
3. No third-party dependencies anywhere in the tree.
4. Source files are NASM (`.asm`, `.inc`) until the utasm migration.
5. The Phase 0 specs in `docs/specs/` are written and frozen before the matching source modules grow.
