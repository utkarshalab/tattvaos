"""Whole-file chunk writing and collision-safe deduplication tests."""
import ctypes
import hashlib
import random
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NO_MEM, CORRUPT, CONFLICT = 0, 3, 5, 6
CHUNK_MIN, CHUNK_MAX, MASK = 2048, 32768, 8191
MIX = 0x9E3779B185EBCA87


class ChunkIO(ctypes.Structure):
    _fields_ = [("payload", P), ("payload_length", ctypes.c_uint64),
                ("envelope", P), ("extents", P),
                ("locators", ctypes.POINTER(ctypes.c_uint64)),
                ("extent_capacity", ctypes.c_uint64),
                ("transaction", ctypes.c_uint64), ("object_id", P),
                ("output", P), ("output_capacity", ctypes.c_uint64),
                ("result_length", ctypes.c_uint64)]


class Record(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32), ("data", P),
                ("length", ctypes.c_uint64)]


class Entry(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32),
                ("offset", ctypes.c_uint64), ("length", ctypes.c_uint64),
                ("storage_index", ctypes.c_uint64),
                ("flags", ctypes.c_uint64)]


class Pipeline(ctypes.Structure):
    _fields_ = [("data", P), ("length", ctypes.c_uint64),
                ("bounds", ctypes.POINTER(ctypes.c_uint64)),
                ("bounds_capacity", ctypes.c_uint64),
                ("entries", ctypes.POINTER(Entry)),
                ("entry_capacity", ctypes.c_uint64),
                ("existing", ctypes.POINTER(Record)),
                ("existing_count", ctypes.c_uint64),
                ("new_ios", ctypes.POINTER(ChunkIO)),
                ("new_capacity", ctypes.c_uint64),
                ("result_count", ctypes.c_uint64),
                ("result_new", ctypes.c_uint64)]


lib.vcs_file_chunks_write.argtypes = [ctypes.POINTER(Pipeline)]
lib.vcs_file_chunks_write.restype = ctypes.c_uint64
lib.vcs_chunk_object_verify.argtypes = [ctypes.POINTER(ChunkIO)]
lib.vcs_chunk_object_verify.restype = ctypes.c_uint64


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def object_id(data):
    frame = b"UVCSHSH1" + struct.pack("<HHIQ", 1, 1, 0, len(data))
    return hashlib.sha256(frame + data).digest()


def boundaries(data):
    if not data:
        return []
    result, start, rolling = [], 0, 0
    for pos, byte in enumerate(data, 1):
        mixed = ((byte + 1) * MIX) & ((1 << 64) - 1)
        rolling = (((rolling << 1) | (rolling >> 63)) ^ mixed) & ((1 << 64) - 1)
        size = pos - start
        if pos == len(data) or size >= CHUNK_MAX or (size >= CHUNK_MIN and not rolling & MASK):
            result.append(pos)
            start, rolling = pos, 0
    return result


def run(data, existing=(), capacity=None):
    source = array(data)
    count = len(boundaries(data))
    capacity = count if capacity is None else capacity
    bounds_buf = (ctypes.c_uint64 * max(1, capacity))()
    entries = (Entry * max(1, capacity))()
    records = (Record * max(1, len(existing)))()
    existing_buffers = []
    for index, (digest, payload) in enumerate(existing):
        buf = array(payload)
        existing_buffers.append(buf)
        records[index].object_id[:] = digest
        records[index].data = ctypes.cast(buf, P)
        records[index].length = len(payload)
    ios = (ChunkIO * max(1, capacity))()
    owned = []
    for index in range(max(1, capacity)):
        envelope = (ctypes.c_ubyte * 128)()
        extents = (ctypes.c_ubyte * (9 * 4096))()
        locators = (ctypes.c_uint64 * 9)(*[0x100000 + index * 0x100 + j + 1 for j in range(9)])
        owned.append((envelope, extents, locators))
        ios[index].envelope = ctypes.cast(envelope, P)
        ios[index].extents = ctypes.cast(extents, P)
        ios[index].locators = locators
        ios[index].extent_capacity = 9
        ios[index].transaction = 41
    plan = Pipeline(ctypes.cast(source, P), len(data), bounds_buf, capacity,
                    entries, capacity, records if existing else None,
                    len(existing), ios, capacity, 0xBAD, 0xBAD)
    rc = lib.vcs_file_chunks_write(ctypes.byref(plan))
    return rc, plan, source, bounds_buf, entries, ios, owned, existing_buffers


rng = random.Random(0xC0DEC0DE)
data = bytes(rng.randrange(256) for _ in range(180000))
expected_bounds = boundaries(data)
rc, plan, source, bounds_buf, entries, ios, owned, keep = run(data)
assert rc == OK and plan.result_count == len(expected_bounds)
assert list(bounds_buf[:plan.result_count]) == expected_bounds
assert plan.result_new == plan.result_count
start = 0
for index, end in enumerate(expected_bounds):
    payload = data[start:end]
    entry = entries[index]
    assert (entry.offset, entry.length, entry.flags, entry.storage_index) == (start, len(payload), 0, index)
    assert bytes(entry.object_id) == object_id(payload)
    assert lib.vcs_chunk_object_verify(ctypes.byref(ios[index])) == OK
    start = end

# A pre-existing object is reused only after exact byte verification.
first_end = expected_bounds[0]
first = data[:first_end]
rc, plan, source, bounds_buf, entries, ios, owned, keep = run(
    data, ((object_id(first), first),))
assert rc == OK and entries[0].flags == 1 and entries[0].storage_index == 0
assert plan.result_new == plan.result_count - 1

# Same ID with different bytes is a collision, never a deduplication hit.
forged = bytes([first[0] ^ 1]) + first[1:]
rc, plan, *_ = run(data, ((object_id(first), forged),))
assert rc == CONFLICT and plan.result_count == 0xBAD and plan.result_new == 0xBAD
rc, plan, *_ = run(data, ((object_id(first), first), (object_id(first), first)))
assert rc == CORRUPT and plan.result_count == 0xBAD and plan.result_new == 0xBAD

# Repeat a naturally terminated deterministic chunk to prove in-file reuse.
probe = bytes(random.Random(17).randrange(256) for _ in range(40000))
candidate = probe[:boundaries(probe)[0]]
repeated = candidate + candidate
rc, plan, source, bounds_buf, entries, ios, owned, keep = run(repeated)
assert rc == OK and plan.result_count == 2 and plan.result_new == 1
assert entries[1].flags == 2 and entries[1].storage_index == 0
assert bytes(entries[0].object_id) == bytes(entries[1].object_id)

# Empty files need no arrays; insufficient caller capacity publishes no result.
empty = Pipeline(None, 0, None, 0, None, 0, None, 0, None, 0, 7, 9)
assert lib.vcs_file_chunks_write(ctypes.byref(empty)) == OK
assert (empty.result_count, empty.result_new) == (0, 0)
rc, plan, *_ = run(data, capacity=len(expected_bounds) - 1)
assert rc == NO_MEM and plan.result_count == 0xBAD and plan.result_new == 0xBAD

rc, plan, source, bounds_buf, entries, ios, owned, keep = run(data)
ios[0].extent_capacity = 0
plan.result_count = plan.result_new = 0xBAD
assert lib.vcs_file_chunks_write(ctypes.byref(plan)) == NO_MEM
assert plan.result_count == 0xBAD and plan.result_new == 0xBAD

print("VCS chunk pipeline: PASS (whole-file bounds, object writes, exact dedup, collisions, capacity)")
