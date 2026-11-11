"""Canonical paged-file construction and verified reconstruction tests."""
import ctypes
import hashlib
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
OK, NOT_FOUND, NO_MEM, CORRUPT = 0, 2, 3, 5
PAGE_BYTES, PAGE_MAX = 4064, 100


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


lib.vcs_file_object_build.argtypes = [ctypes.POINTER(Build)]
lib.vcs_file_object_build.restype = ctypes.c_uint64
lib.vcs_file_object_read.argtypes = [ctypes.POINTER(Read)]
lib.vcs_file_object_read.restype = ctypes.c_uint64


def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)


def oid(kind, payload):
    frame = b"UVCSHSH1" + struct.pack("<HHIQ", 1, kind, 0, len(payload))
    return hashlib.sha256(frame + payload).digest()


def build_file(parts, mode=0o644, flags=0):
    data = b"".join(parts)
    source = array(data)
    entries = (Entry * max(1, len(parts)))()
    offset = 0
    for index, part in enumerate(parts):
        entries[index].object_id[:] = oid(1, part)
        entries[index].offset = offset
        entries[index].length = len(part)
        offset += len(part)
    page_count = (len(parts) + PAGE_MAX - 1) // PAGE_MAX
    pages = (ctypes.c_ubyte * max(1, page_count * PAGE_BYTES))()
    page_ids = (ctypes.c_ubyte * max(1, page_count * 32))()
    page_lengths = (ctypes.c_uint64 * max(1, page_count))()
    root = (ctypes.c_ubyte * 128)()
    root_id = (ctypes.c_ubyte * 32)()
    request = Build(ctypes.cast(source, P) if data else None, len(data),
                    entries if parts else None, len(parts), mode, flags,
                    ctypes.cast(pages, P) if page_count else None, page_count,
                    ctypes.cast(page_ids, P) if page_count else None,
                    page_lengths if page_count else None,
                    root, root_id, 0xBAD)
    assert lib.vcs_file_object_build(ctypes.byref(request)) == OK
    assert request.result_pages == page_count
    return data, source, entries, pages, page_ids, page_lengths, root, root_id


def records_for(parts, pages, page_ids, page_lengths):
    page_count = len(page_lengths)
    page_records = (Record * max(1, page_count))()
    for index in range(page_count):
        page_records[index].object_id[:] = bytes(page_ids[index * 32:(index + 1) * 32])
        page_records[index].data = ctypes.cast(ctypes.byref(pages, index * PAGE_BYTES), P)
        page_records[index].length = page_lengths[index]
    chunk_records = (Record * max(1, len(parts)))()
    chunk_buffers = []
    for index, part in enumerate(parts):
        buf = array(part)
        chunk_buffers.append(buf)
        chunk_records[index].object_id[:] = oid(1, part)
        chunk_records[index].data = ctypes.cast(buf, P)
        chunk_records[index].length = len(part)
    return page_records, chunk_records, chunk_buffers


parts = [bytes(((index * 17 + pos * 29) & 0xFF) for pos in range(2048 + index % 97))
         for index in range(205)]
data, source, entries, pages, page_ids, page_lengths, root, root_id = build_file(parts)
assert bytes(root[:8]) == b"UVCSFIL1"
assert struct.unpack_from("<IIQQQ", bytes(root), 8) == (0o644, 0, len(data), 205, 3)
assert bytes(root[80:112]) == hashlib.sha256(b"UVCSBYT1" + struct.pack("<Q", len(data)) + data).digest()
assert bytes(root_id) == oid(2, bytes(root))

for index in range(3):
    count = min(PAGE_MAX, len(parts) - index * PAGE_MAX)
    length = 64 + count * 40
    page = bytes(pages[index * PAGE_BYTES:index * PAGE_BYTES + length])
    assert page[:8] == b"UVCSFPG1"
    assert struct.unpack_from("<II", page, 8) == (index, count)
    assert page_lengths[index] == length
    assert bytes(page_ids[index * 32:(index + 1) * 32]) == oid(9, page)
    expected_next = bytes(32) if index == 2 else bytes(page_ids[(index + 1) * 32:(index + 2) * 32])
    assert page[32:64] == expected_next

page_records, chunk_records, chunk_buffers = records_for(parts, pages, page_ids, page_lengths)
output = (ctypes.c_ubyte * len(data))(*([0xCC] * len(data)))
read = Read(root, root_id, page_records, 3, chunk_records, 205,
            output, len(output), 0xBAD)
assert lib.vcs_file_object_read(ctypes.byref(read)) == OK
assert read.result_length == len(data) and bytes(output) == data

# Missing/reordered resolved objects fail before output publication.
for mutate, expected in (("missing_page", NOT_FOUND), ("missing_chunk", NOT_FOUND),
                         ("reorder_page", NOT_FOUND)):
    page_records, chunk_records, chunk_buffers = records_for(parts, pages, page_ids, page_lengths)
    output[:] = bytes([0xCC]) * len(output)
    read = Read(root, root_id, page_records, 2 if mutate == "missing_page" else 3,
                chunk_records, 204 if mutate == "missing_chunk" else 205,
                output, len(output), 0xBAD)
    if mutate == "reorder_page":
        page_records[0], page_records[1] = page_records[1], page_records[0]
    assert lib.vcs_file_object_read(ctypes.byref(read)) == expected
    assert read.result_length == 0xBAD and bytes(output) == bytes([0xCC]) * len(output)

page_records, chunk_records, chunk_buffers = records_for(parts, pages, page_ids, page_lengths)
chunk_buffers[17][3] ^= 1
output[:] = bytes([0xCC]) * len(output)
read = Read(root, root_id, page_records, 3, chunk_records, 205,
            output, len(output), 0xBAD)
assert lib.vcs_file_object_read(ctypes.byref(read)) == CORRUPT
assert read.result_length == 0xBAD and bytes(output) == bytes([0xCC]) * len(output)

page_records, chunk_records, chunk_buffers = records_for(parts, pages, page_ids, page_lengths)
pages[64] ^= 1
output[:] = bytes([0xCC]) * len(output)
read = Read(root, root_id, page_records, 3, chunk_records, 205,
            output, len(output), 0xBAD)
assert lib.vcs_file_object_read(ctypes.byref(read)) == CORRUPT
assert read.result_length == 0xBAD and bytes(output) == bytes([0xCC]) * len(output)
pages[64] ^= 1

bad_root = (ctypes.c_ubyte * 128)(*bytes(root))
bad_root[80] ^= 1
bad_root_id = (ctypes.c_ubyte * 32)(*oid(2, bytes(bad_root)))
page_records, chunk_records, chunk_buffers = records_for(parts, pages, page_ids, page_lengths)
output[:] = bytes([0xCC]) * len(output)
read = Read(bad_root, bad_root_id, page_records, 3, chunk_records, 205,
            output, len(output), 0xBAD)
assert lib.vcs_file_object_read(ctypes.byref(read)) == CORRUPT
assert read.result_length == 0xBAD and bytes(output) == bytes([0xCC]) * len(output)

page_records, chunk_records, chunk_buffers = records_for(parts, pages, page_ids, page_lengths)
output[:] = bytes([0xCC]) * len(output)
read = Read(root, root_id, page_records, 3, chunk_records, 205,
            output, len(output) - 1, 0xBAD)
assert lib.vcs_file_object_read(ctypes.byref(read)) == NO_MEM
assert read.result_length == 0xBAD and bytes(output) == bytes([0xCC]) * len(output)

empty_data, _, _, empty_pages, empty_ids, empty_lengths, empty_root, empty_root_id = build_file([])
empty_read = Read(empty_root, empty_root_id, None, 0, None, 0, None, 0, 77)
assert lib.vcs_file_object_read(ctypes.byref(empty_read)) == OK
assert empty_read.result_length == 0

print("VCS file objects: PASS (paged descriptors, canonical IDs, reconstruction, missing/corrupt bounds)")
