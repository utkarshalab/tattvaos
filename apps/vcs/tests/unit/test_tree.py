"""Recursive Git tree planner and canonical encoder validation."""
import ctypes
import hashlib
import struct
import sys
import zlib

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
for name in ('tree_plan_probe', 'tree_hash_probe', 'tree_emit_probe',
             'tree_finish_probe', 'git_tree_file_parents', 'git_tree_sort_entries'):
    getattr(lib, name).restype = ctypes.c_uint64
value = ctypes.c_uint64.in_dll(lib, 'tree_probe_value')

manifest = (ctypes.c_ubyte * (256 + 3 * 256))()
ctypes.c_uint64.from_buffer(manifest, 24).value = 3
for index, path in enumerate((b'z.txt', b'src/b.asm', b'src/lib/a.asm')):
    manifest[256 + index * 256:256 + index * 256 + len(path) + 1] = path + b'\0'
plan = (ctypes.c_ubyte * (64 * 256))()
lib.tree_plan_probe.argtypes = [P, P, ctypes.c_uint64]
assert lib.tree_plan_probe(manifest, plan, 64) == 0 and value.value == 3
def q(offset): return ctypes.c_uint64.from_buffer(plan, offset).value
assert bytes(plan[256:260]) == b'src/' and q(256 + 240) == 1 and q(256 + 248) == 0
assert bytes(plan[512:520]) == b'src/lib/' and q(512 + 240) == 2 and q(512 + 248) == 1
parents = (ctypes.c_ubyte * 15)()
lib.git_tree_file_parents.argtypes = [P, P, ctypes.c_uint64, P]
assert lib.git_tree_file_parents(manifest, plan, 3, parents) == 0
assert list(parents[:3]) == [0, 1, 2]

class Entry(ctypes.Structure):
    _fields_ = [('name', P), ('hash', P), ('kind', ctypes.c_uint64)]
names = [(ctypes.c_ubyte * len(x))(*x) for x in (b'z\0', b'dir\0', b'a\0')]
hashes = [(ctypes.c_ubyte * 32)(*([x] * 32)) for x in (3, 2, 1)]
entries = (Entry * 3)(Entry(names[0], hashes[0], 0), Entry(names[1], hashes[1], 1), Entry(names[2], hashes[2], 0))
lib.git_tree_sort_entries.argtypes = [ctypes.POINTER(Entry), ctypes.c_uint64]
assert lib.git_tree_sort_entries(entries, 3) == 0
assert [ctypes.string_at(entry.name) for entry in entries] == [b'a', b'dir', b'z']
expected = (b'100644 a\0' + bytes([1]) * 32 + b'40000 dir\0' + bytes([2]) * 32
            + b'100644 z\0' + bytes([3]) * 32)
encoded = (ctypes.c_ubyte * 512)(); digest = (ctypes.c_ubyte * 32)()
lib.tree_hash_probe.argtypes = [ctypes.POINTER(Entry), ctypes.c_uint64, P, ctypes.c_uint64, P]
assert lib.tree_hash_probe(entries, 3, encoded, len(encoded), digest) == 0
assert value.value == len(expected) and bytes(encoded[:value.value]) == expected
assert bytes(digest) == hashlib.sha256(b'tree ' + str(len(expected)).encode() + b'\0' + expected).digest()

pack = (ctypes.c_ubyte * 4096)()
lib.git_pack_begin.argtypes = [P, ctypes.c_uint64, ctypes.c_uint32]
lib.tree_emit_probe.argtypes = [ctypes.POINTER(Entry), ctypes.c_uint64, P, ctypes.c_uint64, P]
assert lib.git_pack_begin(pack, len(pack), 1) == 0
assert lib.tree_emit_probe(entries, 3, encoded, len(encoded), digest) == 0
assert lib.tree_finish_probe() == 0
raw = bytes(pack[:value.value]); assert raw[:4] == b'PACK' and struct.unpack('>I', raw[8:12])[0] == 1
pos = 12; header = raw[pos]; pos += 1
size = header & 15; shift = 4
while header & 0x80:
    header = raw[pos]; pos += 1; size |= (header & 127) << shift; shift += 7
stream = zlib.decompressobj(); payload = stream.decompress(raw[pos:-32])
assert (raw[12] >> 4) & 7 == 2 and size == len(expected) and payload == expected and stream.eof
assert raw[-32:] == hashlib.sha256(raw[:-32]).digest()

assert lib.tree_plan_probe(None, plan, 64) == 8
assert lib.tree_plan_probe(manifest, plan, 0) == 8
bad = bytearray(len(manifest)); bad[24:32] = (1).to_bytes(8, 'little'); bad[256:260] = b'../x'
bad_manifest = (ctypes.c_ubyte * len(bad)).from_buffer_copy(bad)
assert lib.tree_plan_probe(bad_manifest, plan, 64) == 5
assert lib.tree_hash_probe(entries, 3, encoded, len(expected) - 1, digest) == 3
assert lib.tree_hash_probe(None, 3, encoded, len(encoded), digest) == 8

print('VCS tree: PASS (recursive plan, parents, canonical order, SHA-256, PACK, bounds)')
