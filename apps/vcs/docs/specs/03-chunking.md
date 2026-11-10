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

`scalar_chunk` receives the data pointer in `rdi`, byte length in `rsi`, output
qword array in `rdx`, and array capacity in `rcx`. It returns the number of
boundaries in `rax`. Empty input returns zero without dereferencing pointers.
Nonempty input returns `UINT64_MAX` for a null pointer and `UINT64_MAX-1` when
the output capacity is exhausted. It never writes beyond the supplied capacity.

## Validation

The executable differential suite compares assembly boundaries with an
independent Python definition across fixed vectors, boundary-sized inputs,
seeded random data, repetitive data, capacity failures, and output canaries.

## Open Questions

- Whether UXFS should consume these boundaries directly or maintain its own
  chunk index remains an integration decision.
- AVX2 and AVX-512 implementations must produce byte-for-byte identical
  boundaries before replacing the scalar path.
