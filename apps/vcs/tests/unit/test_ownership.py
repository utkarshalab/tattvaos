"""Exact ownership-edge and explicit reclamation accounting tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NO_MEM, CORRUPT, CONFLICT = 0, 3, 5, 6
PAGE_BYTES = 4064


class Entry(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32),
                ("offset", ctypes.c_uint64), ("length", ctypes.c_uint64),
                ("storage_index", ctypes.c_uint64), ("flags", ctypes.c_uint64)]


class Record(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32), ("data", P),
                ("length", ctypes.c_uint64)]


class Build(ctypes.Structure):
    _fields_ = [("data", P), ("length", ctypes.c_uint64),
                ("entries", ctypes.POINTER(Entry)), ("entry_count", ctypes.c_uint64),
                ("mode", ctypes.c_uint64), ("flags", ctypes.c_uint64),
                ("pages", P), ("page_capacity", ctypes.c_uint64),
                ("page_ids", P), ("page_lengths", ctypes.POINTER(ctypes.c_uint64)),
                ("root", P), ("root_id", P), ("result_pages", ctypes.c_uint64)]


class Read(ctypes.Structure):
    _fields_ = [("root", P), ("root_id", P),
                ("pages", ctypes.POINTER(Record)), ("page_count", ctypes.c_uint64),
                ("chunks", ctypes.POINTER(Record)), ("chunk_count", ctypes.c_uint64),
                ("output", P), ("output_capacity", ctypes.c_uint64),
                ("result_length", ctypes.c_uint64)]


class Edge(ctypes.Structure):
    _fields_ = [("owner_kind", ctypes.c_uint32), ("child_type", ctypes.c_uint32),
                ("owner_key", ctypes.c_ubyte * 32),
                ("child_id", ctypes.c_ubyte * 32), ("flags", ctypes.c_uint64)]


class FileOwnership(ctypes.Structure):
    _fields_ = [("file", ctypes.POINTER(Read)), ("edges", ctypes.POINTER(Edge)),
                ("edge_capacity", ctypes.c_uint64), ("result_edges", ctypes.c_uint64)]


class Reclaim(ctypes.Structure):
    _fields_ = [("object_id", P), ("catalog", ctypes.POINTER(Edge)),
                ("catalog_count", ctypes.c_uint64), ("active_readers", ctypes.c_uint64)]


for name, arg in (("vcs_file_object_build", Build),
                  ("vcs_file_object_verify", Read),
                  ("vcs_file_ownership_edges", FileOwnership),
                  ("vcs_ownership_reclaimable", Reclaim)):
    getattr(lib, name).argtypes = [ctypes.POINTER(arg)]
    getattr(lib, name).restype = ctypes.c_uint64
lib.vcs_ownership_catalog_validate.argtypes = [ctypes.POINTER(Edge), ctypes.c_uint64]
lib.vcs_ownership_catalog_validate.restype = ctypes.c_uint64
lib.vcs_ownership_edge_validate.argtypes = [ctypes.POINTER(Edge)]
lib.vcs_ownership_edge_validate.restype = ctypes.c_uint64


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def oid(kind, payload):
    return hashlib.sha256(b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload)) + payload).digest()


base = bytes((i * 19) & 0xFF for i in range(2048))
parts = [base, base]
parts += [bytes(((index * 23 + i) & 0xFF) for i in range(2048 + index % 31))
          for index in range(2, 100)]
parts += [base]
parts += [bytes(((index * 29 + i * 3) & 0xFF) for i in range(2100))
          for index in range(101, 105)]
data = b"".join(parts)
source = array(data)
entries = (Entry * len(parts))()
offset = 0
for index, part in enumerate(parts):
    entries[index].object_id[:] = oid(1, part)
    entries[index].offset = offset
    entries[index].length = len(part)
    offset += len(part)

pages = (ctypes.c_ubyte * (2 * PAGE_BYTES))()
page_ids = (ctypes.c_ubyte * 64)()
page_lengths = (ctypes.c_uint64 * 2)()
root = (ctypes.c_ubyte * 128)()
root_id = (ctypes.c_ubyte * 32)()
build = Build(source, len(data), entries, len(parts), 0o644, 0, pages, 2,
              page_ids, page_lengths, root, root_id, 0)
assert lib.vcs_file_object_build(ctypes.byref(build)) == OK

page_records = (Record * 2)()
for index in range(2):
    page_records[index].object_id[:] = bytes(page_ids[index * 32:(index + 1) * 32])
    page_records[index].data = ctypes.cast(ctypes.byref(pages, index * PAGE_BYTES), P)
    page_records[index].length = page_lengths[index]
chunk_records = (Record * len(parts))()
chunk_buffers = []
for index, part in enumerate(parts):
    buf = array(part)
    chunk_buffers.append(buf)
    chunk_records[index].object_id[:] = oid(1, part)
    chunk_records[index].data = buf
    chunk_records[index].length = len(part)

read = Read(root, root_id, page_records, 2, chunk_records, len(parts), None, 0, 0xBAD)
assert lib.vcs_file_object_verify(ctypes.byref(read)) == OK
assert read.result_length == 0xBAD

edges = (Edge * (len(parts) + 2))()
ownership = FileOwnership(ctypes.pointer(read), edges, len(edges), 0xBAD)
assert lib.vcs_file_ownership_edges(ctypes.byref(ownership)) == OK
# Two page-link edges + 99 unique chunks on page zero + five on page one.
assert ownership.result_edges == 106
for edge in edges[:ownership.result_edges]:
    assert lib.vcs_ownership_edge_validate(ctypes.byref(edge)) == OK

raw_edges = [bytes(edge) for edge in edges[:ownership.result_edges]]
def edge_key(raw):
    return raw[40:72], struct.unpack_from("<I", raw, 0)[0], raw[8:40]
ordered_raw = sorted(raw_edges, key=edge_key)
ordered = (Edge * len(ordered_raw))()
for index, raw in enumerate(ordered_raw):
    ctypes.memmove(ctypes.byref(ordered[index]), raw, len(raw))
assert lib.vcs_ownership_catalog_validate(ordered, len(ordered)) == OK

duplicate_raw = sorted(raw_edges + [raw_edges[0]], key=edge_key)
duplicate = (Edge * len(duplicate_raw))()
for index, raw in enumerate(duplicate_raw):
    ctypes.memmove(ctypes.byref(duplicate[index]), raw, len(raw))
assert lib.vcs_ownership_catalog_validate(duplicate, len(duplicate)) == CORRUPT

owned_id = (ctypes.c_ubyte * 32).from_buffer_copy(ordered[0].child_id)
check = Reclaim(owned_id, ordered, len(ordered), 0)
assert lib.vcs_ownership_reclaimable(ctypes.byref(check)) == CONFLICT
free_id = (ctypes.c_ubyte * 32)(*hashlib.sha256(b"unowned").digest())
check = Reclaim(free_id, ordered, len(ordered), 0)
assert lib.vcs_ownership_reclaimable(ctypes.byref(check)) == OK
check.active_readers = 1
assert lib.vcs_ownership_reclaimable(ctypes.byref(check)) == CONFLICT

bad = Edge.from_buffer_copy(bytes(ordered[0]))
bad.flags = 1
assert lib.vcs_ownership_edge_validate(ctypes.byref(bad)) == CORRUPT

small_edges = (Edge * 1)()
small = FileOwnership(ctypes.pointer(read), small_edges, 1, 0xBAD)
assert lib.vcs_file_ownership_edges(ctypes.byref(small)) == NO_MEM
assert small.result_edges == 0xBAD

print("VCS ownership: PASS (file edges, duplicate collapse, catalog order, explicit reclaim proof)")
