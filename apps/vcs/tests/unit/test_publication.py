"""Recoverable publication phase-machine and failure-injection tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, IO, CORRUPT = 0, 4, 5
NONE, BEGUN, OBJECTS, OWNERSHIP, ROOT, FLUSHED, COMMITTED, POISONED, ABORTED = range(9)


class PublishObject(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32),
                ("object_type", ctypes.c_uint32), ("flags", ctypes.c_uint32),
                ("payload", P), ("length", ctypes.c_uint64)]


class Edge(ctypes.Structure):
    _fields_ = [("owner_kind", ctypes.c_uint32), ("child_type", ctypes.c_uint32),
                ("owner_key", ctypes.c_ubyte * 32),
                ("child_id", ctypes.c_ubyte * 32), ("flags", ctypes.c_uint64)]


class Backend(ctypes.Structure):
    _fields_ = [("context", ctypes.c_void_p), ("begin", ctypes.c_void_p),
                ("put_object", ctypes.c_void_p), ("put_edge", ctypes.c_void_p),
                ("stage_root", ctypes.c_void_p), ("flush", ctypes.c_void_p),
                ("publish", ctypes.c_void_p), ("abort", ctypes.c_void_p),
                ("poison", ctypes.c_void_p)]


class Publication(ctypes.Structure):
    _fields_ = [("backend", ctypes.POINTER(Backend)),
                ("objects", ctypes.POINTER(PublishObject)),
                ("object_count", ctypes.c_uint64),
                ("edges", ctypes.POINTER(Edge)), ("edge_count", ctypes.c_uint64),
                ("root", P), ("root_length", ctypes.c_uint64),
                ("tx_sequence", ctypes.c_uint64), ("generation", ctypes.c_uint64),
                ("result_phase", ctypes.c_uint64)]


lib.vcs_publication_commit.argtypes = [ctypes.POINTER(Publication)]
lib.vcs_publication_commit.restype = ctypes.c_uint64

BEGIN_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_uint64,
                           ctypes.c_uint64, ctypes.c_uint64)
PAIR_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p)
ROOT_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p,
                          ctypes.c_uint64, ctypes.c_uint64)
SIMPLE_CB = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p)


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def oid(kind, payload):
    return hashlib.sha256(b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload)) + payload).digest()


payloads = [b"first immutable payload", b"second canonical object"]
payload_buffers = [array(value) for value in payloads]
objects = (PublishObject * 2)()
for index, payload in enumerate(payloads):
    kind = index + 1
    objects[index].object_id[:] = oid(kind, payload)
    objects[index].object_type = kind
    objects[index].payload = payload_buffers[index]
    objects[index].length = len(payload)

edges = (Edge * 1)()
edges[0].owner_kind = 1
edges[0].child_type = 1
edges[0].owner_key[:] = objects[1].object_id
edges[0].child_id[:] = objects[0].object_id
root_bytes = b"checksummed generation root"
root = array(root_bytes)


def backend_for(fail=None, abort_fail=False):
    state = {"events": [], "callbacks": []}
    def status(name):
        state["events"].append(name)
        if name == "abort" and abort_fail:
            return IO
        return IO if fail == name else OK
    @BEGIN_CB
    def begin(ctx, tx, object_count, edge_count):
        assert (tx, object_count, edge_count) == (11, 2, 1)
        return status("begin")
    @PAIR_CB
    def put_object(ctx, value):
        return status("object")
    @PAIR_CB
    def put_edge(ctx, value):
        return status("edge")
    @ROOT_CB
    def stage_root(ctx, value, length, generation):
        assert length == len(root_bytes) and generation == 9
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
    return Publication(ctypes.pointer(backend), objects, 2, edges, 1, root,
                       len(root_bytes), 11, 9, 0xBAD)


backend, state = backend_for()
publication = request(backend)
success_status = lib.vcs_publication_commit(ctypes.byref(publication))
assert success_status == OK
assert publication.result_phase == COMMITTED
assert state["events"] == ["begin", "object", "object", "edge", "root", "flush", "publish"]

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

print("VCS publication: PASS (ordered phases, abort paths, poisoned barrier, preflight atomicity)")
