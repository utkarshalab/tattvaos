"""Snapshot-to-Git object graph and PACK orchestration coverage."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.snapshot_pack_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, P]
lib.snapshot_pack_probe.restype = ctypes.c_uint64

def q(name):
    return ctypes.c_uint64.in_dll(lib, name)

controls = {name: q(name) for name in ('mock_load_status mock_tree_status '
    'mock_pack_status mock_finish_status mock_begin_objects mock_add_calls').split()}
manifest = (ctypes.c_ubyte * 512).in_dll(lib, 'mock_manifest')
node = (ctypes.c_ubyte * 4352).in_dll(lib, 'mock_blob_node')
types = (ctypes.c_uint64 * 8).in_dll(lib, 'mock_add_types')
out = (ctypes.c_ubyte * 1024)()
oid = (ctypes.c_ubyte * 32)()

def put64(buf, offset, value):
    ctypes.c_uint64.from_buffer(buf, offset).value = value

def setup():
    for value in controls.values(): value.value = 0
    ctypes.memset(manifest, 0, len(manifest))
    ctypes.memset(node, 0, len(node))
    put64(manifest, 24, 1)
    put64(manifest, 32, 3)
    manifest[40:44] = b'msg\0'
    manifest[256:262] = b'a.asm\0'
    put64(manifest, 496, 7)
    put64(manifest, 504, 3)
    put64(node, 240, 1)
    put64(node, 248, 3)
    node[256:259] = b'abc'

setup()
result = lib.snapshot_pack_probe(1, out, len(out), oid)
assert result == 0, result
assert controls['mock_begin_objects'].value == 3
assert controls['mock_add_calls'].value == 2 and list(types[:2]) == [3, 1]
assert bytes(oid) == bytes([0x33]) * 32

setup(); controls['mock_tree_status'].value = 5
assert lib.snapshot_pack_probe(1, out, len(out), oid) == 5
setup(); controls['mock_pack_status'].value = 3
assert lib.snapshot_pack_probe(1, out, len(out), oid) == 3
setup(); controls['mock_finish_status'].value = 4
assert lib.snapshot_pack_probe(1, out, len(out), oid) == 4
setup(); controls['mock_load_status'].value = 1
assert lib.snapshot_pack_probe(1, out, len(out), oid) == 5
setup(); put64(node, 248, 2)
assert lib.snapshot_pack_probe(1, out, len(out), oid) == 5
assert lib.snapshot_pack_probe(0, out, len(out), oid) == 8
assert lib.snapshot_pack_probe(1, None, len(out), oid) == 8
assert lib.snapshot_pack_probe(1, out, len(out), None) == 8

print('VCS upload pack: PASS (blob/tree/commit orchestration, OID, failures, bounds)')
