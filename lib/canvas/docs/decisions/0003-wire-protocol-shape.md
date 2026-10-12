# Decision 0003: Wire Protocol Shape — Binary, Versioned, Handles Separate

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (implemented C4)

## Context
Need a wire protocol for client↔server communication (CWP — Canvas Wire Protocol).

## Decision
**CWP Wire Format**:
```
Message Header (12 bytes):
  u32 object      ; generation-tagged handle
  u16 opcode      ; interface-specific
  u16 flags       ; NEED_ACK=1, HAS_HANDLES=2, IS_EVENT=4, TRANSACTION=8
  u32 length      ; payload bytes (4-byte aligned)

Payload: length bytes, 4-byte aligned

Handles: SEPARATE channel (SPSC ring of u32[16] messages)
```

**Key properties**:
- Binary, fixed-width, no varints
- Every interface versioned; negotiate at connect
- Capability bitmap granted at handshake — ungranted interfaces invisible
- No registry round-trip (unlike Wayland `wl_registry`)
- Flow control: bounded rings, slow client throttled → disconnected
- Errors: per-client error object, disconnect only that client

## Rationale
| Alternative | Why Rejected |
|-------------|--------------|
| **Wayland (wl_protocol)** | Registry round-trip, fd passing in payload, no flow control, C ABI assumed |
| **X11 (X protocol)** | Request/reply model = round trips, no explicit sync, string atoms |
| **Cap'n Proto / FlatBuffers** | Schema compilation complexity, not assembly-friendly |
| **Custom text/JSON** | Parsing overhead, ambiguity, no binary efficiency |
| **D-Bus** | Daemon, serialization overhead, not for display hot path |

**Handles separate from payload** because:
- No fd passing (single address space)
- Handle validation on receive (generation check) before payload decode
- Allows zero-copy buffer sharing: handle = buffer object, payload = metadata only
- Simplifies fuzzing: handle channel and payload channel tested independently

## Consequences
- `cwpgen` (C4) generates: opcode enums, struct definitions, encode/decode, dispatch tables
- Client library (`canvas_client.o`) uses same generated code
- `tests/fuzz/fuzz_wire.asm` fuzzes both channels independently
- Protocol version in `proto/VERSION` — bump on any wire change

## Implementation
- `inc/cwp.inc` — Header, flags, base opcodes
- `inc/caps.inc` — Capability bit definitions
- `proto/*.cwp` — Interface definitions (source of truth)
- `src/proto/wire.asm` — Framing, encode, decode
- `src/proto/channel.asm` — SPSC rings for payload + handles
- `tools/cwpgen.asm` — IDL compiler (written in assembly)

## Related
- `architecture.md` §4
- Decision 0004 (generation handles), 0006 (explicit sync)
- `proto/canvas-core.cwp` — Core interfaces

## Revisit Criteria
If protocol evolution requires breaking wire format → major version bump, new `canvas_client.o`, old clients disconnected at connect.