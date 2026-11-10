# Object Model

- Status: Scalable v1 encoding frozen
- Version: 1.0
- Owner: Utkarsha Lab

## Scope

Canonical architecture-independent encodings for immutable VCS objects. This
model is the destination of repository format version 3. Existing version-2
manifests and sidecars remain defined by `04-storage-layout.md` and are never
reinterpreted as these objects.

All integers are unsigned little-endian unless a field explicitly says signed.
There is no native padding, pointer, register-sized integer or host byte order
on disk. Reserved bytes are zero when written and must be zero when read.

## Common rules

- Every immutable object has a 32-byte content ID defined by
  `02-hashing-and-ids.md`.
- Canonical payload length is a u64, but every object type imposes a smaller
  bound before allocation or hashing.
- Object references always contain the complete 32-byte ID; truncated IDs are
  display and namespace conveniences only.
- Strings are byte sequences with an explicit length and no terminator. Names
  and paths are UTF-8 or portable ASCII as required below; messages are opaque
  non-NUL bytes.
- Unknown type, version, flag or nonzero reserved fields are rejected unless a
  later repository feature explicitly makes them optional.
- Immutable objects are never changed in place. A logical edit creates new
  objects and atomically changes a mutable root or ref.
- Reclamation is explicit ownership accounting. No object is freed by tracing
  or background garbage collection.

## Object type codes

| Code | Name | Payload |
| ---: | --- | --- |
| 1 | chunk | exact file bytes |
| 2 | file root | ordered chunk-page index and total file metadata |
| 3 | tree root | ordered tree-page index and directory metadata |
| 4 | commit | tree, parents, change identity, author and message |
| 5 | change | stable change metadata across rewritten commits |
| 6 | conflict | immutable base/ours/theirs path conflict |
| 7 | operation | immutable operation-log event |
| 8 | signature | signature over another immutable object ID |
| 9 | file page | bounded ordered chunk references |
| 10 | tree page | bounded ordered directory entries |

Codes 11 through 255 are reserved. Mutable refs and ownership edges are storage
records, not content objects, and are defined by `04-storage-layout.md`.

## Chunk object: type 1

The canonical payload is the exact chunk bytes with length 1 through 32,768.
Empty files have a file root with zero chunks; an empty chunk object is invalid.
Chunk boundaries follow `03-chunking.md`. Identical bytes have the same object
ID regardless of file, path, offset or repository.

## File page object: type 9

A file page payload is exactly `64 + entry_count*40` bytes and never exceeds
4,064 bytes. Therefore `entry_count` is 1 through 100.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSFPG1` |
| 8 | 4 | page index, starting at zero |
| 12 | 4 | entry count, 1..100 |
| 16 | 8 | first file byte offset represented by this page |
| 24 | 8 | total bytes represented by this page |
| 32 | 32 | next file-page ID, all zero for the final page |
| 64 | 40 each | chunk entries |

Each chunk entry is a 32-byte chunk ID followed by an 8-byte chunk length.
Lengths are 1..32,768. Offsets are implicit cumulative sums. The sum must equal
the page byte count without u64 overflow. Page indexes increase by one and next
links must terminate after the file root's declared page count.

## File root object: type 2

The payload is exactly 128 bytes.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSFIL1` |
| 8 | 4 | mode bits; only the frozen portable mask is allowed |
| 12 | 4 | flags; bit 0 executable, bit 1 generated, others zero |
| 16 | 8 | exact logical byte length |
| 24 | 8 | total chunk count |
| 32 | 8 | file-page count |
| 40 | 8 | reserved zero |
| 48 | 32 | first file-page ID; zero only for an empty file |
| 80 | 32 | hash of exact reconstructed file bytes |
| 112 | 16 | reserved zero |

An empty file has zero length/count/pages and zero first-page ID. A nonempty
file has all three counts nonzero. Walking its page chain must consume exactly
the declared pages, chunks and bytes, end in a zero next ID and reproduce the
stored byte hash. File roots do not contain a path.

## Tree page object: type 10

A tree page payload starts with a 64-byte header and contains complete variable
entries. It is at most 4,064 bytes; an entry never crosses a page.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSTPG1` |
| 8 | 4 | page index, starting at zero |
| 12 | 4 | entry count, 1..64 |
| 16 | 8 | encoded entry bytes after this header |
| 24 | 8 | reserved zero |
| 32 | 32 | next tree-page ID, zero for final page |

Each entry is `48 + align8(name_length)` bytes:

| Relative offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | target kind: 2 file root or 3 tree root |
| 1 | 1 | name length, 1..240 |
| 2 | 2 | portable mode bits |
| 4 | 4 | flags, currently zero |
| 8 | 8 | target logical size; file bytes or immediate entry count |
| 16 | 32 | complete target object ID |
| 48 | variable | name bytes followed by zero alignment padding |

Names contain no NUL, slash, control byte, DEL, empty/dot/dot-dot component or
`.vcs` component. Entries across the complete page chain are strictly sorted by
unsigned name bytes; duplicates and alternate encodings are invalid.

## Tree root object: type 3

The payload is exactly 96 bytes.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSTRE1` |
| 8 | 8 | immediate entry count |
| 16 | 8 | tree-page count |
| 24 | 8 | flags, currently zero |
| 32 | 32 | first tree-page ID; zero only for an empty tree |
| 64 | 32 | reserved zero |

Empty directories have zero entries/pages and a zero first-page ID. Trees are
hierarchical by directory, so paths never appear in a tree object.

## Commit object: type 4

The payload is `256 + message_length` bytes. Message length is 1..65,535 and
messages contain no NUL. Parent count is 0..2.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSCOM3` |
| 8 | 4 | flags: bit 0 merge, bit 1 signed-required; others zero |
| 12 | 4 | parent count |
| 16 | 8 | generation: one plus maximum parent generation |
| 24 | 8 | signed timestamp nanoseconds; zero means unavailable |
| 32 | 4 | signed UTC offset minutes |
| 36 | 4 | message length |
| 40 | 32 | root tree ID |
| 72 | 32 | first parent ID or zero |
| 104 | 32 | second parent ID or zero |
| 136 | 16 | stable change ID or zero when not part of a stack |
| 152 | 32 | author key ID or zero for an unsigned local identity |
| 184 | 32 | committer key ID or zero |
| 216 | 40 | reserved zero |
| 256 | variable | exact message bytes |

Root commits have zero parents and generation one. Ordinary commits have one
parent, while merge commits have two distinct nonzero parents with merge flag
bit 0 set.
Generation is validated from parents and is not trusted as an authorization
claim. Time zero is canonical when no trusted wall clock exists.

## Change object: type 5

The payload is `96 + title_length` bytes. It records a stable logical change
across rebases without making mutable commit objects.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSCHG1` |
| 8 | 16 | 128-bit random change ID from the native CSPRNG |
| 24 | 32 | current commit ID at creation time |
| 56 | 32 | creator key ID or zero |
| 88 | 4 | title length, 1..4,096 |
| 92 | 4 | flags, currently zero |
| 96 | variable | title bytes without NUL |

The stable ID is copied when a new change object supersedes an older one. Ref
state selects the current object; existing change objects remain immutable.

## Conflict object: type 6

The payload is `144 + path_length` bytes.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSCNF3` |
| 8 | 4 | conflict kind |
| 12 | 4 | path length, 1..4,096 |
| 16 | 32 | base object ID or zero for absent |
| 48 | 32 | ours object ID or zero for absent |
| 80 | 32 | theirs object ID or zero for absent |
| 112 | 32 | resolution object ID or zero while unresolved |
| 144 | variable | canonical repository-relative path bytes |

Kinds are 1 content, 2 modify/delete, 3 rename/rename, 4 rename/delete and 5
mode. Unknown kinds are rejected. Resolution creates a new conflict object.

## Operation object: type 7

The payload is `192 + argument_length` bytes.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSOPR1` |
| 8 | 8 | monotonic repository operation sequence |
| 16 | 8 | signed timestamp nanoseconds; zero when unavailable |
| 24 | 4 | operation kind |
| 28 | 4 | flags, currently zero |
| 32 | 32 | previous operation ID or zero |
| 64 | 32 | before ref-root ID |
| 96 | 32 | after ref-root ID |
| 128 | 32 | actor key ID or zero |
| 160 | 4 | argument length, 0..65,535 |
| 164 | 28 | reserved zero |
| 192 | variable | canonical operation argument bytes |

Undo appends another operation selecting an earlier root; it never deletes or
mutates the operation being undone.

## Signature object: type 8

The version-1 payload is exactly 176 bytes and uses Ed25519 algorithm 1.

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 8 | ASCII `UVCSSIG3` |
| 8 | 4 | algorithm, 1 Ed25519 |
| 12 | 4 | flags, currently zero |
| 16 | 32 | signed immutable object ID |
| 48 | 32 | signer key ID |
| 80 | 32 | complete Ed25519 public key |
| 112 | 64 | signature bytes |

The signature input is the 32-byte target ID, not a path or mutable ref. The key
ID must match the domain-separated public-key hash and trust/revocation policy
must be evaluated separately.

## Validation order

Readers validate bounds and arithmetic, type/version/flags, exact payload size,
reserved zeroes and local field relationships before following any reference.
They then load referenced objects with expected types, verify every content ID,
and finally validate aggregate counts, lengths, ordering and termination.
Failure publishes no partial caller output.

## Test vectors required before implementation completes

1. Empty and maximum-size canonical objects of every type.
2. Exact byte encodings and SHA-256 IDs for one object of every type.
3. File chains spanning multiple pages and a multi-level tree.
4. Reordered, duplicate, cyclic, truncated and overlong references.
5. Every u64 addition/multiplication overflow boundary.
6. Unknown flags, nonzero reserved bytes and cross-type ID substitution.
7. Signature acceptance, tampering, untrusted key and revoked key cases.

## Open questions

- The portable mode-bit mask must be finalized with the UXFS inode contract.
- Change IDs require the native CSPRNG ABI before stacked changes become active.
