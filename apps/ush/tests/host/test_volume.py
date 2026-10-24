#!/usr/bin/env python3
"""Inject torn writes/flush failures into the actual NASM volume implementation."""
import ctypes as C
import importlib.util
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume', ROOT/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
lib = C.CDLL(str(Path(sys.argv[1]).resolve()))
IO = C.CFUNCTYPE(C.c_int64, C.c_uint64, C.c_uint64, C.c_void_p)
FLUSH = C.CFUNCTYPE(C.c_int64)
disk = bytearray(fmt.image())
failure = None
flush_count = 0

@IO
def read(lba, count, buf):
    data = bytes(disk[lba*512:(lba+count)*512])
    if len(data) != count*512:
        return -5
    C.memmove(buf, data, len(data))
    return 0

@IO
def write(lba, count, buf):
    data = C.string_at(buf, count*512)
    if failure and failure[0] == ('body' if count > 1 else 'header'):
        data = data[:failure[1]]
        disk[lba*512:lba*512+len(data)] = data
        return -5
    disk[lba*512:(lba+count)*512] = data
    return 0

@FLUSH
def flush():
    global flush_count
    flush_count += 1
    return -5 if failure == ('flush', flush_count) else 0

for name, callback in [('uxv_read', read), ('uxv_write', write), ('uxv_flush', flush)]:
    C.c_void_p.in_dll(lib, name).value = C.cast(callback, C.c_void_p).value
nodes = (C.c_ubyte * (fmt.NODES*fmt.NODE)).in_dll(lib, 'uxv_nodes')
ready = C.c_uint64.in_dll(lib, 'uxv_ready')

def set_file(text):
    node = bytearray(fmt.NODE)
    node[:3] = b'/f\0'
    struct.pack_into('<QQ', node, 240, 1, len(text))
    node[256:256+len(text)] = text
    C.memmove(C.addressof(nodes)+fmt.NODE, bytes(node), len(node))

assert lib.uxv_mount() == 0
set_file(b'old')
assert lib.uxv_commit() == 0
baseline = bytes(disk)
for failure in [('body', 0), ('body', 8192), ('body', fmt.NODES*fmt.NODE-1),
                ('header', 0), ('header', 24), ('header', 40),
                ('header', 511), ('flush', 1), ('flush', 2)]:
    disk[:] = baseline
    assert lib.uxv_mount() == 0
    set_file(b'new')
    flush_count = 0
    assert lib.uxv_commit() != 0 and ready.value == 0, failure
    assert lib.uxv_mount() == 0, failure
    restored = bytes(nodes)[fmt.NODE+256:fmt.NODE+259]
    # A reported final-flush/header failure may already have committed. Never
    # claim rollback in that case, but recovery must yield a complete snapshot.
    assert restored in (b'old', b'new'), (failure, restored)

failure = None
# Even checksummed metadata must pass namespace validation.
for name, kind, size in [(b'/../bad', 1, 0), (b'/missing/child', 1, 0),
                          (b'/a//b', 1, 0), (b'/', 2, 0),
                          (b'/bad', 7, 0), (b'/bad', 1, 4097),
                          (b'/bad', 2, 1)]:
    disk[:] = fmt.image()
    node = bytearray(fmt.NODE)
    node[:len(name)+1] = name+b'\0'
    struct.pack_into('<QQ', node, 240, kind, size)
    disk[512+fmt.NODE:512+2*fmt.NODE] = node
    struct.pack_into('<Q', disk, 24, fmt.checksum(disk[512:fmt.BANK*512]))
    struct.pack_into('<Q', disk, 32, 0)
    struct.pack_into('<Q', disk, 32, fmt.checksum(disk[:512]))
    assert lib.uxv_mount() != 0, name
print('UXFS NASM torn-write/flush recovery and metadata validation: PASS')
