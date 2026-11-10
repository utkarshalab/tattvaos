"""Differential validation for the scalar content-defined chunker."""
import ctypes
import random
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
Q = ctypes.POINTER(ctypes.c_uint64)
lib.scalar_chunk.argtypes = [P, ctypes.c_uint64, Q, ctypes.c_uint64]
lib.scalar_chunk.restype = ctypes.c_uint64
lib.vcs_chunk.argtypes = [P, ctypes.c_uint64, Q, ctypes.c_uint64]
lib.vcs_chunk.restype = ctypes.c_uint64
lib.vcs_chunk_count.argtypes = [P, ctypes.c_uint64]
lib.vcs_chunk_count.restype = ctypes.c_uint64
lib.scalar_blake3.argtypes = [P, ctypes.c_uint64, P]
lib.scalar_blake3.restype = ctypes.c_uint64

MASK64 = (1 << 64) - 1
MIX = 0x9E3779B185EBCA87

def reference(data):
    bounds = []
    state = 0
    start = 0
    for offset, byte in enumerate(data, 1):
        state = (((state << 1) | (state >> 63)) & MASK64) ^ (((byte + 1) * MIX) & MASK64)
        size = offset - start
        if offset == len(data) or size == 32768 or (size >= 2048 and state & 0x1FFF == 0):
            bounds.append(offset)
            state = 0
            start = offset
    return bounds

def assembly(data, capacity=None, entry=None):
    expected_max = (len(data) + 2047) // 2048
    if capacity is None:
        capacity = max(1, expected_max)
    source = (ctypes.c_ubyte * len(data)).from_buffer_copy(data) if data else None
    guarded = (ctypes.c_uint64 * (capacity + 2))()
    guarded[0] = 0x1122334455667788
    guarded[capacity + 1] = 0x8877665544332211
    output = ctypes.cast(ctypes.byref(guarded, 8), Q)
    count = (entry or lib.vcs_chunk)(source, len(data), output, capacity)
    assert guarded[0] == 0x1122334455667788
    assert guarded[capacity + 1] == 0x8877665544332211
    return count, list(guarded[1:1 + min(count, capacity)]) if count <= capacity else []

def count_only(data):
    source = (ctypes.c_ubyte * len(data)).from_buffer_copy(data) if data else None
    return lib.vcs_chunk_count(source, len(data))

vectors = [
    b'', b'a', b'a' * 2047, b'a' * 2048, b'a' * 32768,
    b'a' * 32769, bytes(range(256)) * 300,
]
rng = random.Random(0x544154545641)
for length in (63, 2049, 8192, 32767, 65536, 131071):
    vectors.append(rng.randbytes(length))

for data in vectors:
    expected = reference(data)
    count, bounds = assembly(data)
    assert count_only(data) == count
    assert count == len(expected), (len(data), count, len(expected))
    assert bounds == expected, (len(data), bounds, expected)
    if bounds:
        assert bounds[-1] == len(data)
        previous = 0
        for boundary in bounds:
            assert 0 < boundary - previous <= 32768
            previous = boundary

for data in vectors:
    assert assembly(data) == assembly(data, entry=lib.scalar_chunk)

data = rng.randbytes(65536)
needed = len(reference(data))
count, _ = assembly(data, needed - 1)
assert count == (1 << 64) - 2
assert lib.vcs_chunk(None, 1, None, 0) == (1 << 64) - 1
assert lib.vcs_chunk(None, 0, None, 0) == 0
assert lib.vcs_chunk_count(None, 1) == (1 << 64) - 1
assert lib.vcs_chunk_count(None, 0) == 0
digest = (ctypes.c_ubyte * 32)(*([0xA5] * 32))
assert lib.scalar_blake3(None, 0, digest) == 9
assert bytes(digest) == b'\xA5' * 32

print('VCS chunking differential: PASS (preflight, public/scalar parity, vectors, random, bounds, capacity, canaries, fail-closed hash)')
