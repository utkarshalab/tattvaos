"""Scalable canonical object-index validation, lookup and merge tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NOT_FOUND, NO_MEM, CORRUPT = 0, 2, 3, 5


class Record(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32),
                ("envelope", ctypes.c_uint64),
                ("payload_length", ctypes.c_uint64),
                ("object_type", ctypes.c_uint32),
                ("flags", ctypes.c_uint32),
                ("transaction", ctypes.c_uint64)]


class Lookup(ctypes.Structure):
    _fields_ = [("records", ctypes.POINTER(Record)), ("record_count", ctypes.c_uint64),
                ("object_id", P), ("result", ctypes.POINTER(Record))]


VERIFY = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.POINTER(Record),
                          ctypes.POINTER(Record), ctypes.c_void_p)


class Merge(ctypes.Structure):
    _fields_ = [("existing", ctypes.POINTER(Record)), ("existing_count", ctypes.c_uint64),
                ("inserts", ctypes.POINTER(Record)), ("insert_count", ctypes.c_uint64),
                ("output", ctypes.POINTER(Record)), ("output_capacity", ctypes.c_uint64),
                ("verify_equal", VERIFY), ("context", ctypes.c_void_p),
                ("result_count", ctypes.c_uint64)]


class Root(ctypes.Structure):
    _fields_ = [("records", ctypes.POINTER(Record)), ("record_count", ctypes.c_uint64),
                ("generation", ctypes.c_uint64), ("root_hash", P)]


class VerifiedLookup(ctypes.Structure):
    _fields_ = [("root", ctypes.POINTER(Root)), ("lookup", ctypes.POINTER(Lookup))]


lib.vcs_object_index_validate.argtypes = [ctypes.POINTER(Record), ctypes.c_uint64]
lib.vcs_object_index_validate.restype = ctypes.c_uint64
lib.vcs_object_index_find.argtypes = [ctypes.POINTER(Lookup)]
lib.vcs_object_index_find.restype = ctypes.c_uint64
lib.vcs_object_index_merge_plan.argtypes = [ctypes.POINTER(Merge)]
lib.vcs_object_index_merge_plan.restype = ctypes.c_uint64
lib.vcs_object_index_root_hash.argtypes = [ctypes.POINTER(Root)]
lib.vcs_object_index_root_hash.restype = ctypes.c_uint64
lib.vcs_object_index_root_verify.argtypes = [ctypes.POINTER(Root)]
lib.vcs_object_index_root_verify.restype = ctypes.c_uint64
lib.vcs_object_index_verified_find.argtypes = [ctypes.POINTER(VerifiedLookup)]
lib.vcs_object_index_verified_find.restype = ctypes.c_uint64


def object_id(index):
    return hashlib.sha256(b"object-index-record" + index.to_bytes(8, "little")).digest()


def make_records(indices, locator_base, transaction):
    identities = sorted((object_id(index), index) for index in indices)
    records = (Record * max(1, len(identities)))()
    for slot, (identity, index) in enumerate(identities):
        records[slot].object_id[:] = identity
        records[slot].envelope = locator_base + index
        records[slot].payload_length = 1000 + index
        records[slot].object_type = 1 + index % 10
        records[slot].transaction = transaction
    return records, identities


existing, existing_ids = make_records(range(0, 400, 2), 10000, 7)
inserts, insert_ids = make_records(list(range(1, 400, 2)) + list(range(0, 400, 10)), 20000, 8)
assert len(existing) > 64 and len(inserts) > 64
assert lib.vcs_object_index_validate(existing, len(existing_ids)) == OK
assert lib.vcs_object_index_validate(inserts, len(insert_ids)) == OK

# Binary lookup finds first/middle/last records and leaves result untouched on miss.
for slot in (0, len(existing_ids) // 2, len(existing_ids) - 1):
    identity = (ctypes.c_ubyte * 32)(*existing_ids[slot][0])
    request = Lookup(existing, len(existing_ids), identity, None)
    assert lib.vcs_object_index_find(ctypes.byref(request)) == OK
    assert bytes(request.result.contents.object_id) == existing_ids[slot][0]
missing = (ctypes.c_ubyte * 32)(*hashlib.sha256(b"missing-index-object").digest())
sentinel = ctypes.cast(ctypes.pointer(existing[5]), ctypes.POINTER(Record))
request = Lookup(existing, len(existing_ids), missing, sentinel)
assert lib.vcs_object_index_find(ctypes.byref(request)) == NOT_FOUND
assert ctypes.addressof(request.result.contents) == ctypes.addressof(existing[5])

callback_calls = []
@VERIFY
def verify_equal(old, new, _context):
    callback_calls.append(bytes(old.contents.object_id))
    # The test model represents exact bytes by the shared logical index encoded
    # in length/type; the native planner already checks those fields first.
    return OK


output = (Record * 400)()
ctypes.memset(ctypes.addressof(output), 0xCC, ctypes.sizeof(output))
merge = Merge(existing, len(existing_ids), inserts, len(insert_ids), output,
              len(output), verify_equal, None, 0xBAD)
assert lib.vcs_object_index_merge_plan(ctypes.byref(merge)) == OK
assert merge.result_count == 400
assert len(callback_calls) == 40
assert [bytes(record.object_id) for record in output] == sorted(object_id(i) for i in range(400))
# Exact duplicates retain the already-published locator and transaction.
by_id = {bytes(record.object_id): record for record in output}
for index in range(0, 400, 10):
    assert by_id[object_id(index)].envelope == 10000 + index
    assert by_id[object_id(index)].transaction == 7

# Root kind 5 authenticates generation and exact canonical record bytes while
# remaining independent of object-index page placement.
root_hash = (ctypes.c_ubyte * 32)()
root = Root(output, merge.result_count, 19, root_hash)
assert lib.vcs_object_index_root_hash(ctypes.byref(root)) == OK
frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 5, 0, 19, ctypes.sizeof(output))
assert bytes(root_hash) == hashlib.sha256(frame + bytes(output)).digest()
assert lib.vcs_object_index_root_verify(ctypes.byref(root)) == OK

identity = (ctypes.c_ubyte * 32)(*object_id(211))
verified_result_sentinel = ctypes.cast(ctypes.pointer(output[3]), ctypes.POINTER(Record))
verified_lookup = Lookup(output, merge.result_count, identity, verified_result_sentinel)
verified = VerifiedLookup(ctypes.pointer(root), ctypes.pointer(verified_lookup))
assert lib.vcs_object_index_verified_find(ctypes.byref(verified)) == OK
assert bytes(verified_lookup.result.contents.object_id) == object_id(211)

root_hash[0] ^= 1
verified_lookup.result = verified_result_sentinel
assert lib.vcs_object_index_verified_find(ctypes.byref(verified)) == CORRUPT
assert ctypes.addressof(verified_lookup.result.contents) == ctypes.addressof(output[3])
root_hash[0] ^= 1
root.generation += 1
assert lib.vcs_object_index_root_verify(ctypes.byref(root)) == CORRUPT
root.generation -= 1

# Capacity and collision failures occur before any output/result publication.
small_output = (Record * 399)()
ctypes.memset(ctypes.addressof(small_output), 0xA5, ctypes.sizeof(small_output))
before = bytes(small_output)
small = Merge(existing, len(existing_ids), inserts, len(insert_ids), small_output,
              len(small_output), verify_equal, None, 0xBAD)
assert lib.vcs_object_index_merge_plan(ctypes.byref(small)) == NO_MEM
assert small.result_count == 0xBAD and bytes(small_output) == before

@VERIFY
def collision(_old, _new, _context):
    return CORRUPT

collision_output = (Record * 400)()
ctypes.memset(ctypes.addressof(collision_output), 0x5A, ctypes.sizeof(collision_output))
before = bytes(collision_output)
bad_merge = Merge(existing, len(existing_ids), inserts, len(insert_ids), collision_output,
                  len(collision_output), collision, None, 0xBAD)
assert lib.vcs_object_index_merge_plan(ctypes.byref(bad_merge)) == CORRUPT
assert bad_merge.result_count == 0xBAD and bytes(collision_output) == before

# Malformed, unsorted and duplicate catalogs fail closed.
bad = (Record * 2)()
bad[0], bad[1] = existing[1], existing[0]
assert lib.vcs_object_index_validate(bad, 2) == CORRUPT
bad[0], bad[1] = existing[0], existing[0]
assert lib.vcs_object_index_validate(bad, 2) == CORRUPT
for field, value in (("envelope", 0), ("object_type", 11), ("flags", 1), ("transaction", 0)):
    malformed = Record.from_buffer_copy(bytes(existing[0]))
    setattr(malformed, field, value)
    assert lib.vcs_object_index_validate(ctypes.pointer(malformed), 1) == CORRUPT

empty_merge = Merge(None, 0, None, 0, None, 0, VERIFY(), None, 0xBAD)
assert lib.vcs_object_index_merge_plan(ctypes.byref(empty_merge)) == OK
assert empty_merge.result_count == 0

print("VCS object index: PASS (400 records, COW merge, authenticated generations, verified lookup, atomic failures)")
