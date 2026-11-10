"""Executable validation for scalable chunk envelopes and extent chains."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)


class ChunkIO(ctypes.Structure):
    _fields_ = [
        ("payload", P),
        ("payload_length", ctypes.c_uint64),
        ("envelope", P),
        ("extents", P),
        ("locators", ctypes.POINTER(ctypes.c_uint64)),
        ("extent_capacity", ctypes.c_uint64),
        ("transaction", ctypes.c_uint64),
        ("object_id", P),
        ("output", P),
        ("output_capacity", ctypes.c_uint64),
        ("result_length", ctypes.c_uint64),
    ]


for name in ("vcs_chunk_object_id", "vcs_chunk_object_write",
             "vcs_chunk_object_read", "vcs_chunk_object_verify"):
    getattr(lib, name).restype = ctypes.c_uint64
lib.vcs_chunk_object_id.argtypes = [P, ctypes.c_uint64, P]
for name in ("vcs_chunk_object_write", "vcs_chunk_object_read",
             "vcs_chunk_object_verify"):
    getattr(lib, name).argtypes = [ctypes.POINTER(ChunkIO)]

OK, NO_MEM, CORRUPT, USAGE = 0, 3, 5, 8
EXTENT_PAYLOAD = 4032


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def expected_id(data):
    frame = b"UVCSHSH1" + struct.pack("<HHIQ", 1, 1, 0, len(data))
    return hashlib.sha256(frame + data).digest()


def make_io(data, capacity=9, transaction=7):
    payload = array(data)
    envelope = (ctypes.c_ubyte * 128)(*[0xA5] * 128)
    extents = (ctypes.c_ubyte * (capacity * 4096))(*([0xA5] * (capacity * 4096)))
    locators = (ctypes.c_uint64 * capacity)(*[0x1000 + i * 17 for i in range(capacity)])
    object_id = (ctypes.c_ubyte * 32)(*[0xA5] * 32)
    output = (ctypes.c_ubyte * max(1, len(data)))(*[0xCC] * max(1, len(data)))
    io = ChunkIO(payload, len(data), envelope, extents, locators, capacity,
                 transaction, object_id, output, len(data), 0xDEADBEEF)
    return io, payload, envelope, extents, locators, object_id, output


def check_round_trip(data):
    io, _, envelope, extents, locators, object_id, output = make_io(data)
    assert lib.vcs_chunk_object_write(ctypes.byref(io)) == OK
    digest = expected_id(data)
    assert bytes(object_id) == digest and io.result_length == len(data)
    raw = bytes(envelope)
    count = (len(data) + EXTENT_PAYLOAD - 1) // EXTENT_PAYLOAD
    assert raw[:8] == b"UVCSOBJ3"
    assert struct.unpack_from("<HHHHIIQQ", raw, 8) == (1, 128, 1, 1, 0, 0, len(data), count)
    assert raw[40:72] == digest
    assert struct.unpack_from("<QQ", raw, 72) == (locators[0], 7)
    assert raw[88:120] == hashlib.sha256(raw[:88]).digest()
    assert raw[120:] == bytes(8)
    offset = 0
    for index in range(count):
        block = bytes(extents[index * 4096:(index + 1) * 4096])
        size = min(EXTENT_PAYLOAD, len(data) - offset)
        assert block[:8] == b"UVCSEXT1"
        assert struct.unpack_from("<HHI", block, 8) == (1, index == count - 1, size)
        assert block[16:48] == digest
        assert struct.unpack_from("<Q", block, 48)[0] == index
        expected_next = 0 if index == count - 1 else locators[index + 1]
        assert struct.unpack_from("<Q", block, 56)[0] == expected_next
        assert block[64:64 + size] == data[offset:offset + size]
        assert block[64 + size:] == bytes(EXTENT_PAYLOAD - size)
        offset += size
    io.result_length = 0xBAD
    assert lib.vcs_chunk_object_verify(ctypes.byref(io)) == OK
    assert io.result_length == 0xBAD
    assert lib.vcs_chunk_object_read(ctypes.byref(io)) == OK
    assert io.result_length == len(data) and bytes(output) == data
    return io, envelope, extents, locators, object_id, output


for size in (1, 31, 4032, 4033, 32768):
    check_round_trip(bytes((i * 131 + size) & 0xFF for i in range(size)))

sample = array(b"abc")
digest = (ctypes.c_ubyte * 32)()
assert lib.vcs_chunk_object_id(sample, 3, digest) == OK
assert bytes(digest) == expected_id(b"abc")
assert lib.vcs_chunk_object_id(None, 3, digest) == USAGE
assert lib.vcs_chunk_object_id(sample, 0, digest) == CORRUPT

io, _, envelope, extents, locators, object_id, output = make_io(b"x" * 4033, 1)
before = bytes(envelope), bytes(extents), bytes(object_id), io.result_length
assert lib.vcs_chunk_object_write(ctypes.byref(io)) == NO_MEM
assert (bytes(envelope), bytes(extents), bytes(object_id), io.result_length) == before

io, _, envelope, extents, locators, object_id, output = make_io(b"p" * 5000)
locators[1] = locators[0]
assert lib.vcs_chunk_object_write(ctypes.byref(io)) == CORRUPT
locators[1] += 1
io.transaction = 0
assert lib.vcs_chunk_object_write(ctypes.byref(io)) == CORRUPT

def corrupt_and_reject(region, byte_offset):
    io, envelope, extents, _, _, output = check_round_trip(b"z" * 5000)
    target = envelope if region == "envelope" else extents
    target[byte_offset] ^= 1
    output[:] = bytes([0xCC]) * len(output)
    io.result_length = 0x1234
    assert lib.vcs_chunk_object_read(ctypes.byref(io)) == CORRUPT
    assert bytes(output) == bytes([0xCC]) * len(output)
    assert io.result_length == 0x1234


for where, offset in (("envelope", 0), ("envelope", 88),
                      ("extent", 0), ("extent", 10),
                      ("extent", 48), ("extent", 64),
                      ("extent", 4095)):
    corrupt_and_reject(where, offset)

io, envelope, extents, locators, object_id, output = check_round_trip(b"bounded read")
io.output_capacity -= 1
output[:] = bytes([0xCC]) * len(output)
assert lib.vcs_chunk_object_read(ctypes.byref(io)) == NO_MEM
assert bytes(output) == bytes([0xCC]) * len(output)
object_id[0] ^= 1
assert lib.vcs_chunk_object_verify(ctypes.byref(io)) == CORRUPT

print("VCS object store: PASS (domain IDs, envelopes, extent chains, bounds, corruption, atomic reads)")
