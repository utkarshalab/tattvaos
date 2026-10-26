# Wire Protocol

- Status: Implemented core framing; repository negotiation pending
- Version: 1
- Owner: TBD

## Scope

Negotiation, partial fetch, push, land, streaming, resumable transfer.

## Definitions

The native protocol runs over non-blocking `unet` streams. A transport
callback returns `-1` when the caller must yield and retry, zero for a broken
connection, or the positive number of bytes transferred.

## Specification

Every transfer starts with a fixed 160-byte little-endian `UVBNDLE1` header:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | magic |
| 8 | 4 | version (`1`) |
| 12 | 4 | fetch, push, clone, or patch operation |
| 16 | 8 | payload byte length |
| 24 | 8 | object count |
| 32 | 8 | repository identity |
| 40 | 32 | SHA-256 over metadata bytes 0..39 and payload |
| 72 | 32 | Ed25519 signer public key |
| 104 | 64 | Ed25519 signature of the digest |

Payloads are bounded to 256 KiB. Receivers reject unknown versions or
operations, empty or oversized payloads, digest mismatches, untrusted keys,
and invalid signatures before import. A trust callback is mandatory, so
transport authentication cannot silently degrade to accepting any signer.

`vcs_sync_step` performs at most one transport callback. The owning Ush task
or fiber yields between `VCS_XFER_AGAIN` results.

## Test Vectors

Deferred to the requested final validation pass.

## Open Questions

- Missing-object negotiation and ref-update leases.
- Multi-frame repositories larger than the bounded payload.
- Per-ref server authorization policy.
