"""Persistent native remote endpoint coverage over the real UXFS volume."""
import ctypes as C
import importlib.util
from pathlib import Path
import struct
import sys

root = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume', root/'lib/storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
lib = C.CDLL(str(Path(sys.argv[1]).resolve()))
lib.vcs_repo_init.argtypes = [C.c_char_p]
lib.vcs_remote.argtypes = [C.c_uint64, C.c_char_p, C.c_char_p, C.c_char_p, C.c_void_p]
lib.remote_resolve_probe.argtypes = [C.c_char_p]
for name in ('vcs_repo_init', 'vcs_remote', 'remote_resolve_probe'):
    getattr(lib, name).restype = C.c_uint64

IO = C.CFUNCTYPE(C.c_int64, C.c_uint64, C.c_uint64, C.c_void_p)
Flush = C.CFUNCTYPE(C.c_int64)
Writer = C.CFUNCTYPE(C.c_uint64, C.c_void_p, C.c_uint64)
disk = bytearray(fmt.image())
fail_write = False

@IO
def read(lba, count, buf):
    data = bytes(disk[lba*512:(lba+count)*512])
    if len(data) != count*512:
        return -5
    C.memmove(buf, data, len(data))
    return 0

@IO
def write(lba, count, buf):
    if fail_write:
        return -5
    data = C.string_at(buf, count*512)
    disk[lba*512:(lba+count)*512] = data
    return 0

@Flush
def flush():
    return 0

for name, cb in [('uxv_read', read), ('uxv_write', write), ('uxv_flush', flush)]:
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value

nodes = (C.c_ubyte * (fmt.NODES * fmt.NODE)).in_dll(lib, 'uxv_nodes')
ip = C.c_uint32.in_dll(lib, 'probe_ip')
port = C.c_uint32.in_dll(lib, 'probe_port')
listed = bytearray()

@Writer
def writer(data, size):
    listed.extend(C.string_at(data, size))
    return 0

def fresh():
    global fail_write
    fail_write = False
    disk[:] = fmt.image()
    assert lib.uxv_mount() == 0
    assert lib.vcs_repo_init(b'/') == 0

def find_path(path):
    lib.uxv_find.argtypes = [C.c_char_p]
    lib.uxv_find.restype = C.c_void_p
    return lib.uxv_find(path)

fresh()
assert lib.vcs_remote(1, b'origin', b'127.0.0.1', b'9418', None) == 0
assert lib.remote_resolve_probe(b'origin') == 0
assert ip.value == 0x0100007f and port.value == 9418
assert lib.vcs_remote(1, b'origin', b'10.0.0.1', b'1', None) == 6
listed.clear()
assert lib.vcs_remote(0, None, None, None, C.cast(writer, C.c_void_p)) == 0
assert listed == b'origin 127.0.0.1:9418\n'
assert lib.uxv_mount() == 0 and lib.remote_resolve_probe(b'origin') == 0
assert ip.value == 0x0100007f and port.value == 9418

for name in (b'', b'.hidden', b'bad/name', b'x'*33):
    assert lib.vcs_remote(1, name, b'1.2.3.4', b'1', None) == 8
for address in (b'', b'1.2.3', b'1.2.3.256', b'1.2.3.4x', b'01..2.3'):
    assert lib.vcs_remote(1, b'badip', address, b'1', None) == 8
for service in (b'', b'0', b'65536', b'-1', b'80x'):
    assert lib.vcs_remote(1, b'badport', b'1.2.3.4', service, None) == 8
assert lib.vcs_remote(0, None, None, None, None) == 8
assert lib.vcs_remote(4, None, None, None, None) == 8

node = find_path(b'/.vcs/remote.origin')
assert node
C.c_uint64.from_address(node + 248).value = 15
assert lib.remote_resolve_probe(b'origin') == 5
C.c_uint64.from_address(node + 248).value = 16
assert lib.vcs_remote(2, b'origin', None, None, None) == 0
assert lib.remote_resolve_probe(b'origin') == 2
assert lib.vcs_remote(2, b'origin', None, None, None) == 2

fresh()
for index in range(3, fmt.NODES):
    base = index * fmt.NODE
    nodes[base:base+4] = b'full'
    C.c_uint64.from_buffer(nodes, base + 240).value = 1
assert lib.uxv_commit() == 0
assert lib.vcs_remote(1, b'full', b'1.2.3.4', b'80', None) == 3

fresh()
fail_write = True
assert lib.vcs_remote(1, b'broken', b'1.2.3.4', b'80', None) == 4

print('VCS remote: PASS (persist, resolve, list, bounds, corruption, capacity, I/O)')
