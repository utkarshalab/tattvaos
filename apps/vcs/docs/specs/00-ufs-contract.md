# UXFS Interface Contract for VCS

- Status: Active bounded ABI inventoried; scalable ABI blocked
- Version: 0.1
- Owner: Utkarsha Lab

## Scope

This contract records only storage interfaces that VCS may safely call today
and the missing UXFS guarantees required by the scalable object store. A global
assembly symbol is not considered available merely because it exists: it must
have a stable include-level ABI, persistent semantics, error behavior, recovery
tests and integration in the production VCS/UXFS build.

The active VCS backend is `lib/storage/uxfs/volume.asm`, whose public names use
the `uxv_*` prefix. The wider `lib/storage/uxfs/uxfs.asm` tree uses `uxfs_*` and
contains future filesystem components. Those two interfaces are not
interchangeable.

## Active bounded volume ABI

### Fixed format

`lib/storage/uxfs/volume.inc` defines the complete active layout:

| Constant | Value | Meaning |
| --- | ---: | --- |
| `UV_NODES` | 64 | Total fixed records, including root |
| `UV_NODE` | 4,352 | Bytes per record |
| `UV_DATA` | 256 | Data offset inside a record |
| `UV_TYPE` | 240 | Record type offset |
| `UV_SIZE` | 248 | Logical data-size offset |
| maximum file payload | 4,096 | Bytes after `UV_DATA` |
| path field | 240 | NUL-terminated canonical absolute path |
| `UV_MAGIC` | `UFXVOLV2` | Little-endian bank-header magic |

Record type zero is free, one is a regular file and two is a directory. Slot
zero must be the root directory `/`. Every live non-root record must have a
unique canonical absolute path and every proper prefix must resolve to a live
directory.

### Backend callbacks

Before mount, the owner supplies these SysV function pointers:

| Variable | Call ABI | Required result |
| --- | --- | --- |
| `uxv_read` | `rdi=LBA`, `rsi=sector count`, `rdx=buffer` | nonnegative success; negative failure |
| `uxv_write` | `rdi=LBA`, `rsi=sector count`, `rdx=buffer` | nonnegative success; negative failure |
| `uxv_flush` | no arguments | nonnegative durable success; negative failure |

All three callbacks are mandatory for `uxv_mount`. Buffers are borrowed only
for the duration of the call. The implementation is BSP-serialized; it does not
promise reentrancy or concurrent writers.

### Callable operations

| Symbol | Inputs | Result and guarantee |
| --- | --- | --- |
| `uxv_mount` | callbacks already installed | `0` when one valid bank is published; `-1` otherwise |
| `uxv_commit` | mutations already staged in `uxv_nodes` | `0` after inactive body and header each pass a durable flush; `-5` on failure |
| `uxv_sync` | none | flush result; a negative result disables the mount |
| `uxv_find` | `rdi` canonical absolute path | record pointer or zero; preserves `rdi/rsi` |
| `uxv_free` | none | first free non-root record pointer or zero |
| `uxv_normalize` | `rdi` input path, `rsi` 240-byte output | zero on success, nonzero on invalid or missing traversal |

`uxv_ready` equals one only while the mounted image is usable. `uxv_nodes` is
the complete mutable in-memory image and `uxv_cwd` is the canonical working
directory used by normalization.

### Commit and recovery semantics

The disk holds two complete banks. Each bank contains a 512-byte header followed
by the fixed record image. The header contains format version two, a strictly
positive generation, a body checksum and a header checksum. FNV-1a protects
against accidental corruption only; it is not an authentication primitive.

Mount reads and validates both banks, validates every record and the complete
namespace, and publishes only the valid bank with the highest generation.
Commit writes the inactive body, flushes it, writes the checksummed header and
flushes again. Only then does it switch the active generation in memory.

If any commit write or flush fails, `uxv_ready` becomes zero. The caller must
not continue using the in-memory image or claim rollback: a final flush may
have failed after bytes reached media. Remount selects the newest complete
valid bank. The previously active bank is never overwritten by that commit.

This is an atomic whole-volume publication mechanism, not a general nested
transaction API. Callers modify `uxv_nodes` directly and are responsible for
prevalidating capacity, names and object relationships before `uxv_commit`.

## Capability inventory

| Enterprise requirement | Active status | Evidence and decision |
| --- | --- | --- |
| Durable flush | **Available** | mandatory `uxv_flush`; used twice by `uxv_commit` |
| Atomic publication | **Available, bounded** | dual-bank whole-image generation swap |
| Record lookup | **Available, bounded** | `uxv_find` over 64 records |
| Record allocation | **Available, bounded** | `uxv_free`; no persistent dynamic allocator |
| Namespace validation | **Available, bounded** | mount rejects invalid paths, parents and duplicates |
| Crash recovery | **Available, bounded** | newest valid bank wins; torn bank is ignored |
| General transactions | **Missing** | no begin/commit/abort or isolated write set |
| Dynamic block allocation | **Missing from active ABI** | `uxfs_ag_*` is not integrated with `uxv_*` persistence |
| Persistent journal cursor | **Missing** | no VCS-callable changed-path cursor or durable replay ABI |
| Filesystem snapshots | **Missing from active ABI** | prototype snapshot table is RAM-only and not flushed |
| Subtree hash query | **Missing** | no callable path-to-authenticated-subtree-hash operation |
| Extent/reflink API | **Missing from active ABI** | prototype VFS/extent modules have no frozen VCS contract |
| Lazy hydration | **Missing** | no bounded page/object fault callback contract |
| Quotas | **Missing from active ABI** | quota prototypes are not tied to durable allocation |
| Persistent ownership/refcounts | **Missing** | required before explicit reclamation can scale |

## Prototype `uxfs_*` symbols are not yet contractual

The master UXFS tree exposes promising symbols, but VCS must not call them until
their persistence and build contracts are completed:

- `uxfs_ag_alloc_block` and `uxfs_ag_free_block` currently manage a fixed
  in-memory bitmap. The bitmap is not mounted from or committed to the active
  VCS volume and therefore cannot own durable VCS objects.
- `uxfs_journal_start_tx`, `uxfs_journal_commit_tx` and
  `uxfs_journal_replay` operate on caller-provided memory blocks. They do not
  write a journal ring, flush media, publish a root, expose changed paths or
  verify a complete durable transaction during replay.
- `uxfs_snapshot_create` and `uxfs_snapshot_rollback` use a fixed RAM table.
  Snapshot names are not persisted, creation does not publish storage, and
  rollback only changes the supplied superblock memory.
- `uxfs_mount` validates only the superblock magic. It does not establish the
  allocator, journal, tree, snapshot or recovery guarantees required here.

These modules may become the scalable backend after they receive stable headers,
durable layouts, failure semantics, integrated tests and a migration path. Their
current presence does not satisfy a roadmap checkbox by itself.

## Required scalable UXFS ABI

Milestone 1 cannot freeze the scalable object layout until UXFS provides or VCS
implements a tested native contract for the following operations. Names below
describe semantics, not predetermined symbol names.

### Volume and transaction

- Mount a versioned volume and return a validated opaque volume handle.
- Begin one isolated transaction with an explicit maximum write budget.
- Allocate and free blocks inside that transaction without exposing them before
  commit.
- Read and write exact bounded byte ranges with checked 64-bit offsets.
- Atomically publish a new root generation after all referenced blocks are
  durable.
- Abort without publishing allocations or metadata.
- Flush and report whether durability is guaranteed or the mount is poisoned.
- Remount after interruption to either the old or complete new generation.

### Journal and snapshots

- Open a durable journal cursor tied to a validated generation.
- Enumerate changed paths with bounded records and explicit overflow/rescan
  behavior.
- Create, open, list and delete persistent snapshots by immutable ID.
- Roll back or clone through a transaction; never mutate a live root pointer in
  place without durable publication.

### Hashes, extents and ownership

- Query a domain-separated authenticated subtree hash and its generation.
- Create/read extent lists and reflink immutable extents transactionally.
- Store durable owner counts or owner records for every shared block/object.
- Refuse reclamation while any live tree, snapshot, transaction or reader owns
  the object.
- Detect counter overflow, underflow, double-free and stale-generation handles.

## Error contract required for the scalable ABI

Every operation must use one documented signed result convention. At minimum it
must distinguish invalid arguments, corruption, not found, no space, I/O,
permission, stale generation, conflict/retry and unsupported feature. A failed
operation must state whether the transaction remains usable, must abort, or has
poisoned the mount. No success-only placeholder is acceptable.

All length, count, block and offset arithmetic must reject overflow before any
read, write or allocation. Capacity errors must be atomic: outputs and durable
state remain unchanged.

## Validation obligations

The current `uxv_*` ABI is covered indirectly and directly by the VCS repository
tests, including dual-bank selection, torn writes, flush failures, corruption,
capacity and recovery. The scalable ABI must add:

1. executable ABI vectors for every structure and error;
2. power-cut injection before and after every write and flush;
3. allocator persistence, double-free and ownership tests;
4. journal wrap, replay, stale cursor and overflow tests;
5. snapshot create/delete/clone/rollback recovery tests;
6. subtree-hash differential vectors;
7. migration interruption and rollback tests;
8. fuzzing of every persistent reader before VCS writes enterprise objects.

## Decisions unblocked by this inventory

- VCS may continue using `uxv_*` for the bounded repository while the scalable
  backend is developed.
- The current dual-bank algorithm is a valid recovery oracle for migration tests
  but cannot scale by enlarging the fixed image indefinitely.
- Chunk lists, paged trees and ownership records must target a new scalable
  transaction ABI, not direct mutation of prototype UXFS global tables.
- The next roadmap task is to freeze versioned scalable VCS object and ownership
  records against the required ABI above; missing UXFS operations must be
  implemented and tested before production integration.

## Open questions

1. Whether the scalable transaction/journal implementation lives entirely in
   UXFS or exposes a lower block API used by a VCS-owned object transaction.
2. Whether subtree hashes use the VCS object hash directly or a separately
   domain-separated UXFS root that VCS records alongside its own ID.
3. Whether ownership is stored as exact owner records, bounded refcounts plus
   audit records, or both.
4. Which persistent snapshot and journal layouts UXFS will freeze first.
