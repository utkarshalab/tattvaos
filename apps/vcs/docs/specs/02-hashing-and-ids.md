# Hashing and IDs

- Status: Scalable v1 hashing frozen
- Version: 1.0
- Owner: Utkarsha Lab

## Scope

Cryptographic identities for scalable VCS objects, repository roots, keys and
storage records. Version-2 repository sequence IDs remain local identifiers and
are not converted into content IDs.

## Hash algorithm registry

| ID | Algorithm | Status |
| ---: | --- | --- |
| 1 | SHA-256 | required for scalable format v3 |
| 2 | BLAKE3-256 | reserved until the shared implementation passes official vectors and scalar/SIMD parity |

Format v3 writers use algorithm 1. Readers reject any algorithm not enabled by
the repository feature set. Digests are stored as the algorithm's raw 32 bytes;
hexadecimal presentation is 64 lowercase digits and is never hashed as text.

SHA-256 uses the streaming implementation from `lib/crypto/uhash/sha256`.
Callers must check all length arithmetic before passing buffers. Digest equality
for integrity, identity and trust decisions compares all 32 bytes without an
early exit.

## Immutable object IDs

An immutable object ID is:

```text
SHA-256(
    "UVCSHSH1"                         # 8 bytes
    || le16(1)                         # hash framing version
    || le16(object_type)               # codes from 01-object-model.md
    || le32(0)                         # reserved
    || le64(payload_length)
    || canonical_payload
)
```

The framing prefix is exactly 24 bytes before the payload. Object type is part
of the preimage, so equal bytes used as a chunk, tree or message cannot alias.
The common storage header and physical extent layout are not hashed. Canonical
payload validation occurs before an ID is accepted as an object reference.

An object filename or index key may shard on ID bytes but must retain and verify
the complete 32-byte ID. Prefixes never establish equality or trust.

## Reconstructed file-byte hash

The file-root byte hash is:

```text
SHA-256("UVCSBYT1" || le64(file_length) || exact_file_bytes)
```

The prefix is 16 bytes before data. This hash verifies page/chunk reconstruction
and is distinct from the file-root object ID. Empty files hash the prefix with a
zero length and no data.

## Repository identity

Every scalable repository receives a 16-byte random UUID from the native CSPRNG
during format-v3 creation or migration. All-zero is invalid. The UUID is not a
security secret and is never derived from a path, clock or sequence number.

Repository-local monotonic sequences identify transactions and operation order,
not immutable content. Overflow is a permanent capacity error; sequences never
wrap, reset or reuse a committed value.

## Stable change IDs

A new logical change receives 16 random bytes from the native CSPRNG. All-zero
is invalid. Rebase/amend copies the same change ID into the replacement commit
and change object; it never derives a stable ID from a mutable commit ID. The
repository rejects a newly created duplicate change ID before publication.

If the native CSPRNG is unavailable, creating a stacked change fails. It must
not fall back to a timestamp, counter, address, TSC or noncryptographic PRNG.

## Key IDs

An Ed25519 public-key ID is:

```text
SHA-256("UVCSKEY1" || le32(1) || le32(32) || public_key[32])
```

The prefix is 16 bytes. The complete public key remains in identity/signature
records and is compared after key-ID lookup. A key-ID collision is an explicit
conflict, never an identity match.

## Mutable-root hashes

Refs and ownership catalogs are mutable storage records. Their root hash is:

```text
SHA-256(
    "UVCSROT1"
    || le16(1)
    || le16(root_kind)
    || le32(0)
    || le64(generation)
    || le64(canonical_record_bytes)
    || canonical_record_bytes
)
```

Root kinds are 1 refs, 2 ownership, 3 operation head and 4 migration state.
The hash authenticates a specific generation but does not make mutable records
content objects. The repository superblock stores each root and generation that
must be published together.

## UXFS subtree hashes

The scalable UXFS subtree-hash ABI is not available yet. VCS object IDs therefore
remain independently domain-separated SHA-256 values. A future UXFS hash may be
stored alongside a VCS root only after its algorithm, canonical tree encoding,
generation semantics and vectors are frozen. It must never be silently treated
as a VCS object ID because both happen to be 32 bytes.

## Legacy compatibility

Version-2 `h` sidecars remain:

```text
SHA-256("UVCSCHK1" || exact_manifest || referenced_blob_bytes_in_manifest_order)
```

They authenticate the bounded legacy snapshot and are not scalable object IDs.
Migration validates this digest before creating any format-v3 object. Existing
Ed25519 signatures over the sidecar remain historical evidence; migration may
add a new signature over the resulting commit ID but cannot rewrite the old
signature's meaning.

## Verification rules

1. Validate algorithm, type and all lengths before hashing.
2. Stream bytes in canonical order; never hash native structs or uninitialized
   padding.
3. Recompute the complete digest when loading from untrusted storage.
4. Compare all digest bytes and reject a mismatched expected type.
5. Do not authorize, deduplicate or reclaim from a truncated digest.
6. Deduplication verifies payload length and exact bytes after an ID match.
7. Hash failure or unavailable implementation is fatal; there is no weak-hash
   fallback.

## Required test vectors

- Empty and one-byte payload object frames for every object type.
- Chunk lengths 2,048, 8,192 and 32,768 with fixed byte patterns.
- Empty and multi-page reconstructed file hashes.
- Public-key and mutable-root hash vectors.
- Every legacy `UVCSCHK1` vector currently accepted by version 2.
- One-bit changes in every framing field, payload and reserved field.
- Streaming splits at every byte for short vectors and block boundaries for
  large vectors.
- Cross-check every SHA-256 result with an independent implementation.

## Open questions

- BLAKE3 remains reserved until its shared library path is independently
  qualified; enabling it requires a repository feature bit and migration plan.
