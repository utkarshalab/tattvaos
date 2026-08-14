# UWAL — Unikernel Write-Ahead Log

> General-purpose durable log for Tattva OS.

`UWAL` provides crash consistency to `udb` and any other client that needs it:
records describing a change are made durable *before* the change reaches its home
location, so recovery can redo anything the log knows about and can prove that
anything it does not know about never touched the data.

---

## 📁 Directory & File Architecture

```text
storage/uwal/
├── uwal.asm                # Master dispatcher, subsystem init/shutdown
├── uwal.inc                # Record layout, segment geometry, durability modes
├── wal.asm                 # Append path, LSN assignment, CRC32C record framing
├── segment.asm             # Segment ring: allocation, sealing, reclamation
├── recovery.asm            # Two-pass crash recovery, replay handler dispatch
└── fsync.asm               # Device barriers, group commit, block transport
```

---

## 🧱 Why UWAL is separate from `uxfs/journal`

They look redundant and are not. `uxfs` journals its own **filesystem metadata**
through its own block layer; UWAL is a durable log for **clients above the block
layer**, principally `udb`.

Merging them, or layering udb on top of the filesystem journal, produces **double
journaling** — every commit written twice, two barriers for one durability
guarantee. Ceph shipped exactly that as FileStore-on-XFS and rewrote the whole
backend as BlueStore against the raw block device to escape it. Postgres on a raw
device and InnoDB's own tablespace exist for the same reason.

This is what [`storage/README.md`](../README.md) means by *"No redundant block
layers. Direct hardware queue submission."* Each stack owns its log and addresses
the device directly.

**Consequence:** UWAL must never write through `uxfs`. It talks to the NVMe driver
directly — `uxfs` depends on UWAL's guarantees, so the reverse dependency would be
a cycle.

---

## 🔢 Record Format

A 48-byte header followed by an opaque payload.

| Field | Size | Purpose |
|---|---|---|
| `magic` | 2 | `"WR"` record sentinel |
| `type` | 1 | data / commit / abort / checkpoint / segment-end |
| `stream` | 1 | Owning client, for replay demultiplexing |
| `payload_len` | 4 | Payload bytes following the header |
| `lsn` | 8 | Log sequence number, strictly increasing, never reused |
| `prev_lsn` | 8 | Chains records; distinguishes a live tail from a stale one |
| `txn_id` | 8 | Transaction this record belongs to |
| `timestamp` | 8 | TSC at append |
| `checksum` | 4 | CRC32C over header (field zeroed) + payload |

The checksum covers the **payload as well as the header**. A header-only checksum
would accept a record whose payload never landed — precisely the torn write that
recovery exists to detect.

---

## 🔄 Two-Pass Recovery

**Pass one** scans from the checkpoint to the first record that fails
verification, recording which transactions reached a commit marker. Nothing is
applied.

**Pass two** rescans and replays only records belonging to committed
transactions. Anything without a commit is discarded — it was in flight when the
machine stopped and was never promised to anyone.

A single pass cannot do this: on reaching a data record it has no way to know
whether the commit lies ahead, so it must either apply changes it may have to
undo, or defer everything and become two passes anyway.

The scan stopping at a bad record is the **normal case**, not an error path. The
tail of a crashed log is almost always a partially-written record.

---

## ⚡ Durability Modes

| Mode | Behaviour |
|---|---|
| `UWAL_SYNC_NONE` | Buffered. A crash loses recent records. Only valid for rebuildable data. |
| `UWAL_SYNC_FLUSH` | NVMe FLUSH after commit. The default. |
| `UWAL_SYNC_FUA` | Force Unit Access: writes bypass the device cache entirely. |
| `UWAL_SYNC_BARRIER` | Flush plus store ordering. |

A write returning does **not** mean it is durable — it usually means the device
accepted it into a volatile cache that power loss discards. This is where most
"we used a WAL and still lost data" stories come from.

---

## 🚀 Group Commit

A device flush costs hundreds of microseconds, so one flush per transaction caps
the system at a few thousand commits per second regardless of CPU speed.

Group commit batches them: transactions arriving while a flush is in progress wait
for the *next* one rather than issuing their own, so N concurrent commits cost one
flush instead of N. Each commit still waits for a real barrier before being told
it succeeded.

The mechanism is an epoch counter. A caller samples it, and any barrier completing
afterwards necessarily covers that caller's record — the record was already
written before the call — so waiting for the epoch to advance is sufficient and no
waiter queue is needed.

---

## ⚠️ Ordering Rules That Must Not Be Broken

1. **Log before data.** A record must be durable before the change it describes
   reaches its home location. Reversing this makes the log useless.
2. **Checkpoint superblock before reclaiming segments.** A crash in between would
   leave segments marked reusable while the on-disk checkpoint still pointed into
   them, and recovery would read data the log had already released.
3. **Clear dirty state on completion, not submission.** Marking a write done when
   it is merely issued means a crash leaves state the system believes is durable
   and the device never received.
4. **Never reclaim a segment holding uncheckpointed records.** That discards the
   only copy of work not yet applied.

---

## 📌 Current Status

All modules assemble clean. **Not yet exercised** — `udb` is deferred, so nothing
currently appends to the log, and there is no test harness. The recovery path in
particular has never been run against a real torn write.
