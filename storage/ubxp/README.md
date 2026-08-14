# UBXP — Unikernel Binary eXchange Protocol

> Binary serialization format for storage and network.

`UBXP` is the wire and storage encoding shared across Tattva OS: `udb` record
storage, `uobject` metadata, and the `urpc` wire protocol. It is a tagged,
length-delimited format built for zero-copy decoding and forward compatibility.

> **Naming:** UBXP is **not** the boot-time `BXP` (Boot eXecution Package) image
> format in [`boot/stage2/fs/bxp.asm`](../../boot/stage2/fs/bxp.asm). That
> format owns the bare `BXP_` prefix; everything here is prefixed `UBXP_`/`ubxp_`
> so the two can coexist in a single-unit kernel build.

---

## 📁 Directory & File Architecture

```text
storage/ubxp/
├── ubxp.asm                # Master dispatcher, CPU probe, encode entry points
├── ubxp.inc                # Wire constants, frame layout, cursor/descriptor structs
├── frame/                  # Framing & Integrity Layer
│   ├── varint.asm          # LEB128 codec + zig-zag signed mapping
│   └── frame.asm           # Header emit/validate, length patching, CRC32C
├── types/                  # Type System
│   ├── primitive.asm       # bool, uint, zig-zag int, fixed32/fixed64
│   ├── bytes.asm           # Length-delimited blobs & UTF-8 strings (zero-copy)
│   ├── nested.asm          # Submessage open/close, bounded sub-cursor descent
│   ├── repeated.asm        # Packed scalar arrays & tag-per-element repeats
│   └── map.asm             # Key/value maps as repeated {key=1, value=2} entries
├── schema/                 # Schema Evolution Layer
│   ├── schema.asm          # Field tag packing & wire-type dispatch
│   ├── evolution.asm       # Unknown-field skipping, nesting caps, versioning
│   ├── unknown.asm         # Verbatim unknown-field retention & replay
│   ├── descriptor.asm      # Reflection tables, validation, presence, enums
│   └── canonical.asm       # Deterministic-encoding verification
├── debug/
│   └── dump.asm            # Human-readable frame rendering
└── tests/
    └── roundtrip.asm       # Self-checking round-trip suite (excluded from kernel)
```

---

## 🧩 Frame Structure

A frame is a 24-byte header followed by a body of tagged fields.

| Offset | Size | Field | Notes |
|---|---|---|---|
| `0x00` | 4 | `magic` | `"UBXP"` (`0x50584255`) |
| `0x04` | 1 | `version` | Current wire version (`1`) |
| `0x05` | 1 | `flags` | `UBXP_FLAG_*` bitmask |
| `0x06` | 2 | `reserved` | Must be zero |
| `0x08` | 4 | `payload_len` | Body length, excluding this header |
| `0x0C` | 4 | `schema_id` | Schema identifier |
| `0x10` | 4 | `crc32` | CRC32C of body, when `CRC_PRESENT` |
| `0x14` | 4 | `field_count` | Top-level field count |

`payload_len`, `crc32` and `field_count` are written as zero and back-patched by
`ubxp_frame_finalize` once the body length is known, so encoding stays a single
forward pass with no size pre-computation.

---

## 🔢 Type System

Every value carries a **wire type** in the low 3 bits of its field tag
(`tag = (field_number << 3) | wire_type`):

| Wire type | Value | Shape |
|---|---|---|
| `UBXP_WIRE_VARINT` | 0 | LEB128, 1–10 bytes |
| `UBXP_WIRE_FIXED64` | 1 | 8 raw little-endian bytes |
| `UBXP_WIRE_BYTES` | 2 | varint length + payload |
| `UBXP_WIRE_CONTAINER` | 3 | Nested frame, length-prefixed |
| `UBXP_WIRE_FIXED32` | 5 | 4 raw little-endian bytes |

Signed integers are **zig-zag** mapped before varint encoding, so `-1` costs one
byte rather than ten. IEEE-754 doubles ride the `FIXED64` path as a raw bit
pattern, which keeps the codec clear of x87/SSE state.

---

## 🔄 Schema Evolution Contract

1. **Readers skip unknown field numbers** rather than failing — the wire type in
   the tag tells a decoder how wide an unrecognised value is even when it has no
   idea what the value means. This is what lets an old reader consume a new
   writer's frame.
2. **Retired field numbers are never reused**, so a stale reader can never
   mistake a new field for an old one.
3. **Wire types are never changed in place.** A changed representation takes a
   new field number.
4. **Older frame versions are accepted; newer ones are refused** — a newer writer
   may use a wire type this build cannot even skip safely.

---

## ⚡ Implementation Notes

- **Bounds-checked cursor.** Every read and write goes through `ubxp_cursor_t`,
  which holds an absolute end pointer so a bounds check is one compare.
- **Sticky errors.** The first failure latches into the cursor and every later
  call short-circuits, so a caller may encode an entire message and check for
  failure exactly once at the end.
- **Zero-copy reads.** `ubxp_read_bytes` returns a pointer into the caller's own
  input buffer plus a length — no allocation, no copy.
- **Bounded decoding.** Varints stop after 10 bytes, payloads are capped at 16MB,
  and container recursion is capped at 32 levels, so a malformed or hostile frame
  cannot spin or exhaust a caller's stack.
- **Hardware CRC32C** via the SSE4.2 `crc32` instruction, probed once by
  `ubxp_init`. Self-contained rather than delegating to `lib/ucmp`, so a frame can
  be validated without pulling in the compression subsystem.

---

## 🔁 Unknown-Field Retention

Skipping an unknown field is enough to **read** a newer frame. It is not enough to
**forward** one. A relay that decodes, skips what it does not understand, and
re-encodes silently strips every field added after its schema was frozen — and the
sender believes the data arrived.

`schema/unknown.asm` closes that hole: raw tag-and-value bytes are copied aside
exactly as they arrived and replayed on re-encode, so a field survives a hop
through a process that has no idea what it means. On sink overflow the store
latches `truncated` rather than failing, so the degradation is visible instead of
silent. This matters most for `urpc`, where intermediaries are routinely older
than the endpoints they sit between.

---

## ⚠️ Known Limitations

- **Nested frames are not canonical.** `ubxp_submsg_begin` reserves a fixed
  four-byte length slot so encoding stays single-pass; short lengths therefore
  encode non-minimally. `ubxp_canonical_check` reports this. A producer needing
  byte-exact reproducibility must size nested bodies in a separate pass.
- **No schema compiler.** There is no `protoc` equivalent — field numbers are
  written by hand at each call site, and `schema/descriptor.asm` tables stand in
  for generated accessors.
- **Presence tracking covers field numbers 1..64.** Higher numbers encode and
  decode normally but are not tracked, so required fields should be numbered low.
- **CRC32C detects corruption, not tampering.** It is not a MAC.
- **16MB payload ceiling.** Fine for records and metadata; large object bodies
  must be carried outside the frame.

---

## ✅ Test Status

`tests/roundtrip.asm` is a self-checking suite covering varint and zig-zag
identity across boundary values (including `0xFFFFFFFFFFFFFFFF` and `INT64_MIN`),
frame header round-trip with length back-patching, packed array round-trip,
nested submessage descent, and unknown-field capture/replay.

`ubxp_test_run_all` returns a bitmask so one run reports every failure rather than
stopping at the first. The suite is excluded from `ubxp.asm` and must never land
in a kernel image; assemble it directly to run.
