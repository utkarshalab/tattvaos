"""Paged-tree ownership-edge derivation tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NO_MEM, CORRUPT = 0, 3, 5
PAGE_BYTES, PAGE_HEADER, ENTRY_BASE = 4064, 64, 48


class TreeEntry(ctypes.Structure):
    _fields_ = [("name", P), ("name_length", ctypes.c_uint64),
                ("target_id", ctypes.c_ubyte * 32),
                ("target_size", ctypes.c_uint64), ("kind", ctypes.c_uint64),
                ("mode", ctypes.c_uint64), ("flags", ctypes.c_uint64)]


class Record(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32), ("data", P),
                ("length", ctypes.c_uint64)]


class TreeBuild(ctypes.Structure):
    _fields_ = [("entries", ctypes.POINTER(TreeEntry)), ("entry_count", ctypes.c_uint64),
                ("pages", P), ("page_capacity", ctypes.c_uint64),
                ("page_ids", P), ("page_lengths", ctypes.POINTER(ctypes.c_uint64)),
                ("page_starts", ctypes.POINTER(ctypes.c_uint64)),
                ("page_counts", ctypes.POINTER(ctypes.c_uint64)),
                ("root", P), ("root_id", P), ("result_pages", ctypes.c_uint64)]


class TreeRead(ctypes.Structure):
    _fields_ = [("root", P), ("root_id", P),
                ("pages", ctypes.POINTER(Record)), ("page_count", ctypes.c_uint64),
                ("entries", ctypes.POINTER(TreeEntry)), ("entry_capacity", ctypes.c_uint64),
                ("result_entries", ctypes.c_uint64)]


class Edge(ctypes.Structure):
    _fields_ = [("owner_kind", ctypes.c_uint32), ("child_type", ctypes.c_uint32),
                ("owner_key", ctypes.c_ubyte * 32),
                ("child_id", ctypes.c_ubyte * 32), ("flags", ctypes.c_uint64)]


class TreeOwnership(ctypes.Structure):
    _fields_ = [("tree", ctypes.POINTER(TreeRead)), ("edges", ctypes.POINTER(Edge)),
                ("edge_capacity", ctypes.c_uint64), ("result_edges", ctypes.c_uint64)]


lib.vcs_tree_object_build.argtypes = [ctypes.POINTER(TreeBuild)]
lib.vcs_tree_object_build.restype = ctypes.c_uint64
lib.vcs_tree_ownership_edges.argtypes = [ctypes.POINTER(TreeOwnership)]
lib.vcs_tree_ownership_edges.restype = ctypes.c_uint64
lib.vcs_ownership_edge_validate.argtypes = [ctypes.POINTER(Edge)]
lib.vcs_ownership_edge_validate.restype = ctypes.c_uint64


def target(group):
    return hashlib.sha256(b"owned-tree-target" + struct.pack("<Q", group)).digest()


names = [f"node-{index:04d}-{'x' * (index % 53)}".encode() for index in range(137)]
name_buffers = [(ctypes.c_ubyte * len(name))(*name) for name in names]
entries = (TreeEntry * len(names))()
for index, (name, buf) in enumerate(zip(names, name_buffers)):
    entries[index].name = ctypes.cast(buf, P)
    entries[index].name_length = len(name)
    entries[index].target_id[:] = target(index // 3)
    entries[index].target_size = index
    entries[index].kind = 2
    entries[index].mode = 0o644

capacity = 4
pages = (ctypes.c_ubyte * (capacity * PAGE_BYTES))()
page_ids = (ctypes.c_ubyte * (capacity * 32))()
lengths = (ctypes.c_uint64 * capacity)()
starts = (ctypes.c_uint64 * capacity)()
counts = (ctypes.c_uint64 * capacity)()
root = (ctypes.c_ubyte * 96)()
root_id = (ctypes.c_ubyte * 32)()
build = TreeBuild(entries, len(entries), pages, capacity, page_ids, lengths,
                  starts, counts, root, root_id, 0xBAD)
assert lib.vcs_tree_object_build(ctypes.byref(build)) == OK

records = (Record * build.result_pages)()
for page in range(build.result_pages):
    records[page].object_id[:] = bytes(page_ids[page * 32:(page + 1) * 32])
    records[page].data = ctypes.cast(ctypes.byref(pages, page * PAGE_BYTES), P)
    records[page].length = lengths[page]
read = TreeRead(root, root_id, records, build.result_pages, None, 0, 0xBAD)

expected_targets = 0
for page in range(build.result_pages):
    first, count = starts[page], counts[page]
    expected_targets += len({target(index // 3) for index in range(first, first + count)})
expected_edges = build.result_pages + expected_targets

edges = (Edge * (len(names) + build.result_pages))()
ownership = TreeOwnership(ctypes.pointer(read), edges, len(edges), 0xBAD)
assert lib.vcs_tree_ownership_edges(ctypes.byref(ownership)) == OK
assert ownership.result_edges == expected_edges

# The root owns page zero; each preceding page owns the next page.
for page in range(build.result_pages):
    edge = edges[page + sum(len({target(index // 3)
                                 for index in range(starts[p], starts[p] + counts[p])})
                             for p in range(page))]
    assert edge.owner_kind == 1 and edge.child_type == 10
    expected_owner = bytes(root_id) if page == 0 else bytes(page_ids[(page - 1) * 32:page * 32])
    assert bytes(edge.owner_key) == expected_owner
    assert bytes(edge.child_id) == bytes(page_ids[page * 32:(page + 1) * 32])

for edge in edges[:ownership.result_edges]:
    assert lib.vcs_ownership_edge_validate(ctypes.byref(edge)) == OK

# Capacity and corruption fail before publishing a result count.
small_edges = (Edge * 1)()
small = TreeOwnership(ctypes.pointer(read), small_edges, 1, 0xBAD)
assert lib.vcs_tree_ownership_edges(ctypes.byref(small)) == NO_MEM
assert small.result_edges == 0xBAD

pages[PAGE_HEADER + 16] ^= 1
corrupt = TreeOwnership(ctypes.pointer(read), edges, len(edges), 0xBAD)
assert lib.vcs_tree_ownership_edges(ctypes.byref(corrupt)) == CORRUPT
assert corrupt.result_edges == 0xBAD
pages[PAGE_HEADER + 16] ^= 1

# Empty trees have no dependency edges.
empty_root = (ctypes.c_ubyte * 96)()
empty_root[:8] = b"UVCSTRE1"
frame = b"UVCSHSH1" + struct.pack("<HHIQ", 1, 3, 0, 96)
empty_id = (ctypes.c_ubyte * 32)(*hashlib.sha256(frame + bytes(empty_root)).digest())
empty_read = TreeRead(empty_root, empty_id, None, 0, None, 0, 0xBAD)
empty = TreeOwnership(ctypes.pointer(empty_read), None, 0, 0xBAD)
assert lib.vcs_tree_ownership_edges(ctypes.byref(empty)) == OK
assert empty.result_edges == 0

print("VCS tree ownership: PASS (page chain, child targets, duplicate collapse, atomic failures)")
