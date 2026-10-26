# Storage Layout

- Status: Draft
- Version: 0.0
- Owner: TBD

## Scope

How the bounded object store sits on UXFS, including explicit ownership and
deterministic reclamation. A tracing garbage collector is prohibited.

## Definitions

## Specification

### UXFS bootstrap repository, version 2

`vcs init [DIRECTORY]` initializes an existing directory (default: current
directory). It creates `.vcs/` and the regular file `.vcs/format`. It preserves
working files and never creates the target directory implicitly. Paths use the
existing UXFS normalization and length rules. The canonical target path must
leave space for `/.vcs/format` within the 239-byte UXFS path limit.

The format file is exactly 32 bytes, encoded without native struct padding:

| Offset | Size | Value |
|---|---|---|
| 0 | 8 | ASCII `UVCSREP1` |
| 8 | 8 | Little-endian version, 2 |
| 16 | 8 | Last allocated sequence number; zero is accepted as legacy `HEAD` |
| 24 | 8 | HEAD sequence number; zero means no commits |

This is a private local format, not a Git repository. Existing zero-HEAD
version-2 repositories remain compatible. Version 1 is rejected because it has
no authoritative cryptographic integrity records. No timestamp or random
identity is fabricated.

Initialization reserves two free UXFS records before changing memory and calls
`uxv_commit` exactly once to publish both. Capacity/path/type/conflict errors
leave storage unchanged. If `.vcs` already exists, initialization succeeds
without writing only when it is a directory containing the exact supported
format header and a bounded HEAD. Initialization does not audit the whole commit
chain; history operations do. It refuses partial, foreign or future-version metadata;
it never repairs or overwrites these implicitly.

UXFS dual-bank recovery guarantees a complete previous or new snapshot under
the supported block/flush contract. A failed final flush may already have
published the new repository. On I/O failure, the volume is disabled and the
caller must remount; success/rollback is not guessed. Initialization is serialized
with other UXFS operations by the existing console/volume ownership model.

Native entry: `vcs_repo_init(rdi=NUL directory path)` returns a VCS status in
`rax` and `rdx=0` for newly initialized or `rdx=1` for an existing supported
repository. Errors return `rdx=0`. The module links against actual UXFS symbols;
it contains no OS syscalls or host filesystem passthrough. Ush maps errors to
command status 2 and success to 0.

### Commit manifests and blobs

All object names are fixed-width lowercase hexadecimal in the same `.vcs`
directory: `c` plus 16 digits for a commit, `b` plus 16 digits for a blob. History
operations require a canonical root path of at most 216 bytes so these names fit
the UXFS path limit. Commit numbers start at 1 and advance by 1. A new blob ID is
`(commit_number << 8) | (file_ordinal + 1)`; ordinals range from 0 through 14.
An unchanged file reuses its previous blob. Blobs contain the exact original
file bytes, including binary data, and use the normal UXFS file-size field.

Each manifest is a regular file containing a 256-byte header followed by up to
15 entries of 256 bytes each. All integers are unsigned little-endian qwords.

| Offset | Size | Header field |
|---|---|---|
| 0 | 8 | ASCII `UVCSCOM1` |
| 8 | 8 | Commit sequence number, matching the object name |
| 16 | 8 | First-parent sequence number, less than the current ID; zero for root |
| 24 | 8 | Entry count, 0..15 |
| 32 | 8 | Message length, 1..215; bit 63 marks a merge commit |
| 40 | 216 | Message bytes, NUL-terminated and padded with zeroes |

For an ordinary commit, the complete 216-byte message region is available. For
a merge commit the message is limited to 207 bytes and offset 248 stores its
validated second-parent ID; the first parent remains at offset 16. This encoding
keeps all version-1 ordinary manifests readable while making merged ancestry
explicit. Both parents must be nonzero IDs lower than the merge commit ID.

| Entry offset | Size | Field |
|---|---|---|
| 0 | 240 | Repository-relative path, NUL-terminated and padded |
| 240 | 8 | Blob ID |
| 248 | 8 | File byte length, 0..4096 |

Paths must be unique, nonempty and canonical: no leading/trailing slash, empty
components, `.`/`..`, or `.vcs` component. Snapshot ordering follows volume record
enumeration; it is not a content-addressed canonical hash encoding. Manifests
must have exact length `256 + count*256`. Readers validate the full parent chain,
header fields, message bounds, entry names, blob existence/type/size and blob IDs
before producing status/log output or preparing a commit. The reader accepts
padding after the NUL terminators; producers write zero padding.

Each commit owns a 32-byte `h` object with the same 16-digit commit ID. It is
SHA-256 over ASCII `UVCSCHK1`, the exact manifest bytes, then each referenced
blob's exact bytes in manifest order. Hashing uses the shared streaming
`lib/crypto/uhash/sha256` API. Readers compare all 32 bytes without early exit.
The digest detects post-commit modification and is the exact 32-byte message
authenticated by an optional Ed25519 commit signature.

### Signed repository identity

`.vcs/identity` is the active 80-byte regular identity file. It contains `UVCSIDN1`,
the identity-name length, the 32-byte Ed25519 public key, and a 32-byte
NUL-terminated/padded identity name. Names are 1..31 ASCII letters, digits,
period, underscore, or hyphen. The corresponding 32-byte private seed is never
stored by VCS; signing receives it from an explicit UXFS seed file and rejects
it unless its derived public key matches the repository identity.

A signed commit owns an `s` object with the same fixed-width commit ID. Its
160 bytes contain `UVCSSIG1`, algorithm 1 (Ed25519), commit ID, identity-name
length, public key, 64-byte signature, eight zero padding bytes, and the
32-byte NUL-terminated/padded identity name. Verification first performs normal
manifest/blob/digest validation, then requires the signature's identity fields
to exactly match `.vcs/identity` and verifies the signature over the 32-byte
`h` object through `lib/crypto/usign/ed25519`. Signature creation and identity
registration each publish in one UXFS transaction. Existing signature objects
are not overwritten. Rotation stores the previous identity in an `i` object
whose suffix is the first 16 hexadecimal public-key digits before replacing the
active record. An `x` object with the same suffix revokes that key and overrides
both active and retained trust. The suffix is only a bounded namespace index:
the complete public key remains in the record and collisions are rejected by
exact comparison rather than treated as trust matches.

Optional `.vcs/policy` is 16 bytes: `UVCSPOL1` followed by a zero/one qword.
One requires every commit-producing path to supply a matching private seed;
zero or an absent policy permits unsigned commits. Signed commit publication
reserves the signature node during normal commit preflight and writes it in the
same UXFS transaction as the manifest, digest, HEAD, and attached branch.

### Workflow and publication

`status` identifies additions/modifications/deletions by path and exact byte
comparison against HEAD. It includes all regular files under the repository and
excludes `.vcs` components at every depth. There is no ignore-file hierarchy,
empty-directory tracking or rename detection. A root
`.vcsignore` may contain literal relative paths or directory prefixes ending `/`;
blank/comment lines are skipped and the rules file itself remains trackable.
Rules have no globbing or negation. Nested repository contents
remain ordinary files of the enclosing repository, except their metadata.

The optional `.vcs/index` is a regular file containing `UVCSIDX1`, a qword path
count, and that many 240-byte NUL-terminated relative paths. Counts are bounded
to 15 and readers reject malformed or duplicate paths. `add`, `reset`, and
`add --all` publish an index update in one UXFS transaction. With a nonempty
index, commit replaces only indexed paths and retains HEAD blobs for all other
paths; indexed missing tracked paths are deletions. A successful indexed commit
removes the index in the same transaction.

During merge, `.vcs/merge` is exactly 24 bytes: `UVCSMRG1`, target ID, and base
ID. `.vcs/conflicts` uses `UVCSCNF1`, a qword count, and fixed 240-byte relative
paths like the index. Preparation creates these records together with the
provisional tree. Resolution only shrinks the conflict record. A successful
merge commit validates an empty conflict record and removes merge, conflict,
and index records atomically with the new manifest and ref/HEAD update.

`.vcs/rebase` begins with `UVCSRBS1`, followed by original-tip, target, replay
count, next-index qwords, a 40-byte branch-name slot, and oldest-first commit
IDs. Its exact size is `80 + count*8`, bounded by the 64-record volume. Each
successful replay commit advances the durable index. Finalization moves the
saved branch ref, recreates its attachment, and removes the state record.

`.vcs/pick` is a 32-byte durable cherry-pick/revert record: `UVCSPCK1`, operation
kind, source commit, and original HEAD. The shared replay engine owns the normal
index/conflict records. Continue commits the resolved result and removes the
pick state; abort restores the original tree and branch attachment. Root replay
uses a bounded in-memory empty manifest and does not allocate a fake commit.

`commit MESSAGE` snapshots the selected set. Its first empty snapshot is allowed;
subsequent unchanged snapshots are a no-op. It checks the whole prior chain,
message bounds, snapshot capacity, free record count and object path collisions
before touching live nodes. It allocates a manifest, integrity record, and
new/changed blobs, then
updates HEAD and publishes the entire change through a single `uxv_commit`.
Old manifests, digests, and blobs are retained. Volume exhaustion rejects a new commit
without deleting history or partially installing objects.

`log` walks the linear parent chain newest first, showing local IDs and messages.
Normal log output preserves LF message boundaries and indents every line;
control bytes other than LF, non-ASCII and backslashes are escaped. Oneline log
output escapes LF too, keeping each commit on one physical line. Repeated command
line `-m` values are joined with two LF bytes. `-F` message files contribute
their exact bytes and must contain 1..215 bytes without NUL. These presentation
rules never alter the manifest message bytes.
Success (including a dirty status or no-op commit) is command status 0; failures
map to 2. Neither status nor log writes storage.

Native API: `vcs_history(rdi=operation, rsi=argument, rdx=write_callback)` returns
a VCS status in `rax`. Operations are 0/status, 1/commit, 2/full log,
3/oneline log, 4/show, 5/restore, and 6/integrity check. Commit uses a readable
NUL-terminated message.
For show, zero selects HEAD and a nonzero argument is the numeric sequence.
The callback follows SysV AMD64 with
`rdi=bytes, rsi=length`; its return value is ignored, matching the Ush frontend.
This module uses serialized static buffers and must not be called concurrently
or reentrantly; the caller must own the UXFS volume/console for the whole call.

The history is local and may diverge through branches. IDs are not content hashes;
signed objects make a repository-local identity claim, not a certificate,
timestamp, or remote trust claim. UXFS
checksums detect media corruption and VCS SHA-256 records detect mismatched stored
content. An unsigned commit can be replaced by a writer who can also replace its
digest. A valid signed replacement additionally requires the registered private
seed; VCS does not claim protection when that external seed file is compromised.
Ownership flows from refs to manifests, integrity records, optional signature
records, and blobs. No background/tracing GC exists;
future explicit pruning must prove an object has no live owner before releasing
its UXFS record. Packing and Git interchange remain outside the current scope.

## Test Vectors

`make -C apps/vcs test` exercises the NASM initializer linked to the actual NASM
UXFS backend: exact bytes, fresh mounts, repeated initialization, foreign and
partial metadata, path capacity, zero/one free record, torn body/header writes
and both flush failures. After simulated I/O failures, remount exposes either
both new nodes or neither. `make -C apps/ush test` additionally exercises the
real command parser, current directory and persistence across host processes.

The new `test_history.py` and `test_vcs_history.py` add snapshot/reuse, deletion,
ancestor discovery, log order, same-size blob tampering, SHA-256 verification,
malformed metadata and transaction-failure cases.
**These additions and the history implementation have not been built or tested:
validation is deferred at the user's explicit request.** Prior init-only results
do not qualify the history changes or the updated initializer.

## Open Questions
