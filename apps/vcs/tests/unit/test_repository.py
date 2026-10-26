"""Actual NASM repository + UXFS, with block I/O failure injection."""
import ctypes as C
import importlib.util
from pathlib import Path
import struct
import sys

root = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume',root/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
lib = C.CDLL(str(Path(sys.argv[1]).resolve()))
lib.vcs_repo_init.argtypes = [C.c_char_p]
lib.vcs_repo_init.restype = C.c_uint64
lib.uxv_find.argtypes = [C.c_char_p]
lib.uxv_find.restype = C.c_void_p
IO = C.CFUNCTYPE(C.c_int64,C.c_uint64,C.c_uint64,C.c_void_p)
Flush = C.CFUNCTYPE(C.c_int64)
disk = bytearray(fmt.image())
failure = None
flush_count = 0
@IO
def read(lba,count,buf):
    data = bytes(disk[lba*512:(lba+count)*512])
    if len(data) != count*512: return -5
    C.memmove(buf,data,len(data)); return 0
@IO
def write(lba,count,buf):
    data = C.string_at(buf,count*512)
    if failure and failure[0] == ('body' if count > 1 else 'header'):
        data = data[:failure[1]]
        disk[lba*512:lba*512+len(data)] = data
        return -5
    disk[lba*512:(lba+count)*512] = data
    return 0
@Flush
def flush():
    global flush_count
    flush_count += 1
    return -5 if failure == ('flush',flush_count) else 0
for name,cb in [('uxv_read',read),('uxv_write',write),('uxv_flush',flush)]:
    C.c_void_p.in_dll(lib,name).value = C.cast(cb,C.c_void_p).value
nodes = (C.c_ubyte*(fmt.NODES*fmt.NODE)).in_dll(lib,'uxv_nodes')
ready = C.c_uint64.in_dll(lib,'uxv_ready')
header = b'UVCSREP1'+struct.pack('<QQQ',2,0,0)
def mount_fresh():
    disk[:] = fmt.image()
    assert lib.uxv_mount() == 0
def node(index,path,kind,data=b''):
    raw = bytearray(fmt.NODE)
    raw[:len(path)+1] = path+b'\0'
    struct.pack_into('<QQ',raw,240,kind,len(data))
    raw[256:256+len(data)] = data
    C.memmove(C.addressof(nodes)+index*fmt.NODE,bytes(raw),fmt.NODE)
mount_fresh()
assert lib.vcs_repo_init(b'/') == 0
assert lib.uxv_mount() == 0
p = lib.uxv_find(b'/.vcs/format')
assert p and C.string_at(p+256,32) == header
before = bytes(disk)
assert lib.vcs_repo_init(b'.') == 0 and bytes(disk) == before
for path in [None,b'/absent',b'/.vcs/format',b'/' + b'x'*240]:
    assert lib.vcs_repo_init(path) != 0 and bytes(disk) == before
for count in [62,63]:
    mount_fresh()
    for i in range(1,count+1): node(i,f'/f{i}'.encode(),1)
    assert lib.uxv_commit() == 0
    before, memory = bytes(disk),bytes(nodes)
    assert lib.vcs_repo_init(b'/') == 3
    assert bytes(disk) == before and bytes(nodes) == memory
for kind,data in [(1,b''),(2,b'')]:
    mount_fresh(); node(1,b'/.vcs',kind)
    assert lib.uxv_commit() == 0
    before = bytes(disk)
    assert lib.vcs_repo_init(b'/') == 6 and bytes(disk) == before
for bad in [b'',header[:-1],b'bad'+header[3:],header[:8]+struct.pack('<Q',3)+header[16:]]:
    mount_fresh(); node(1,b'/.vcs',2); node(2,b'/.vcs/format',1,bad)
    assert lib.uxv_commit() == 0
    before = bytes(disk)
    assert lib.vcs_repo_init(b'/') == 6 and bytes(disk) == before
for length in [227,228]:
    mount_fresh(); path = b'/'+b'x'*(length-1); node(1,path,2)
    assert lib.uxv_commit() == 0
    before = bytes(disk)
    assert lib.vcs_repo_init(path) == (0 if length == 227 else 8)
    assert lib.uxv_mount() == 0
    if length == 228: assert bytes(disk) == before
for failure in [('body',0),('body',8192),('body',fmt.NODES*fmt.NODE-1),
                ('header',0),('header',24),('header',511),('flush',1),('flush',2)]:
    mount_fresh(); flush_count = 0
    assert lib.vcs_repo_init(b'/') == 4 and ready.value == 0
    assert lib.uxv_mount() == 0
    directory = lib.uxv_find(b'/.vcs')
    metadata = lib.uxv_find(b'/.vcs/format')
    assert bool(directory) == bool(metadata),failure
    if metadata: assert C.string_at(metadata+256,32) == header
failure = None
ready.value = 0
assert lib.vcs_repo_init(b'/') == 4
print('VCS repository: PASS (format, remount, idempotence, conflicts, capacity, path bounds, torn-write/flush recovery)')
