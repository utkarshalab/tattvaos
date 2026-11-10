# Chunking

- Status: Implemented scalar reference
- Version: 1.0
- Owner: Utkarsha Lab

## Scope

Deterministic content-defined chunk boundaries for large VCS objects. This
version defines the portable scalar result consumed by future SIMD kernels and
UFS dedup integration.

## Parameters

- Minimum chunk size: 2,048 bytes.
- Target average chunk size: 8,192 bytes.
- Maximum chunk size: 32,768 bytes.
- Boundary mask: `0x1fff`.
- Mixing constant: `0x9e3779b185ebca87`.

## Algorithm

The rolling state starts at zero for every chunk. For each byte `b`, interpreted
as an unsigned integer, update the 64-bit state with wrapping arithmetic:

```text
state = rol64(state, 1) XOR ((b + 1) * 0x9e3779b185ebca87)
```

After consuming a byte, end the chunk when any of these conditions holds:

1. the input ended;
2. the chunk reached 32,768 bytes; or
3. the chunk is at least 2,048 bytes and `(state & 0x1fff) == 0`.

Reset the state to zero after every boundary. Boundaries are byte offsets from
the start of the input and point one byte past the chunk. Therefore every
nonempty input ends with a boundary equal to its length; empty input has no
boundaries.

## Assembly ABI

`vcs_chunk` receives the data pointer in `rdi`, byte length in `rsi`, output
qword array in `rdx`, and array capacity in `rcx`. It returns the number of
boundaries in `rax`. Empty input returns zero without dereferencing pointers.
Nonempty input returns `UINT64_MAX` for a null pointer and `UINT64_MAX-1` when
the output capacity is exhausted. It never writes beyond the supplied capacity.
Capacity is checked with the count-only pass before emission, so a capacity
error leaves the complete output array unchanged rather than publishing a
partial prefix of boundaries.
The constants and ABI are published by `include/chunk.inc`. `scalar_chunk` is a
compatibility alias for the current backend; callers use `vcs_chunk` so a future
validated SIMD backend does not require an ABI change.

`vcs_chunk_count` receives only the data pointer and length in `rdi` and `rsi`.
It runs the identical boundary state machine without writing an array and
returns the exact required capacity. Callers can therefore preflight allocation,
then call `vcs_chunk` without relying on a worst-case estimate. Its empty-input
and invalid-pointer behavior is identical to `vcs_chunk`.

## Validation

The executable differential suite compares assembly boundaries with an
independent Python definition across fixed vectors, boundary-sized inputs,
seeded random data, repetitive data, capacity failures, and output canaries.

## Open Questions

- Whether UXFS should consume these boundaries directly or maintain its own
  chunk index remains an integration decision.
- AVX2 and AVX-512 implementations must produce byte-for-byte identical
  boundaries before replacing the scalar path.
