# Storage Layout

- Status: Bounded v2 implemented; scalable v3 layout frozen
- Version: 1.1
- Owner: Utkarsha Lab

## Scope

How the bounded object store sits on UXFS, including explicit ownership and
deterministic reclamation. A tracing garbage collector is prohibited.

## Definitions

- **Object ID:** complete 32-byte cryptographic identity of canonical immutable
  object bytes.
- **Locator:** UXFS-private physical block/allocation identifier. It is never a
  portable identity and never enters an object hash.
- **Root hash:** authenticated identity of one canonical mutable-catalog
  generation.
- **Generation:** strictly increasing durable publication number. Values are
  never reused or wrapped.
- **Ownership edge:** exact durable relationship preventing reclamation of a
  referenced immutable object.

## Specification

### Scalable repository, format version 3

Format version 3 is a new storage namespace. It does not enlarge or reinterpret
version-2 UXFS records in place. Migration validates the complete version-2
repository and builds version-3 state separately before one atomic root switch.

#### Repository superblock

The scalable repository superblock is exactly 512 bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSREP3` |
| 8 | 4 | repository format version, 3 |
| 12 | 4 | header bytes, 512 |
| 16 | 8 | required feature bits |
| 24 | 8 | repository generation, starting at 1 |
| 32 | 16 | nonzero random repository UUID |
| 48 | 4 | object hash algorithm, 1 SHA-256 |
| 52 | 4 | storage block size, 4,096 |
| 56 | 32 | HEAD commit ID; zero for unborn repository |
| 88 | 32 | ref-catalog root hash |
| 120 | 32 | ownership-catalog root hash |
| 152 | 32 | operation-head object ID or zero |
| 184 | 32 | object-index root hash |
| 216 | 32 | migration-state root hash or zero |
| 248 | 8 | last committed operation sequence |
| 256 | 8 | next transaction sequence; never zero |
| 264 | 8 | signed creation timestamp nanoseconds or zero |
| 272 | 208 | reserved zero |
| 480 | 32 | SHA-256 of bytes 0..479 |

Unknown required feature bits reject mount. Generation and transaction sequence
never wrap. Every root referenced by one superblock must belong to the same
published transaction. The superblock is selected through the scalable UXFS
atomic-generation contract defined by `00-ufs-contract.md`; it is not updated in
place without durable root publication.

Recovery validates redundant candidate slots independently. One invalid or torn
slot is ignored when the other validates. When both validate, the candidate with
the greater generation wins only if its transaction sequence increases, its
operation sequence does not decrease, and it retains every feature required by
the older generation. Repository UUID, hash algorithm, block size and creation
timestamp are immutable. Byte-identical equal generations are harmless;
divergent equal generations are split-brain corruption and recovery fails
without selecting either slot.

Initial feature bits are:

| Bit | Meaning |
| ---: | --- |
| 0 | paged content objects required |
| 1 | explicit ownership catalog required |
| 2 | signed identity records may exist |
| 3 | operation log may exist |

Bits 4 through 63 are reserved and must be zero in a version-3 writer.

#### Object envelope

Every immutable object begins with a 128-byte physical envelope. This envelope
is not part of the content-ID preimage.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSOBJ3` |
| 8 | 2 | envelope version, 1 |
| 10 | 2 | header bytes, 128 |
| 12 | 2 | object type |
| 14 | 2 | hash algorithm, 1 |
| 16 | 4 | flags, currently zero |
| 20 | 4 | reserved zero |
| 24 | 8 | canonical payload length |
| 32 | 8 | extent count |
| 40 | 32 | complete object ID |
| 72 | 8 | first extent locator; zero only for zero-byte payload |
| 80 | 8 | transaction sequence that created this envelope |
| 88 | 32 | SHA-256 of bytes 0..87 |
| 120 | 8 | reserved zero |

Payload length must match the object type's canonical formula. Extent count is
zero only when payload length is zero; otherwise it equals
`ceil(payload_length / 4032)` without overflow. The object ID is recomputed over
the canonical payload before publication and after untrusted reads.

#### Object extents

Each object extent is one 4,096-byte block with a 64-byte header and up to 4,032
payload bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSEXT1` |
| 8 | 2 | extent version, 1 |
| 10 | 2 | flags; bit 0 final, others zero |
| 12 | 4 | payload bytes in this extent, 1..4,032 |
| 16 | 32 | owning object ID |
| 48 | 8 | zero-based extent index |
| 56 | 8 | next extent locator; zero only on final extent |
| 64 | variable | canonical payload bytes |

Unused bytes after the payload are zero. Extent indexes are contiguous, object
IDs match the envelope, and the final extent ends exactly at canonical payload
length. Cycles, repeated locators, premature zero, extra extents and cross-object
links are corruption. Locators are UXFS-private allocation identifiers and are
never copied into hashes, Git objects, bundles or signatures.

#### Object index

The object index maps complete 32-byte IDs to envelope locators, types and
payload lengths. Its canonical fixed record is 64 bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 32 | complete object ID |
| 32 | 8 | envelope locator |
| 40 | 8 | canonical payload length |
| 48 | 4 | object type |
| 52 | 4 | flags, currently zero |
| 56 | 8 | creation transaction sequence |

Records are strictly sorted by all 32 ID bytes. Duplicate IDs must resolve to
the same type, length and exact payload; otherwise publication fails as a hash
collision. The physical index is a UXFS transactional B-tree. Its root hash uses
root kind 5 from `02-hashing-and-ids.md`.

#### Ref catalog

The ref catalog contains sorted variable records of
`48 + align8(name_length)` bytes:

| Relative offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | kind: 1 branch, 2 tag, 3 remote, 4 workspace |
| 1 | 1 | name length, 1..240 |
| 2 | 2 | flags: bit 0 protected, bit 1 symbolic |
| 4 | 4 | reserved zero |
| 8 | 8 | ref generation, starting at 1 |
| 16 | 32 | target commit ID, or target-ref key hash when symbolic |
| 48 | variable | ASCII ref name plus zero alignment padding |

Names use letters, digits, period, underscore, hyphen and slash. Components are
nonempty, not dot/dot-dot, do not start with period and cannot contain `.vcs`.
Records are strictly sorted by kind then unsigned name bytes. Ref generation
increments on every target change and never wraps.

HEAD is the superblock commit ID. An attached branch is represented by a
reserved `workspace` ref named `HEAD` whose target identifies the branch record;
detached HEAD has no such record. Tags are immutable unless an explicit policy
operation authorizes replacement.

#### Ownership catalog

Ownership is stored as exact immutable-object edges, not tracing state. Each
catalog record is 80 bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | owner kind |
| 4 | 4 | child object type |
| 8 | 32 | owner key |
| 40 | 32 | child object ID |
| 72 | 8 | flags, currently zero |

Owner kinds are 1 immutable object, 2 ref, 3 snapshot, 4 operation root, 5
transaction pin and 6 migration pin. Immutable-object owner keys are full object
IDs. Mutable owner keys are domain-separated hashes of their complete canonical
identity, never truncated display names.

Records are strictly sorted by child ID, owner kind and owner key. Duplicate
edges are invalid. An object's inbound owner count is derived from exact edges;
no unaudited counter is authoritative. Publication adds all new edges and root
changes in the same transaction as new objects. Explicit reclamation may remove
an object only after the transaction proves it has no inbound edge, no active
reader pin and no pending transaction/migration pin. There is no GC.

#### Mutable catalog paging

Object-index, ref and ownership records are stored in UXFS transactional B-tree
pages. Page size is 4,096 bytes; headers are 128 bytes; records never cross a
page. Each page records kind, level, record count, generation, lower/upper key,
sibling locators and a 32-byte checksum. Exact UXFS page and transaction layouts
remain blocked on the scalable ABI, but the canonical record bytes and root-hash
inputs above are frozen and must not depend on physical page pointers.

#### Publication order

One scalable commit transaction performs this logical order:

1. reserve the maximum blocks, catalog records and ownership edges;
2. write and verify new extents and envelopes without publishing index entries;
3. write copy-on-write object-index and ownership pages;
4. write copy-on-write refs and operation pages;
5. flush every referenced block;
6. write the new checksummed superblock generation;
7. issue the durability barrier and publish that generation;
8. release superseded blocks only through a later explicit ownership transaction.

Failure before step seven leaves the previous generation authoritative. Failure
during or after the final barrier poisons the mount until remount determines the
winning complete generation. No caller guesses whether publication occurred.

#### Arithmetic and capacity rules

Before allocation, readers and writers check every addition, multiplication,
alignment, ceiling division and count-to-byte conversion in u64. Counts also
fit the implementation's bounded arena/index limits. A capacity or overflow
failure leaves output buffers, catalogs and durable roots unchanged.

The scalable format imposes no 15-file, 64-record or 4,096-byte-file limit.
Policy may impose smaller repository/file/path limits, but those are explicit
configuration and not encoded through fixed arrays.

#### Version-2 to version-3 migration

Migration is an offline, restartable transaction. It never rewrites a
version-2 object in place and never exposes a mixed-format repository. The
caller must hold exclusive repository and UXFS-volume ownership from initial
validation through publication or abort. Commands other than migration status,
continue and abort reject a repository carrying an unfinished migration.

The migration source is the complete reachable version-2 repository, including
the format record, HEAD chain, manifests, blobs, integrity records, signatures,
identity history, revocations, policy, refs and every durable workflow record.
Before allocating version-3 storage, the migrator performs the same full-chain,
path, object-size, digest, signature-structure and ref validation required by
normal version-2 readers. Corrupt, unsupported or concurrently changed source
state fails without creating a migration record.

The canonical migration-state payload is exactly 280 bytes. Before selector
publication, `.vcs/migrate3` stores this payload as an ordinary version-2 record;
after publication, the version-3 migration-state root names the same canonical
bytes:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSMIG3` |
| 8 | 2 | migration-state version, 1 |
| 10 | 2 | header bytes, 280 |
| 12 | 4 | phase |
| 16 | 8 | flags, currently zero |
| 24 | 16 | target version-3 repository UUID |
| 40 | 32 | source fingerprint |
| 72 | 8 | source HEAD sequence |
| 80 | 8 | next source commit sequence |
| 88 | 8 | converted commit count |
| 96 | 8 | converted object count |
| 104 | 32 | staged object-index root hash or zero |
| 136 | 32 | staged ref-catalog root hash or zero |
| 168 | 32 | staged ownership-catalog root hash or zero |
| 200 | 32 | staged operation-head object ID or zero |
| 232 | 8 | migration transaction sequence |
| 240 | 8 | reserved zero |
| 248 | 32 | SHA-256 of bytes 0..247 |

Phase values are 1 `PREPARED`, 2 `COPYING`, 3 `VERIFIED`, 4 `PUBLISHING` and
5 `COMMITTED`. Phase zero and unknown phases are corruption. The source
fingerprint uses the mutable-root formula from `02-hashing-and-ids.md` with root
kind 4, generation 1 and these canonical record bytes: each reachable
version-2 record in unsigned full-name order contributes
`le16(name_length) || name || le64(content_length) || exact_content`. The format
record and mutable workflow records are included; `.vcs/migrate3` itself is
excluded. A continuation recomputes the fingerprint and rejects any source
change. Counts and the next sequence are progress hints only; continuation
validates all staged roots and objects before trusting them.

Migration uses a dedicated unpublished version-3 namespace identified by the
target UUID. Every staged object has both a transaction-pin ownership edge and
a migration-pin edge whose owner key is the source fingerprint. These pins are
created in the same transaction as the object/index entry. No staged object is
eligible for reclamation while either pin exists. Allocation locators and
progress positions never enter content IDs.

The migration transaction proceeds as follows:

1. validate the complete source and reject active merge, rebase, pick, bisect or
   other mutable workflow state unless that record has a defined version-3
   encoding;
2. compute the source fingerprint, target UUID, exact upper bounds for source
   reads, destination blocks, index records and ownership edges, then reserve
   the migration-state record and all space needed for the next bounded batch;
3. publish `PREPARED` in the still-authoritative version-2 namespace;
4. create the unpublished version-3 superblock and publish `COPYING`;
5. convert commits oldest first, preserving exact parent topology, file bytes,
   messages, identities and signature evidence; after each bounded batch,
   flush its objects and catalogs before advancing durable progress;
6. build refs and mutable catalogs from the source snapshot, remove transaction
   pins only after their replacement ownership edges are durable, and publish
   `VERIFIED` only after rereading and hashing every staged object and root;
7. write and flush the complete generation-1 version-3 superblock, then publish
   `PUBLISHING` in the old namespace;
8. use one UXFS atomic-generation transaction to switch the repository selector
   from the version-2 root to the checksummed version-3 superblock;
9. after remount confirms version 3 as authoritative, record `COMMITTED` in the
   version-3 migration root and replace migration pins with normal ref,
   operation, snapshot or immutable-object ownership edges;
10. retain the version-2 namespace as rollback data until an explicit later
    finalize transaction proves there are no version-2 readers or rollback
    pins. Finalization is never implicit reclamation.

Every source commit receives a version-3 commit object and a deterministic
mapping entry keyed by the source fingerprint plus its full u64 sequence. The
mapping stores the complete 32-byte target object ID. Files are rechunked
from their exact bytes; v2 blob IDs, record order and physical allocation do not
enter v3 hashes. Existing valid Ed25519 signatures remain historical sidecars
over their original `UVCSCHK1` digest and are not relabelled as signatures of
the new commit ID. A new v3 signature requires the signer to authorize that
new ID explicitly.

Abort is permitted only in `PREPARED`, `COPYING` or `VERIFIED`. It atomically
removes the version-2 migration-state record and releases the unpublished
namespace through explicit ownership transactions after proving that no
non-migration owner references it. Disk-full during cleanup may leave a valid
abort-pending migration record; continuation retries cleanup. Abort never
modifies source objects, HEAD, refs or workflow records.

`PUBLISHING` is the point of no unilateral rollback. An interruption at or
after that phase requires remount and selector validation:

- if the version-2 selector is authoritative, the migrator returns to
  `VERIFIED` and may retry publication or abort;
- if the version-3 selector is authoritative, migration continues forward from
  `COMMITTED` and ordinary commands use only version 3;
- if neither selector and superblock pair validates, mount fails as corrupt;
- if both validate with the same selector generation, mount fails as ambiguous
  rather than choosing by timestamp or physical position.

Rollback after successful publication is a separate explicit transaction. It
is allowed only while the retained source fingerprint still matches, no v3
write transaction has committed after migration generation 1, and rollback
pins cover the complete v2 source. It atomically switches the selector back to
v2. Once a v3 write commits or v2 is finalized, downgrade is rejected; forward
migration to another version is required.

Unknown required features, arithmetic overflow, capacity exhaustion, checksum
failure, collision mismatch, source mutation or I/O failure never advance the
phase. A failure before selector publication leaves v2 authoritative. A failure
during the final barrier poisons the mount until remount establishes the
selector outcome. Recovery never guesses success from a progress counter and
never deletes either namespace merely because the other appears readable.

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

Native remotes are regular 16-byte `.vcs/remote.NAME` records. They contain the
`VCREMOT1` magic, four network-order IPv4 bytes, a nonzero host-order port, and
two reserved zero bytes. Names use 1..32 safe ASCII ref characters. Creation
and removal use an atomic UXFS volume transaction; malformed records make
remote operations fail as corrupt.

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

## Stash stack

`.vcs/stash` is a bounded `UVCSST1` file. Its 16-byte header contains the magic
and an entry count, followed by 16-byte records containing a hidden snapshot
commit ID and the HEAD ID on which it was based. Entries are ordered oldest to
newest. Hidden snapshots use the ordinary manifest, integrity, blob, and
optional signature formats, so normal validation and three-way replay apply.
Removing a stack record does not implicitly reclaim its objects.

## Bisect state

`.vcs/bisect` is an 80-byte `UVCSBIS1` record containing the original HEAD,
known-good, known-bad, current test commit, and the original active branch name.
All commit IDs are validated on every command, and GOOD must occur on BAD's
first-parent chain. State is persisted before each detached checkout. Reset
restores the recorded HEAD and branch before deleting the state record.

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
These suites are part of the active `make -C apps/vcs test` gate.

## Open Questions
