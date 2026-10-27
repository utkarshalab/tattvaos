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

Connection establishment is also resumable. `vcs_sync_connect_begin` creates
the native TCP socket and starts the handshake; `vcs_sync_connect_poll` reports
success only after `TCP_STATE_ESTABLISHED`, returns `VCS_XFER_AGAIN` while the
socket remains in `SYN_SENT`, and reports an I/O error for closed or invalid
states. `unet_get_state` exposes that state without leaking `socket_table` to
applications. Callers close every completed or failed session through
`vcs_sync_close`.

### Negotiation messages

Fetch, push, and clone begin with a fixed 96-byte `UVCSREQ1` payload inside a
signed wire frame. It carries protocol version 1, operation, capability flags,
the client's current commit digest (all zero when unborn), and an optional
31-byte ref name. The peer returns a signed 96-byte `UVCSRES1` payload containing
a VCS status, bundle count, and its current head digest. Reserved bytes must be
zero and unknown capabilities are rejected. Bundle frames follow only after a
successful response.

`vcs_sync_client_begin` and `vcs_sync_client_step` implement this negotiation as
a cooperative state machine. Each step performs at most one connection or
transport operation and returns `VCS_XFER_AGAIN` when the owner should yield.
The client reaches `VC_READY` only after the response frame signature, trusted
identity, message shape, capability set, and remote status all succeed. The
state then exposes the announced bundle count and head digest for the transfer
phase. Every exit path can close the descriptor with `vcs_sync_client_close`.

`vcs_sync_server_begin` creates a bounded listener and
`vcs_sync_server_step` cooperatively accepts one peer, authenticates and decodes
its request, invokes repository policy, and transmits a signed response. A push
uses a zero-count advertisement round to obtain the remote head digest, then a
second signed request declaring 1..64 incoming bundles. Fetch and clone requests
declare zero. The policy callback chooses response status, head digest, and outgoing
bundle count before the server reaches `VS_READY`. Both accepted and listening
sockets are closed explicitly by `vcs_sync_server_close`.

After negotiation, `vcs_stream_send_begin` exports and signs one announced
commit bundle, while `vcs_stream_receive_begin` accepts exactly one frame of the
negotiated operation. `vcs_stream_step` remains cooperative; receive completion
authenticates the frame and atomically publishes the remapped commit before
returning its local ID. The current implementation owns one 256 KiB transfer
buffer and therefore permits one active peer stream at a time.

Range planning walks bounded first-parent history and matches the peer's digest
against either a local integrity object or a `UVCSMAP1` source mapping. It emits
at most 64 commit IDs in oldest-to-newest order. A nonzero digest absent from
the selected ancestry is a divergence error rather than an implicit overwrite.

### Repository bundle payload

Wire frames carry a `UVCSBND1` payload. Its 96-byte header records the version,
exact total length, record count, source tip and first-parent IDs, the parent's
32-byte integrity digest, and flags. Bounded
records then contain a kind, source object ID, byte length, and exact bytes.
Version 1 carries one first-parent commit: its manifest, SHA-256 record,
optional Ed25519 signature, and exactly one blob per manifest entry.

`vcs_bundle_export` validates the local commit and completes capacity preflight
before writing. `vcs_bundle_validate` is side-effect free and rejects truncated
or trailing bytes, duplicate records or paths, unsafe paths, malformed IDs or
messages, merge manifests, blob-size mismatches, integrity failures, and bad
signatures. Source IDs are transport metadata; publication must map them into
the destination repository rather than trusting remote sequence numbers.

After a wire frame has passed trusted-signer authentication,
`vcs_bundle_publish` resolves the source parent through its integrity digest,
allocates a new monotonic destination ID, rewrites the manifest and blob IDs,
recomputes the destination digest, and publishes every record plus the new
`last_id` in one UXFS transaction. It deliberately leaves HEAD and refs
unchanged. Repository signing policy is enforced; an optional local seed signs
the remapped commit because the source signature cannot authenticate rewritten
local IDs. A `UVCSMAP1` sidecar retains the signed source digest so subsequent
bundles can resolve parents after remapping. Callers must not pass
unauthenticated payloads to this internal API.

## Test Vectors

Deferred to the requested final validation pass.

## Open Questions

- Missing-object negotiation and ref-update leases.
- Multi-frame repositories larger than the bounded payload.
- Per-ref server authorization policy.
