"""Canonical scalable commit and ownership-edge tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NO_MEM, CORRUPT = 0, 3, 5


class Edge(ctypes.Structure):
    _fields_ = [("owner_kind", ctypes.c_uint32), ("child_type", ctypes.c_uint32),
                ("owner_key", ctypes.c_ubyte * 32),
                ("child_id", ctypes.c_ubyte * 32), ("flags", ctypes.c_uint64)]


class CommitOwnership(ctypes.Structure):
    _fields_ = [("payload", P), ("length", ctypes.c_uint64), ("commit_id", P),
                ("edges", ctypes.POINTER(Edge)),
                ("edge_capacity", ctypes.c_uint64),
                ("result_edges", ctypes.c_uint64)]


lib.vcs_commit_object_verify.argtypes = [P, ctypes.c_uint64]
lib.vcs_commit_object_verify.restype = ctypes.c_uint64
lib.vcs_commit_ownership_edges.argtypes = [ctypes.POINTER(CommitOwnership)]
lib.vcs_commit_ownership_edges.restype = ctypes.c_uint64


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def oid(kind, payload):
    frame = b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload))
    return hashlib.sha256(frame + payload).digest()


def commit(root, parents=(), generation=1, flags=0, message=b"message"):
    header = bytearray(256)
    header[:8] = b"UVCSCOM3"
    struct.pack_into("<IIQqii", header, 8, flags, len(parents), generation,
                     123456789, 345, len(message))
    header[40:72] = root
    for offset, parent in zip((72, 104), parents):
        header[offset:offset + 32] = parent
    return bytes(header) + message


tree_id = hashlib.sha256(b"root tree").digest()
parent_one = hashlib.sha256(b"parent one").digest()
parent_two = hashlib.sha256(b"parent two").digest()

vectors = [
    (commit(tree_id), [tree_id], [3]),
    (commit(tree_id, (parent_one,), 2), [tree_id, parent_one], [3, 4]),
    (commit(tree_id, (parent_one, parent_two), 7, 1, b"merge\nmessage"),
     [tree_id, parent_one, parent_two], [3, 4, 4]),
]

for payload, children, types in vectors:
    payload_buffer = array(payload)
    commit_id = array(oid(4, payload))
    edges = (Edge * 3)()
    plan = CommitOwnership(payload_buffer, len(payload), commit_id, edges, 3, 99)
    assert lib.vcs_commit_object_verify(payload_buffer, len(payload)) == OK
    assert lib.vcs_commit_ownership_edges(ctypes.byref(plan)) == OK
    assert plan.result_edges == len(children)
    for edge, child, child_type in zip(edges, children, types):
        assert edge.owner_kind == 1 and edge.child_type == child_type
        assert bytes(edge.owner_key) == bytes(commit_id)
        assert bytes(edge.child_id) == child and edge.flags == 0

# Capacity failure is atomic and leaves caller storage/result untouched.
payload = vectors[-1][0]
payload_buffer = array(payload)
commit_id = array(oid(4, payload))
edges = (Edge * 3)()
ctypes.memset(edges, 0xA5, ctypes.sizeof(edges))
before = bytes(edges)
plan = CommitOwnership(payload_buffer, len(payload), commit_id, edges, 2, 77)
assert lib.vcs_commit_ownership_edges(ctypes.byref(plan)) == NO_MEM
assert plan.result_edges == 0 and bytes(edges) == before

bad_id = array(bytes(32))
plan = CommitOwnership(payload_buffer, len(payload), bad_id, edges, 3, 77)
assert lib.vcs_commit_ownership_edges(ctypes.byref(plan)) == CORRUPT
assert plan.result_edges == 0 and bytes(edges) == before

mutations = []
root = bytearray(commit(tree_id))
bad_magic = bytearray(root); bad_magic[0] ^= 1; mutations.append(bad_magic)
bad_flags = bytearray(root); struct.pack_into("<I", bad_flags, 8, 4); mutations.append(bad_flags)
bad_count = bytearray(root); struct.pack_into("<I", bad_count, 12, 3); mutations.append(bad_count)
bad_generation = bytearray(root); struct.pack_into("<Q", bad_generation, 16, 0); mutations.append(bad_generation)
bad_zone = bytearray(root); struct.pack_into("<i", bad_zone, 32, 1441); mutations.append(bad_zone)
bad_length = bytearray(root); struct.pack_into("<I", bad_length, 36, 6); mutations.append(bad_length)
bad_tree = bytearray(root); bad_tree[40:72] = bytes(32); mutations.append(bad_tree)
bad_reserved = bytearray(root); bad_reserved[216] = 1; mutations.append(bad_reserved)
bad_message = bytearray(root); bad_message[256] = 0; mutations.append(bad_message)
mutations.extend((
    bytearray(commit(tree_id, (), 2)),
    bytearray(commit(tree_id, (parent_one,), 1)),
    bytearray(commit(tree_id, (parent_one,), 2, 1)),
    bytearray(commit(tree_id, (parent_one, parent_one), 3, 1)),
    bytearray(commit(tree_id, (parent_one, parent_two), 3, 0)),
))
for malformed in mutations:
    malformed_buffer = array(malformed)
    assert lib.vcs_commit_object_verify(malformed_buffer,
                                        len(malformed)) == CORRUPT

print("VCS commit objects: PASS (canonical fields, messages, parents, ownership, atomic bounds)")
