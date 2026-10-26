"""Pending validation suite: native history with real UXFS and injected I/O."""
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
IO = C.CFUNCTYPE(C.c_int64,C.c_uint64,C.c_uint64,C.c_void_p)
Flush = C.CFUNCTYPE(C.c_int64)
Writer = C.CFUNCTYPE(None,C.c_void_p,C.c_uint64)
disk = bytearray(fmt.image())
failure = None
flush_count = 0
output = bytearray()
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
@Writer
def emit(buf,size): output.extend(C.string_at(buf,size))
for name,cb in [('uxv_read',read),('uxv_write',write),('uxv_flush',flush)]:
    C.c_void_p.in_dll(lib,name).value = C.cast(cb,C.c_void_p).value
lib.vcs_history.argtypes = [C.c_uint64,C.c_char_p,Writer]
lib.vcs_history.restype = C.c_uint64
lib.vcs_repo_init.argtypes = [C.c_char_p]
lib.uxv_find.argtypes = [C.c_char_p]
lib.uxv_find.restype = C.c_void_p
nodes = (C.c_ubyte*(fmt.NODE*fmt.NODES)).in_dll(lib,'uxv_nodes')
ready = C.c_uint64.in_dll(lib,'uxv_ready')
def command(kind,message=None,status=0):
    output.clear()
    before = bytes(disk)
    result = lib.vcs_history(kind,message,emit)
    assert result == status,(kind,result,status,bytes(output))
    if kind != 1: assert bytes(disk) == before
    return bytes(output)
def put(path,data):
    address = lib.uxv_find(path)
    if not address:
        address = next(C.addressof(nodes)+i*fmt.NODE for i in range(1,fmt.NODES)
                       if struct.unpack_from('<Q',bytes(nodes),i*fmt.NODE+240)[0] == 0)
    node = bytearray(fmt.NODE)
    node[:len(path)+1] = path+b'\0'
    struct.pack_into('<QQ',node,240,1,len(data))
    node[256:256+len(data)] = data
    C.memmove(address,bytes(node),fmt.NODE)
    assert lib.uxv_commit() == 0

def head():
    return struct.unpack('<Q',C.string_at(lib.uxv_find(b'/.vcs/format')+280,8))[0]
assert lib.uxv_mount() == 0
command(0,status=2)
assert lib.vcs_repo_init(b'/') == 0
assert command(0) == b'No commits yet\n'
put(b'/a',b'first\n')
assert command(0) == b'No commits yet\nA a\n'
assert command(1,b'first') == b'Committed 0000000000000001\n'
assert head() == 1
assert lib.uxv_mount() == 0
assert command(0) == b'Working tree clean\n'
before = bytes(disk)
assert command(1,b'unchanged') == b'Nothing to commit\n'
assert bytes(disk) == before
assert lib.vcs_repo_init(b'/') == 0 and bytes(disk) == before
put(b'/b',b'second')
command(1,b'add b')
manifest = lib.uxv_find(b'/.vcs/c0000000000000002')+256
assert struct.unpack('<Q',C.string_at(manifest+256+240,8))[0] == 0x101
assert command(3) == b'commit 0000000000000002 add b\ncommit 0000000000000001 first\n'
assert command(2) == (b'commit 0000000000000002\n    add b\n\n'
                      b'commit 0000000000000001\n    first\n\n')
assert command(4,C.c_char_p(2)) == (b'commit 0000000000000002\n    add b\nfiles:\n'
                                       b'  6 a\n  6 b\n')
put(b'/a',b'changed')
C.memset(lib.uxv_find(b'/b'),0,fmt.NODE)
assert lib.uxv_commit() == 0
assert command(0) == b'M a\nD b\n'
command(1,b'change and delete')
assert command(0) == b'Working tree clean\n'
command(1,b'',status=8)
command(1,b'x'*216,status=8)
put(b'/a',b'next\x00')
baseline = bytes(disk)
for failure in [('body',0),('body',8192),('header',0),('header',511),('flush',1),('flush',2)]:
    disk[:] = baseline
    assert lib.uxv_mount() == 0
    flush_count = 0
    command(1,b'fourth',status=4)
    assert ready.value == 0
    assert lib.uxv_mount() == 0
    assert head() in (3,4)
    command(2)
    assert command(0) == (b'Working tree clean\n' if head() == 4 else b'M a\n')
failure = None
disk[:] = baseline
assert lib.uxv_mount() == 0
blob = lib.uxv_find(b'/.vcs/b0000000000000301')
assert blob
C.memset(blob,0,fmt.NODE)
assert lib.uxv_commit() == 0
assert command(0,status=5) == b''
assert command(1,b'bad',status=5) == b''
assert command(2,status=5) == b''
print('VCS history: PASS (snapshots, reuse, status, parent log, no-op, corruption and transaction recovery)')
