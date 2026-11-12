"""Canonical paged-tree construction and verified traversal tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NOT_FOUND, NO_MEM, CORRUPT = 0, 2, 3, 5
PAGE_BYTES, PAGE_HEADER, PAGE_MAX, ENTRY_BASE = 4064, 64, 64, 48


class Entry(ctypes.Structure):
    _fields_ = [("name", P), ("name_length", ctypes.c_uint64),
                ("target_id", ctypes.c_ubyte * 32),
                ("target_size", ctypes.c_uint64), ("kind", ctypes.c_uint64),
                ("mode", ctypes.c_uint64), ("flags", ctypes.c_uint64)]


class Record(ctypes.Structure):
    _fields_ = [("object_id", ctypes.c_ubyte * 32), ("data", P),
                ("length", ctypes.c_uint64)]


class Build(ctypes.Structure):
    _fields_ = [("entries", ctypes.POINTER(Entry)), ("entry_count", ctypes.c_uint64),
                ("pages", P), ("page_capacity", ctypes.c_uint64),
                ("page_ids", P), ("page_lengths", ctypes.POINTER(ctypes.c_uint64)),
                ("page_starts", ctypes.POINTER(ctypes.c_uint64)),
                ("page_counts", ctypes.POINTER(ctypes.c_uint64)),
                ("root", P), ("root_id", P), ("result_pages", ctypes.c_uint64)]


class Read(ctypes.Structure):
    _fields_ = [("root", P), ("root_id", P),
                ("pages", ctypes.POINTER(Record)), ("page_count", ctypes.c_uint64),
                ("entries", ctypes.POINTER(Entry)), ("entry_capacity", ctypes.c_uint64),
                ("result_entries", ctypes.c_uint64)]


lib.vcs_tree_object_build.argtypes = [ctypes.POINTER(Build)]
lib.vcs_tree_object_build.restype = ctypes.c_uint64
lib.vcs_tree_object_read.argtypes = [ctypes.POINTER(Read)]
lib.vcs_tree_object_read.restype = ctypes.c_uint64
lib.vcs_tree_object_verify.argtypes = [ctypes.POINTER(Read)]
lib.vcs_tree_object_verify.restype = ctypes.c_uint64


def oid(kind, payload):
    return hashlib.sha256(b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload)) + payload).digest()


def target(index):
    return hashlib.sha256(b"tree-target" + struct.pack("<Q", index)).digest()


def make_names(count):
    names = [f"entry-{index:04d}-{'x' * (index % 79)}".encode() for index in range(count - 2)]
    names += ["नेपाली".encode(), "文件".encode()]
    return sorted(names)


def build_tree(names):
    buffers = [(ctypes.c_ubyte * len(name))(*name) for name in names]
    entries = (Entry * max(1, len(names)))()
    for index, (name, buf) in enumerate(zip(names, buffers)):
        entries[index].name = ctypes.cast(buf, P)
        entries[index].name_length = len(name)
        entries[index].target_id[:] = target(index)
        entries[index].target_size = index * 101
        entries[index].kind = 2 if index % 7 else 3
        entries[index].mode = 0o644 if entries[index].kind == 2 else 0o755
    capacity = max(1, (len(names) + PAGE_MAX - 1) // PAGE_MAX + 2)
    pages = (ctypes.c_ubyte * (capacity * PAGE_BYTES))()
    page_ids = (ctypes.c_ubyte * (capacity * 32))()
    lengths = (ctypes.c_uint64 * capacity)()
    starts = (ctypes.c_uint64 * capacity)()
    counts = (ctypes.c_uint64 * capacity)()
    root = (ctypes.c_ubyte * 96)()
    root_id = (ctypes.c_ubyte * 32)()
    request = Build(entries if names else None, len(names), pages, capacity, page_ids,
                    lengths, starts, counts, root, root_id, 0xBAD)
    assert lib.vcs_tree_object_build(ctypes.byref(request)) == OK
    return buffers, entries, pages, page_ids, lengths, starts, counts, root, root_id, request.result_pages


def page_records(pages, ids, lengths, count):
    records = (Record * max(1, count))()
    for index in range(count):
        records[index].object_id[:] = bytes(ids[index * 32:(index + 1) * 32])
        records[index].data = ctypes.cast(ctypes.byref(pages, index * PAGE_BYTES), P)
        records[index].length = lengths[index]
    return records


names = make_names(173)
buffers, source, pages, ids, lengths, starts, counts, root, root_id, page_count = build_tree(names)
assert page_count >= 3 and sum(counts[:page_count]) == len(names)
assert bytes(root[:8]) == b"UVCSTRE1"
assert struct.unpack_from("<QQQ", bytes(root), 8) == (len(names), page_count, 0)
assert bytes(root_id) == oid(3, bytes(root))

# Independently reconstruct every canonical greedy page and its reverse-linked ID.
next_id = bytes(32)
for index in range(page_count - 1, -1, -1):
    payload = bytearray()
    for entry_index in range(starts[index], starts[index] + counts[index]):
        name = names[entry_index]
        encoded = struct.pack("<BBHIQ", source[entry_index].kind, len(name),
                              source[entry_index].mode, 0, source[entry_index].target_size)
        encoded += target(entry_index) + name
        encoded += bytes((-len(name)) & 7)
        payload += encoded
    expected = b"UVCSTPG1" + struct.pack("<IIQQ", index, counts[index], len(payload), 0)
    expected += next_id + payload
    actual = bytes(pages[index * PAGE_BYTES:index * PAGE_BYTES + lengths[index]])
    assert actual == expected
    assert bytes(ids[index * 32:(index + 1) * 32]) == oid(10, expected)
    next_id = oid(10, expected)
assert bytes(root[32:64]) == bytes(ids[:32])

records = page_records(pages, ids, lengths, page_count)
decoded = (Entry * len(names))()
read = Read(root, root_id, records, page_count, decoded, len(decoded), 0xBAD)
assert lib.vcs_tree_object_read(ctypes.byref(read)) == OK
assert read.result_entries == len(names)
for index, name in enumerate(names):
    assert ctypes.string_at(decoded[index].name, decoded[index].name_length) == name
    assert bytes(decoded[index].target_id) == target(index)
    assert decoded[index].target_size == index * 101
    assert decoded[index].kind == source[index].kind
    assert decoded[index].mode == source[index].mode

verify = Read(root, root_id, records, page_count, None, 0, 0xBAD)
assert lib.vcs_tree_object_verify(ctypes.byref(verify)) == OK
assert verify.result_entries == 0xBAD

# Missing, reordered, corrupt, or undersized inputs do not publish decoded output.
for mutation, expected in (("missing", NOT_FOUND), ("reorder", NOT_FOUND),
                           ("corrupt", CORRUPT), ("small", NO_MEM)):
    local_records = page_records(pages, ids, lengths, page_count)
    if mutation == "reorder":
        local_records[0], local_records[1] = local_records[1], local_records[0]
    if mutation == "corrupt":
        pages[PAGE_HEADER] ^= 1
    output = (Entry * len(names))()
    ctypes.memset(ctypes.addressof(output), 0xCC, ctypes.sizeof(output))
    before = bytes(output)
    request = Read(root, root_id, local_records,
                   page_count - 1 if mutation == "missing" else page_count,
                   output, len(names) - 1 if mutation == "small" else len(names), 0xBAD)
    assert lib.vcs_tree_object_read(ctypes.byref(request)) == expected
    assert request.result_entries == 0xBAD and bytes(output) == before
    if mutation == "corrupt":
        pages[PAGE_HEADER] ^= 1

# Invalid ordering, reserved names, malformed UTF-8, flags, and zero targets are rejected.
for bad_names in ([b"b", b"a"], [b"a", b"a"], [b"."], [b".."], [b".vcs"],
                  [b"a/b"], [b"bad\x00name"], [b"\xc0\x80"]):
    buffers2 = [(ctypes.c_ubyte * len(name))(*name) for name in bad_names]
    entries2 = (Entry * len(bad_names))()
    for index, (name, buf) in enumerate(zip(bad_names, buffers2)):
        entries2[index].name = ctypes.cast(buf, P)
        entries2[index].name_length = len(name)
        entries2[index].target_id[:] = target(index)
        entries2[index].kind = 2
        entries2[index].mode = 0o644
    out_pages = (ctypes.c_ubyte * PAGE_BYTES)()
    out_ids = (ctypes.c_ubyte * 32)()
    out_lengths = (ctypes.c_uint64 * 1)()
    out_starts = (ctypes.c_uint64 * 1)()
    out_counts = (ctypes.c_uint64 * 1)()
    out_root = (ctypes.c_ubyte * 96)()
    out_root_id = (ctypes.c_ubyte * 32)()
    req = Build(entries2, len(bad_names), out_pages, 1, out_ids, out_lengths,
                out_starts, out_counts, out_root, out_root_id, 0xBAD)
    assert lib.vcs_tree_object_build(ctypes.byref(req)) == CORRUPT
    assert req.result_pages == 0xBAD

empty = build_tree([])
empty_read = Read(empty[7], empty[8], None, 0, None, 0, 77)
assert lib.vcs_tree_object_read(ctypes.byref(empty_read)) == OK
assert empty_read.result_entries == 0

print("VCS tree objects: PASS (canonical paging, UTF-8 names, IDs, traversal, atomic decode)")
