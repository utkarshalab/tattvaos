"""Git SHA-256 object hashing and PACK v2 executable validation."""
import ctypes
import hashlib
import struct
import sys
import zlib

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.git_object_hash.argtypes = [ctypes.c_char_p, ctypes.c_uint64, P, ctypes.c_uint64, P]
lib.git_pack_begin.argtypes = [P, ctypes.c_uint64, ctypes.c_uint32]
lib.git_pack_begin_unique.argtypes = [P, ctypes.c_uint64, ctypes.c_uint32]
lib.git_pack_add.argtypes = [ctypes.c_uint32, P, ctypes.c_uint64]
for name in ('git_object_hash', 'git_pack_begin', 'git_pack_begin_unique',
             'git_pack_add', 'pack_finish_probe'):
    getattr(lib, name).restype = ctypes.c_uint64
length = ctypes.c_uint64.in_dll(lib, 'probe_length')

def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)

def parse_pack(raw):
    assert raw[:4] == b'PACK' and struct.unpack('>I', raw[4:8])[0] == 2
    count = struct.unpack('>I', raw[8:12])[0]
    pos, objects = 12, []
    for _ in range(count):
        byte = raw[pos]; pos += 1
        kind, size, shift = (byte >> 4) & 7, byte & 15, 4
        while byte & 0x80:
            byte = raw[pos]; pos += 1
            size |= (byte & 0x7f) << shift; shift += 7
        stream = zlib.decompressobj()
        data = stream.decompress(raw[pos:-32])
        assert stream.eof and len(data) == size
        used = len(raw[pos:-32]) - len(stream.unused_data)
        pos += used
        objects.append((kind, data))
    assert pos == len(raw) - 32
    assert raw[-32:] == hashlib.sha256(raw[:-32]).digest()
    return objects

blob = array(b'abc'); digest = (ctypes.c_ubyte * 32)()
assert lib.git_object_hash(b'blob', 4, blob, 3, digest) == 0
assert bytes(digest) == hashlib.sha256(b'blob 3\0abc').digest()
assert lib.git_object_hash(None, 4, blob, 3, digest) == 8

output = (ctypes.c_ubyte * 4096)()
assert lib.git_pack_begin(output, len(output), 3) == 0
for kind, data in ((3, b'abc'), (2, b'100644 a\0' + bytes(32)), (1, b'tree x\n\nmsg\n')):
    value = array(data)
    assert lib.git_pack_add(kind, value, len(data)) == 0
assert lib.pack_finish_probe() == 0
raw = bytes(output[:length.value])
assert parse_pack(raw) == [(3, b'abc'), (2, b'100644 a\0' + bytes(32)), (1, b'tree x\n\nmsg\n')]

assert lib.git_pack_begin_unique(output, len(output), 2) == 0
assert lib.git_pack_add(3, blob, 3) == 0
assert lib.git_pack_add(3, blob, 3) == 0
assert lib.pack_finish_probe() == 0
raw = bytes(output[:length.value])
assert struct.unpack('>I', raw[8:12])[0] == 1 and parse_pack(raw) == [(3, b'abc')]

assert lib.git_pack_begin(output, len(output), 2) == 0
assert lib.git_pack_add(3, blob, 3) == 0
assert lib.pack_finish_probe() == 8
assert lib.git_pack_begin(None, len(output), 1) == 8
assert lib.git_pack_begin(output, 43, 1) == 3
assert lib.git_pack_begin_unique(output, len(output), 4097) == 3
assert lib.git_pack_begin(output, 44, 1) == 0
assert lib.git_pack_add(3, blob, 3) == 0
assert lib.pack_finish_probe() == 3
assert lib.git_pack_begin(output, len(output), 1) == 0
assert lib.git_pack_add(0, blob, 3) == 8
assert lib.git_pack_add(3, None, 3) == 8

print('VCS pack: PASS (object hash, PACK v2, zlib, Adler, trailer, unique, bounds)')
