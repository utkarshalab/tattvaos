"""Executable coverage for bounded native request/response negotiation codecs."""
import ctypes
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
byte_pointer = ctypes.POINTER(ctypes.c_ubyte)
lib.vcs_sync_request_encode.argtypes = [byte_pointer, ctypes.c_uint32,
                                        byte_pointer, ctypes.c_char_p,
                                        ctypes.c_uint64]
lib.vcs_sync_request_encode.restype = ctypes.c_uint64
lib.vcs_sync_response_encode.argtypes = [byte_pointer, ctypes.c_uint32,
                                         byte_pointer, ctypes.c_uint64]
lib.vcs_sync_response_encode.restype = ctypes.c_uint64
lib.protocol_request_decode_probe.argtypes = [byte_pointer, ctypes.c_uint64,
                                              ctypes.POINTER(ctypes.c_uint64)]
lib.protocol_response_decode_probe.argtypes = [byte_pointer, ctypes.c_uint64,
                                               ctypes.POINTER(ctypes.c_uint64)]

SIZE = 96
VCS_USAGE = 8
VCS_CORRUPT = 5
REQ_MAGIC = 0x3151455253435655
RES_MAGIC = 0x3153455253435655

def guarded():
    raw = (ctypes.c_ubyte * (SIZE + 32))(*([0xA5] * (SIZE + 32)))
    return raw, ctypes.cast(ctypes.byref(raw, 16), byte_pointer)

def body(raw):
    return bytes(raw[16:16 + SIZE])

def request_decode(raw, length=SIZE):
    result = (ctypes.c_uint64 * 6)()
    lib.protocol_request_decode_probe(
        ctypes.cast(ctypes.byref(raw, 16), byte_pointer), length, result)
    return tuple(result)

def response_decode(raw, length=SIZE):
    result = (ctypes.c_uint64 * 4)()
    lib.protocol_response_decode_probe(
        ctypes.cast(ctypes.byref(raw, 16), byte_pointer), length, result)
    return tuple(result)

digest = (ctypes.c_ubyte * 32)(*range(32))
raw, output = guarded()
assert lib.vcs_sync_request_encode(output, 1, digest, b'main', 0) == 0
encoded = body(raw)
assert bytes(raw[:16]) == bytes([0xA5] * 16)
assert bytes(raw[-16:]) == bytes([0xA5] * 16)
assert struct.unpack_from('<QIIQQ', encoded) == (REQ_MAGIC, 1, 1, 3, 0)
assert encoded[32:64] == bytes(range(32))
assert encoded[64:69] == b'main\0' and encoded[69:] == bytes(27)
status, operation, flags, digest_ptr, ref_ptr, count = request_decode(raw)
base = ctypes.addressof(raw) + 16
assert (status, operation, flags, count) == (0, 1, 3, 0)
assert digest_ptr == base + 32 and ref_ptr == base + 64

for operation, count in ((2, 0), (2, 64), (3, 0)):
    raw, output = guarded()
    assert lib.vcs_sync_request_encode(output, operation, None, None, count) == 0
    assert request_decode(raw)[:3] == (0, operation, 3)
for operation, count, ref in ((0, 0, None), (4, 0, None), (1, 1, None),
                              (2, 65, None), (1, 0, b''),
                              (1, 0, b'.hidden'), (1, 0, b'bad/name'),
                              (1, 0, b'x' * 32)):
    raw, output = guarded()
    assert lib.vcs_sync_request_encode(output, operation, None, ref, count) == VCS_USAGE
    assert body(raw) == bytes([0xA5] * SIZE)

raw, output = guarded()
assert lib.vcs_sync_request_encode(output, 1, digest, b'branch_1', 0) == 0
for offset, replacement in ((0, b'BADMAGIC'), (8, struct.pack('<I', 2)),
                            (12, struct.pack('<I', 4)),
                            (16, struct.pack('<Q', 1)),
                            (24, struct.pack('<Q', 1)), (68, b'/')):
    damaged = (ctypes.c_ubyte * (SIZE + 32)).from_buffer_copy(raw)
    start = 16 + offset
    damaged[start:start + len(replacement)] = replacement
    assert request_decode(damaged)[0] == VCS_CORRUPT
assert request_decode(raw, SIZE - 1)[0] == VCS_CORRUPT

raw, output = guarded()
assert lib.vcs_sync_response_encode(output, 0, digest, 64) == 0
encoded = body(raw)
assert struct.unpack_from('<QIIQQ', encoded) == (RES_MAGIC, 1, 0, 3, 64)
assert encoded[32:64] == bytes(range(32)) and encoded[64:] == bytes(32)
status, remote_status, count, digest_ptr = response_decode(raw)
base = ctypes.addressof(raw) + 16
assert (status, remote_status, count, digest_ptr) == (0, 0, 64, base + 32)
for remote_status, count in ((10, 0), (0, 65)):
    candidate, pointer = guarded()
    assert lib.vcs_sync_response_encode(pointer, remote_status, None, count) == VCS_USAGE
    assert body(candidate) == bytes([0xA5] * SIZE)
for offset, replacement in ((0, b'BADMAGIC'), (8, struct.pack('<I', 2)),
                            (12, struct.pack('<I', 10)),
                            (16, struct.pack('<Q', 1)),
                            (24, struct.pack('<Q', 65)), (64, b'X')):
    damaged = (ctypes.c_ubyte * (SIZE + 32)).from_buffer_copy(raw)
    start = 16 + offset
    damaged[start:start + len(replacement)] = replacement
    assert response_decode(damaged)[0] == VCS_CORRUPT
assert response_decode(raw, SIZE + 1)[0] == VCS_CORRUPT

print('VCS protocol: PASS (request/response framing, bounds, refs, corruption, canaries)')
