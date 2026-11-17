"""Recoverable publication phase-machine and failure-injection tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, IO, CORRUPT, USAGE = 0, 4, 5, 8
NONE, BEGUN, OBJECTS, OWNERSHIP, ROOT, FLUSHED, COMMITTED, POISONED, ABORTED = range(9)


class PublishObject(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32),
                ("object_type", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("payload", P), ("length", ctypes.c_uint64),
                ("envelope", ctypes.c_uint64)]


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
                ("result_phase", ctypes.c_uint64)]


lib.vcs_publication_commit.argtypes = [ctypes.POINTER(Publication)]
lib.vcs_publication_commit.restype = ctypes.c_uint64

BEGIN_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
                           ctypes.c_uint64, ctypes.c_uint64)
PAIR_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p)
ROOT_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p,
                          ctypes.c_uint64, ctypes.c_uint64, ctypes.c_void_p)
SIMPLE_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p)


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def oid(kind, payload):
    return hashlib.sha256(b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload)) + payload).digest()


object_specs = [(1, b"first immutable payload"),
                (2, b"second canonical object")]
object_specs.sort(key=lambda value: oid(value[0], value[1]))
payload_buffers = [array(payload) for _, payload in object_specs]
objects = (PublishObject * 2)()
for index, (kind, payload) in enumerate(object_specs):
    objects[index].object_id[:] = oid(kind, payload)
    objects[index].object_type = kind
    objects[index].payload = payload_buffers[index]
    objects[index].length = len(payload)
    objects[index].envelope = 100 + index

chunk_index = next(index for index, spec in enumerate(object_specs) if spec[0] == 1)
file_index = next(index for index, spec in enumerate(object_specs) if spec[0] == 2)
transaction_owner = array(hashlib.sha256(b"publication transaction 11").digest())
edge_values = [(1, 1, bytes(objects[file_index].object_id),
                bytes(objects[chunk_index].object_id))]
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

commit_payload = b"canonical head commit"
commit_id = oid(4, commit_payload)
catalog = [(bytes(objects[index].object_id), 100 + index,
            objects[index].length, objects[index].object_type)
           for index in range(2)]
catalog.append((commit_id, 102, len(commit_payload), 4))
index_records = (IndexRecord * len(catalog))()
for slot, (object_id, envelope, length, object_type) in enumerate(
        sorted(catalog, key=lambda value: value[0])):
    index_records[slot].object_id[:] = object_id
    index_records[slot].envelope = envelope
    index_records[slot].payload_length = length
    index_records[slot].object_type = object_type
    index_records[slot].transaction = 11
index_frame = b"UVCSROT1" + struct.pack("<HHIQQ", 1, 5, 0, 9, ctypes.sizeof(index_records))
index_hash = array(hashlib.sha256(index_frame + bytes(index_records)).digest())
index_root = IndexRoot(index_records, len(catalog), 9, index_hash)

root_image = bytearray(512)
root_image[:8] = b"UVCSREP3"
struct.pack_into("<IIQQ", root_image, 8, 3, 512, 3, 9)
root_image[32:48] = hashlib.sha256(b"publication repository uuid").digest()[:16]
struct.pack_into("<II", root_image, 48, 1, 4096)
root_image[56:88] = commit_id
root_image[88:120] = hashlib.sha256(b"empty refs root").digest()
root_image[120:152] = hashlib.sha256(b"empty ownership root").digest()
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
    def begin(ctx, tx, object_count, edge_count):
        assert (tx, object_count, edge_count) == (11, 2, len(edges))
        return status("begin")
    @PAIR_CB
    def put_object(ctx, value):
        return status("object")
    @PAIR_CB
    def put_edge(ctx, value):
        return status("edge")
    @ROOT_CB
    def stage_root(ctx, value, length, generation, object_index_hash):
        assert length == len(root_bytes) and generation == 9
        assert ctypes.string_at(object_index_hash, 32) == bytes(index_hash)
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
    return Publication(ctypes.pointer(backend), previous_root, objects, 2,
                       edges, len(edges), transaction_owner, root,
                       len(root_bytes), 11, 9, ctypes.pointer(index_root), 0xBAD)


backend, state = backend_for()
publication = request(backend)
success_status = lib.vcs_publication_commit(ctypes.byref(publication))
assert success_status == OK
assert publication.result_phase == COMMITTED
assert state["events"] == ["begin", "object", "object", "edge", "edge",
                           "edge", "root", "flush", "publish"]

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
        edges[immutable_edge_index].child_type = 2
    else:
        edges[immutable_edge_index].owner_key[0] ^= 1
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
    if mutation == "child_missing":
        edges[immutable_edge_index].child_id[0] ^= 1
    elif mutation == "child_wrong_type":
        edges[immutable_edge_index].child_type = 1
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

for envelope in (0, 999):
    saved_envelope = objects[0].envelope
    objects[0].envelope = envelope
    backend, state = backend_for()
    publication = request(backend)
    assert lib.vcs_publication_commit(ctypes.byref(publication)) == CORRUPT
    assert publication.result_phase == 0xBAD and state["events"] == []
    objects[0].envelope = saved_envelope

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

print("VCS publication: PASS (authenticated closure/locators, canonical staging, transaction pins, atomic failures)")
