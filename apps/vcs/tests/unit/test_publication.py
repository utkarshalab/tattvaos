"""Recoverable publication phase-machine and failure-injection tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NO_MEM, IO, CORRUPT, USAGE = 0, 3, 4, 5, 8
NONE, BEGUN, OBJECTS, OWNERSHIP, ROOT, FLUSHED, COMMITTED, POISONED, ABORTED = range(9)


class PublishObject(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32),
                ("object_type", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("payload", P), ("length", ctypes.c_uint64),
                ("envelope", ctypes.c_uint64), ("envelope_header", P),
                ("extents", P), ("locators", ctypes.POINTER(ctypes.c_uint64)),
                ("extent_count", ctypes.c_uint64)]


class Edge(ctypes.Structure):
    _fields_ = [("owner_kind", ctypes.c_uint32), ("child_type", ctypes.c_uint32),
                ("owner_key", ctypes.c_ubyte * 32),
                ("child_id", ctypes.c_ubyte * 32), ("flags", ctypes.c_uint64)]


class IndexRecord(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32), ("envelope", ctypes.c_uint64),
                ("payload_length", ctypes.c_uint64), ("object_type", ctypes.c_uint32),
                ("flags", ctypes.c_uint32), ("transaction", ctypes.c_uint64)]


class IndexRoot(ctypes.Structure):
    _fields_ = [("records", ctypes.POINTER(IndexRecord)), ("record_count", ctypes.c_uint64),
                ("generation", ctypes.c_uint64), ("root_hash", P)]


class OwnershipRoot(ctypes.Structure):
    _fields_ = [("records", ctypes.POINTER(Edge)), ("record_count", ctypes.c_uint64),
                ("generation", ctypes.c_uint64), ("root_hash", P)]


class RefRoot(ctypes.Structure):
    _fields_ = [("records", P), ("record_bytes", ctypes.c_uint64),
                ("generation", ctypes.c_uint64), ("root_hash", P)]


class Backend(ctypes.Structure):
    _fields_ = [("context", ctypes.c_void_p), ("begin", ctypes.c_void_p),
                ("put_object", ctypes.c_void_p), ("put_edge", ctypes.c_void_p),
                ("stage_root", ctypes.c_void_p), ("flush", ctypes.c_void_p),
                ("publish", ctypes.c_void_p), ("abort", ctypes.c_void_p),
                ("poison", ctypes.c_void_p)]


class Publication(ctypes.Structure):
    _fields_ = [("backend", ctypes.POINTER(Backend)),
                ("previous_root", P),
                ("objects", ctypes.POINTER(PublishObject)),
                ("object_count", ctypes.c_uint64),
                ("edges", ctypes.POINTER(Edge)), ("edge_count", ctypes.c_uint64),
                ("transaction_owner", P),
                ("root", P), ("root_length", ctypes.c_uint64),
                ("tx_sequence", ctypes.c_uint64), ("generation", ctypes.c_uint64),
                ("index_root", ctypes.POINTER(IndexRoot)),
                ("ownership_root", ctypes.POINTER(OwnershipRoot)),
                ("ref_root", ctypes.POINTER(RefRoot)),
                ("result_phase", ctypes.c_uint64)]


lib.vcs_publication_commit.argtypes = [ctypes.POINTER(Publication)]
lib.vcs_publication_commit.restype = ctypes.c_uint64

BEGIN_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
                           ctypes.c_uint64, ctypes.c_uint64, ctypes.c_uint64)
PAIR_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p)
ROOT_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p,
                          ctypes.c_uint64, ctypes.c_uint64, ctypes.c_void_p,
                          ctypes.c_void_p, ctypes.c_void_p)
SIMPLE_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p)


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def oid(kind, payload):
    return hashlib.sha256(b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload)) + payload).digest()


tree_id = hashlib.sha256(b"publication root tree").digest()
commit_message = b"canonical head commit"
commit_header = bytearray(256)
commit_header[:8] = b"UVCSCOM3"
struct.pack_into("<IIQqii", commit_header, 8, 0, 0, 1, 0, 0,
                 len(commit_message))
commit_header[40:72] = tree_id
commit_payload = bytes(commit_header) + commit_message
commit_id = oid(4, commit_payload)
alternate_commit_id = hashlib.sha256(b"indexed alternate commit").digest()
object_specs = [(1, b"first immutable payload"),
                (2, bytes((index * 73) & 0xff for index in range(5000))),
                (4, commit_payload)]
object_specs.sort(key=lambda value: oid(value[0], value[1]))
payload_buffers = [array(payload) for _, payload in object_specs]
objects = (PublishObject * len(object_specs))()
for index, (kind, payload) in enumerate(object_specs):
    objects[index].object_id[:] = oid(kind, payload)
    objects[index].object_type = kind
    objects[index].payload = payload_buffers[index]
    objects[index].length = len(payload)
    objects[index].envelope = 100 + index

envelope_buffers, extent_buffers, locator_buffers = [], [], []
for index, value in enumerate(objects):
    extent_count = (value.length + 4031) // 4032
    locators = (ctypes.c_uint64 * extent_count)(
        *[1000 + index * 16 + extent for extent in range(extent_count)])
    extents = bytearray(extent_count * 4096)
    payload = bytes(payload_buffers[index])
    offset = 0
    for extent_index in range(extent_count):
        block = extent_index * 4096
        size = min(4032, value.length - offset)
        extents[block:block + 8] = b"UVCSEXT1"
        struct.pack_into("<HHI", extents, block + 8, 1,
                         extent_index == extent_count - 1, size)
        extents[block + 16:block + 48] = bytes(value.object_id)
        next_locator = 0 if extent_index == extent_count - 1 else locators[extent_index + 1]
        struct.pack_into("<QQ", extents, block + 48, extent_index, next_locator)
        extents[block + 64:block + 64 + size] = payload[offset:offset + size]
        offset += size
    extent_buffer = array(extents)
    extent_buffers.append(extent_buffer)
    locator_buffers.append(locators)
    value.extents = extent_buffer
    value.locators = locators
    value.extent_count = extent_count
    envelope = bytearray(128)
    envelope[:8] = b"UVCSOBJ3"
    struct.pack_into("<HHHHIIQQ", envelope, 8, 1, 128,
                     value.object_type, 1, 0, 0, value.length,
                     extent_count)
    envelope[40:72] = bytes(value.object_id)
    struct.pack_into("<QQ", envelope, 72, locators[0], 11)
    envelope[88:120] = hashlib.sha256(envelope[:88]).digest()
    envelope_buffer = array(envelope)
    envelope_buffers.append(envelope_buffer)
    value.envelope_header = envelope_buffer

chunk_index = next(index for index, spec in enumerate(object_specs) if spec[0] == 1)
file_index = next(index for index, spec in enumerate(object_specs) if spec[0] == 2)
commit_index = next(index for index, spec in enumerate(object_specs) if spec[0] == 4)
transaction_owner = array(hashlib.sha256(b"publication transaction 11").digest())
ref_name = b"main"
branch_key = hashlib.sha256(b"UVCSRFK1" + struct.pack("<HBB", 1, 1,
                                                       len(ref_name))
                                + ref_name).digest()
edge_values = [(1, 1, bytes(objects[file_index].object_id),
                bytes(objects[chunk_index].object_id)),
               (1, 3, commit_id, tree_id),
               (2, 4, branch_key, commit_id)]
for value in objects:
    edge_values.append((5, value.object_type, bytes(transaction_owner),
                        bytes(value.object_id)))
edge_values.sort(key=lambda value: (value[3], value[0], value[2]))
edges = (Edge * len(edge_values))()
for edge, (owner_kind, child_type, owner_key, child_id) in zip(edges, edge_values):
    edge.owner_kind = owner_kind
    edge.child_type = child_type
    edge.owner_key[:] = owner_key
    edge.child_id[:] = child_id
immutable_edge_index = next(index for index, edge in enumerate(edges)
                            if edge.owner_kind == 1)
immutable_edge_type = edges[immutable_edge_index].child_type
ownership_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 2, 0, 9,
                                             ctypes.sizeof(edges))
ownership_hash = array(hashlib.sha256(ownership_frame + bytes(edges)).digest())
ownership_root = OwnershipRoot(edges, len(edges), 9, ownership_hash)

branch_record = (struct.pack("<BBHIQ", 1, len(ref_name), 1, 0, 7)
                 + commit_id + ref_name
                 + bytes((-len(ref_name)) & 7))
head_name = b"HEAD"
head_record = (struct.pack("<BBHIQ", 4, len(head_name), 2, 0, 3)
               + branch_key + head_name + bytes((-len(head_name)) & 7))
ref_record = branch_record + head_record
ref_records = array(ref_record)
ref_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 1, 0, 9,
                                       len(ref_record))
ref_hash = array(hashlib.sha256(ref_frame + ref_record).digest())
ref_root = RefRoot(ref_records, len(ref_record), 9, ref_hash)

catalog = [(bytes(objects[index].object_id), 100 + index,
            objects[index].length, objects[index].object_type)
           for index in range(len(objects))]
catalog.append((tree_id, 200, 96, 3))
catalog.append((alternate_commit_id, 201, 256, 4))
index_records = (IndexRecord * len(catalog))()
for slot, (object_id, envelope, length, object_type) in enumerate(
        sorted(catalog, key=lambda value: value[0])):
    index_records[slot].object_id[:] = object_id
    index_records[slot].envelope = envelope
    index_records[slot].payload_length = length
    index_records[slot].object_type = object_type
    index_records[slot].transaction = 10
for value in objects:
    record = next(record for record in index_records
                  if bytes(record.object_id) == bytes(value.object_id))
    record.transaction = 11
index_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 5, 0, 9, ctypes.sizeof(index_records))
index_hash = array(hashlib.sha256(index_frame + bytes(index_records)).digest())
index_root = IndexRoot(index_records, len(catalog), 9, index_hash)

root_image = bytearray(512)
root_image[:8] = b"UVCSREP3"
struct.pack_into("<IIQQ", root_image, 8, 3, 512, 3, 9)
root_image[32:48] = hashlib.sha256(b"publication repository uuid").digest()[:16]
struct.pack_into("<II", root_image, 48, 1, 4096)
root_image[56:88] = commit_id
root_image[88:120] = bytes(ref_hash)
root_image[120:152] = bytes(ownership_hash)
root_image[184:216] = bytes(index_hash)
struct.pack_into("<Q", root_image, 256, 12)
root_image[480:512] = hashlib.sha256(root_image[:480]).digest()
root_bytes = bytes(root_image)
root = array(root_bytes)
previous_image = bytearray(root_image)
struct.pack_into("<Q", previous_image, 24, 8)
struct.pack_into("<Q", previous_image, 256, 11)
previous_image[480:512] = hashlib.sha256(previous_image[:480]).digest()
previous_root = array(previous_image)


def backend_for(fail=None, abort_fail=False):
    state = {"events": [], "callbacks": []}
    def status(name):
        state["events"].append(name)
        if name == "abort" and abort_fail:
            return IO
        return IO if fail == name else OK
    @BEGIN_CB
    def begin(ctx, tx, object_count, extent_count, edge_count):
        assert (tx, object_count, extent_count, edge_count) == (
            11, len(objects), sum(value.extent_count for value in objects),
            len(edges))
        return status("begin")
    @PAIR_CB
    def put_object(ctx, value):
        return status("object")
    @PAIR_CB
    def put_edge(ctx, value):
        return status("edge")
    @ROOT_CB
    def stage_root(ctx, value, length, generation, object_index_hash,
                   ownership_root_hash, ref_root_hash):
        assert length == len(root_bytes) and generation == 9
        assert ctypes.string_at(object_index_hash, 32) == bytes(index_hash)
        assert ctypes.string_at(ownership_root_hash, 32) == bytes(ownership_hash)
        assert ctypes.string_at(ref_root_hash, 32) == bytes(ref_hash)
        return status("root")
    @SIMPLE_CB
    def flush(ctx):
        return status("flush")
    @SIMPLE_CB
    def publish(ctx):
        return status("publish")
    @SIMPLE_CB
    def abort(ctx):
        return status("abort")
    @SIMPLE_CB
    def poison(ctx):
        state["events"].append("poison")
        return OK
    callbacks = [begin, put_object, put_edge, stage_root, flush, publish, abort, poison]
    state["callbacks"] = callbacks
    backend = Backend(None, *[ctypes.cast(cb, ctypes.c_void_p).value for cb in callbacks])
    return backend, state


def request(backend):
    return Publication(ctypes.pointer(backend), previous_root, objects,
                       len(objects),
                       edges, len(edges), transaction_owner, root,
                       len(root_bytes), 11, 9, ctypes.pointer(index_root),
                       ctypes.pointer(ownership_root), ctypes.pointer(ref_root),
                       0xBAD)


backend, state = backend_for()
publication = request(backend)
success_status = lib.vcs_publication_commit(ctypes.byref(publication))
assert success_status == OK
assert publication.result_phase == COMMITTED
assert state["events"] == (["begin"] + ["object"] * len(objects)
                           + ["edge"] * len(edges)
                           + ["root", "flush", "publish"])

# Newly staged commits must insert their canonical dependency edges in this
# transaction, even when the complete candidate catalog already contains them.
commit_dependency_index = next(
    index for index, edge in enumerate(edges)
    if edge.owner_kind == 1 and edge.child_type == 3
    and bytes(edge.owner_key) == commit_id)
missing_dependency_values = [bytes(edge) for index, edge in enumerate(edges)
                             if index != commit_dependency_index]
missing_dependency_edges = (Edge * len(missing_dependency_values))()
for edge, value in zip(missing_dependency_edges, missing_dependency_values):
    ctypes.memmove(ctypes.byref(edge), value, len(value))
backend, state = backend_for()
publication = request(backend)
publication.edges = missing_dependency_edges
publication.edge_count = len(missing_dependency_edges)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

for failed, phase in (("begin", NONE), ("object", ABORTED), ("edge", ABORTED),
                      ("root", ABORTED), ("flush", ABORTED)):
    backend, state = backend_for(failed)
    publication = request(backend)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == IO
    assert publication.result_phase == phase
    if failed == "begin":
        assert state["events"] == ["begin"]
    else:
        assert state["events"][-1] == "abort" and "publish" not in state["events"]

backend, state = backend_for("publish")
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == IO
assert publication.result_phase == POISONED
assert state["events"][-2:] == ["publish", "poison"] and "abort" not in state["events"]

backend, state = backend_for("object", abort_fail=True)
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == IO
assert publication.result_phase == POISONED
assert state["events"][-2:] == ["abort", "poison"]

# Preflight rejects an ID mismatch before touching backend state or result phase.
backend, state = backend_for()
publication = request(backend)
objects[0].object_id[0] ^= 1
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
objects[0].object_id[0] ^= 1

# An unauthenticated index generation fails before begin and leaves phase intact.
publication = request(backend)
index_hash[0] ^= 1
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
index_hash[0] ^= 1

# Ownership generation and superblock binding fail before backend state opens.
ownership_hash[0] ^= 1
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ownership_hash[0] ^= 1
ownership_root.generation = 10
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ownership_root.generation = 9

candidate = bytearray(root_image)
candidate[120] ^= 1
candidate[480:512] = hashlib.sha256(candidate[:480]).digest()
candidate_buffer = array(candidate)
backend, state = backend_for()
publication = request(backend)
publication.root = candidate_buffer
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

subset = (Edge * (len(edges) - 1))()
ctypes.memmove(subset, ctypes.byref(edges, ctypes.sizeof(Edge)),
               ctypes.sizeof(subset))
subset_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 2, 0, 9,
                                          ctypes.sizeof(subset))
subset_hash = array(hashlib.sha256(subset_frame + bytes(subset)).digest())
subset_root = OwnershipRoot(subset, len(subset), 9, subset_hash)
subset_candidate = bytearray(root_image)
subset_candidate[120:152] = bytes(subset_hash)
subset_candidate[480:512] = hashlib.sha256(subset_candidate[:480]).digest()
subset_candidate_buffer = array(subset_candidate)
backend, state = backend_for()
publication = request(backend)
publication.root = subset_candidate_buffer
publication.ownership_root = ctypes.pointer(subset_root)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

# Ref generation and exact superblock binding are authenticated independently.
ref_hash[0] ^= 1
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ref_hash[0] ^= 1
ref_root.generation = 10
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ref_root.generation = 9
ref_candidate = bytearray(root_image)
ref_candidate[88] ^= 1
ref_candidate[480:512] = hashlib.sha256(ref_candidate[:480]).digest()
ref_candidate_buffer = array(ref_candidate)
backend, state = backend_for()
publication = request(backend)
publication.root = ref_candidate_buffer
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

for target_offset in (16, len(branch_record) + 16):
    dangling_bytes = bytearray(ref_record)
    dangling_bytes[target_offset] ^= 1
    dangling_records = array(dangling_bytes)
    dangling_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 1, 0, 9,
                                                len(dangling_bytes))
    dangling_hash = array(hashlib.sha256(dangling_frame
                                         + dangling_bytes).digest())
    dangling_root = RefRoot(dangling_records, len(dangling_bytes), 9,
                            dangling_hash)
    dangling_candidate = bytearray(root_image)
    dangling_candidate[88:120] = bytes(dangling_hash)
    dangling_candidate[480:512] = hashlib.sha256(
        dangling_candidate[:480]).digest()
    dangling_candidate_buffer = array(dangling_candidate)
    backend, state = backend_for()
    publication = request(backend)
    publication.root = dangling_candidate_buffer
    publication.ref_root = ctypes.pointer(dangling_root)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []

# Attached HEAD is one atomic state: its selected branch target must equal the
# candidate superblock HEAD even when both IDs independently name valid commits.
split_head_candidate = bytearray(root_image)
split_head_candidate[56:88] = alternate_commit_id
split_head_candidate[480:512] = hashlib.sha256(
    split_head_candidate[:480]).digest()
split_head_candidate_buffer = array(split_head_candidate)
backend, state = backend_for()
publication = request(backend)
publication.root = split_head_candidate_buffer
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

# A branch cannot keep a commit live unless the authenticated ownership catalog
# contains the exact ref-key-to-commit edge.
ref_edge_index = next(index for index, edge in enumerate(edges)
                      if edge.owner_kind == 2)
without_ref_values = [bytes(edge) for index, edge in enumerate(edges)
                      if index != ref_edge_index]
without_ref_edges = (Edge * len(without_ref_values))()
for edge, value in zip(without_ref_edges, without_ref_values):
    ctypes.memmove(ctypes.byref(edge), value, len(value))
without_ref_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 2, 0, 9,
                                                ctypes.sizeof(without_ref_edges))
without_ref_hash = array(hashlib.sha256(without_ref_frame
                                        + bytes(without_ref_edges)).digest())
without_ref_root = OwnershipRoot(without_ref_edges, len(without_ref_edges), 9,
                                 without_ref_hash)
without_ref_candidate = bytearray(root_image)
without_ref_candidate[120:152] = bytes(without_ref_hash)
without_ref_candidate[480:512] = hashlib.sha256(
    without_ref_candidate[:480]).digest()
without_ref_candidate_buffer = array(without_ref_candidate)
backend, state = backend_for()
publication = request(backend)
publication.root = without_ref_candidate_buffer
publication.ownership_root = ctypes.pointer(without_ref_root)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

# Publication must be the exact successor of the recovered repository root and
# consume that root's advertised transaction sequence before begin.
for field, replacement in (
    ("previous_root", None),
    ("tx_sequence", 10),
    ("generation", 10),
):
    backend, state = backend_for()
    publication = request(backend)
    setattr(publication, field, replacement)
    transition_status = lib.vcs_publication_commit(ctypes.byref(publication))
    assert transition_status in (CORRUPT, USAGE), (field, transition_status)
    assert publication.result_phase == 0xBAD and state["events"] == []

wrong_repository = bytearray(previous_image)
wrong_repository[32] ^= 1
wrong_repository[480:512] = hashlib.sha256(wrong_repository[:480]).digest()
wrong_repository_buffer = array(wrong_repository)
backend, state = backend_for()
publication = request(backend)
publication.previous_root = wrong_repository_buffer
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

for offset, value in ((24, 7), (256, 10)):
    bad_previous = bytearray(previous_image)
    struct.pack_into("<Q", bad_previous, offset, value)
    bad_previous[480:512] = hashlib.sha256(bad_previous[:480]).digest()
    bad_previous_buffer = array(bad_previous)
    backend, state = backend_for()
    publication = request(backend)
    publication.previous_root = bad_previous_buffer
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []

bad_candidate = bytearray(root_image)
struct.pack_into("<Q", bad_candidate, 256, 13)
bad_candidate[480:512] = hashlib.sha256(bad_candidate[:480]).digest()
bad_candidate_buffer = array(bad_candidate)
backend, state = backend_for()
publication = request(backend)
publication.root = bad_candidate_buffer
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

# HEAD and every immutable ownership endpoint must be authenticated by the
# exact index generation before the backend transaction begins.
for mutation in ("head_missing", "head_wrong_type", "child_missing",
                 "child_wrong_type", "owner_missing"):
    backend, state = backend_for()
    publication = request(backend)
    if mutation.startswith("head"):
        candidate = bytearray(root_image)
        candidate[56:88] = (b"\xff" * 32 if mutation == "head_missing"
                            else bytes(objects[file_index].object_id))
        candidate[480:512] = hashlib.sha256(candidate[:480]).digest()
        candidate_buffer = array(candidate)
        publication.root = candidate_buffer
    elif mutation == "child_missing":
        edges[immutable_edge_index].child_id[0] ^= 1
    elif mutation == "child_wrong_type":
        edges[immutable_edge_index].child_type = 10
    else:
        edges[immutable_edge_index].owner_key[0] ^= 1
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
    if mutation == "child_missing":
        edges[immutable_edge_index].child_id[0] ^= 1
    elif mutation == "child_wrong_type":
        edges[immutable_edge_index].child_type = immutable_edge_type
    elif mutation == "owner_missing":
        edges[immutable_edge_index].owner_key[0] ^= 1

# Staged objects are a strict unique ID set created by this transaction.
saved_objects = bytes(objects)
ctypes.memmove(ctypes.byref(objects, ctypes.sizeof(PublishObject)),
               ctypes.byref(objects), ctypes.sizeof(PublishObject))
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ctypes.memmove(ctypes.byref(objects), saved_objects, len(saved_objects))

first = bytes(ctypes.string_at(ctypes.byref(objects), ctypes.sizeof(PublishObject)))
second = bytes(ctypes.string_at(ctypes.byref(objects, ctypes.sizeof(PublishObject)),
                                ctypes.sizeof(PublishObject)))
ctypes.memmove(ctypes.byref(objects), second, len(second))
ctypes.memmove(ctypes.byref(objects, ctypes.sizeof(PublishObject)), first, len(first))
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ctypes.memmove(ctypes.byref(objects), saved_objects, len(saved_objects))

staged_record = next(record for record in index_records
                     if bytes(record.object_id) == bytes(objects[0].object_id))
staged_record.transaction = 12
index_hash[:] = hashlib.sha256(index_frame + bytes(index_records)).digest()
root_image[184:216] = bytes(index_hash)
root_image[480:512] = hashlib.sha256(root_image[:480]).digest()
root[:] = root_image
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
staged_record.transaction = 11
index_hash[:] = hashlib.sha256(index_frame + bytes(index_records)).digest()
root_image[184:216] = bytes(index_hash)
root_image[480:512] = hashlib.sha256(root_image[:480]).digest()
root[:] = root_image

# A current-transaction index record must have a matching staged object, and no
# authenticated record may claim a transaction newer than the candidate.
unstaged_record = next(record for record in index_records
                       if bytes(record.object_id) == alternate_commit_id)
for invalid_transaction in (11, 12):
    unstaged_record.transaction = invalid_transaction
    index_hash[:] = hashlib.sha256(index_frame + bytes(index_records)).digest()
    root_image[184:216] = bytes(index_hash)
    root_image[480:512] = hashlib.sha256(root_image[:480]).digest()
    root[:] = root_image
    backend, state = backend_for()
    publication = request(backend)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
unstaged_record.transaction = 10
index_hash[:] = hashlib.sha256(index_frame + bytes(index_records)).digest()
root_image[184:216] = bytes(index_hash)
root_image[480:512] = hashlib.sha256(root_image[:480]).digest()
root[:] = root_image

for envelope in (0, 999):
    saved_envelope = objects[0].envelope
    objects[0].envelope = envelope
    backend, state = backend_for()
    publication = request(backend)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
    objects[0].envelope = saved_envelope

header_test_index = file_index
saved_header = bytes(envelope_buffers[header_test_index])
for offset in (0, 12, 24, 72, 80, 88, 120):
    envelope_buffers[header_test_index][offset] ^= 1
    backend, state = backend_for()
    publication = request(backend)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
    envelope_buffers[header_test_index][:] = saved_header
saved_header_address = ctypes.cast(objects[header_test_index].envelope_header,
                                   ctypes.c_void_p).value
objects[header_test_index].envelope_header = None
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == USAGE
assert publication.result_phase == 0xBAD and state["events"] == []
objects[header_test_index].envelope_header = ctypes.cast(saved_header_address, P)

multi_index = next(index for index, value in enumerate(objects)
                   if value.extent_count > 1)
saved_extents = bytes(extent_buffers[multi_index])
for offset in (0, 10, 12, 16, 48, 56, 64, 4096 + 64, 4095):
    extent_buffers[multi_index][offset] ^= 1
    backend, state = backend_for()
    publication = request(backend)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
    extent_buffers[multi_index][:] = saved_extents
saved_locator = locator_buffers[multi_index][1]
locator_buffers[multi_index][1] = locator_buffers[multi_index][0]
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
locator_buffers[multi_index][1] = saved_locator
saved_extent_count = objects[multi_index].extent_count
objects[multi_index].extent_count -= 1
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
objects[multi_index].extent_count = saved_extent_count
saved_extents_address = ctypes.cast(objects[multi_index].extents,
                                    ctypes.c_void_p).value
objects[multi_index].extents = None
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == USAGE
assert publication.result_phase == 0xBAD and state["events"] == []
objects[multi_index].extents = ctypes.cast(saved_extents_address, P)

saved_counts = objects[0].extent_count, objects[1].extent_count
objects[0].extent_count = (1 << 64) - 1
objects[1].extent_count = 1
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == NO_MEM
assert publication.result_phase == 0xBAD and state["events"] == []
objects[0].extent_count, objects[1].extent_count = saved_counts

# Ownership inputs are canonical and every staged object is pinned by the
# current transaction key before durable staging begins.
saved_edges = bytes(edges)
ctypes.memmove(ctypes.byref(edges, ctypes.sizeof(Edge)),
               ctypes.byref(edges), ctypes.sizeof(Edge))
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ctypes.memmove(ctypes.byref(edges), saved_edges, len(saved_edges))

pin_index = next(index for index, edge in enumerate(edges)
                 if edge.owner_kind == 5)
edges[pin_index].owner_kind = 3
backend, state = backend_for()
publication = request(backend)
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []
ctypes.memmove(ctypes.byref(edges), saved_edges, len(saved_edges))

wrong_transaction_owner = array(hashlib.sha256(b"wrong transaction").digest())
backend, state = backend_for()
publication = request(backend)
publication.transaction_owner = wrong_transaction_owner
assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
assert publication.result_phase == 0xBAD and state["events"] == []

print("VCS publication: PASS (catalog transaction and ownership closure, extent chains, atomic failures)")
