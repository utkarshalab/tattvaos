"""First-parent synchronization planner executable coverage."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
Q = ctypes.POINTER(ctypes.c_uint64)
lib.plan_probe.argtypes = [P, ctypes.c_char_p, Q, ctypes.c_uint64]
lib.plan_probe.restype = ctypes.c_uint64
lib.plan_probe_reset.restype = ctypes.c_uint64

def q(name):
    return ctypes.c_uint64.in_dll(lib, name)

status, count, target = (q(n) for n in ('probe_status', 'probe_count', 'probe_target'))
digest_ptr = q('probe_digest')
ready, head = q('uxv_ready'), q('vcs_repo_head')
discover, ref_status, ref_target = (q(n) for n in
    ('mock_discover_status', 'mock_ref_status', 'mock_ref_target'))
map_mask = q('mock_map_mask')
manifests = (ctypes.c_ubyte * 768).in_dll(lib, 'mock_manifests')
hash_nodes = (ctypes.c_ubyte * (3 * 4352)).in_dll(lib, 'mock_hash_nodes')
map_nodes = (ctypes.c_ubyte * (3 * 4352)).in_dll(lib, 'mock_map_nodes')
out = (ctypes.c_uint64 * 64)()

def put64(buf, offset, value):
    ctypes.c_uint64.from_buffer(buf, offset).value = value

def setup():
    lib.plan_probe_reset()
    for i, parent in enumerate((0, 1, 2)):
        put64(manifests, i * 256 + 16, parent)
        base = i * 4352
        put64(hash_nodes, base + 240, 1)
        put64(hash_nodes, base + 248, 32)
        hash_nodes[base + 256:base + 288] = bytes([i + 1]) * 32
        put64(map_nodes, base + 240, 1)
        put64(map_nodes, base + 248, 48)
        put64(map_nodes, base + 256, 0x3150414d53435655)
        map_nodes[base + 272:base + 304] = bytes([0xa1 + i]) * 32

def run(have=None, ref=None, capacity=64, output=out):
    hp = None if have is None else ctypes.cast(have, P)
    op = None if output is None else output
    result = lib.plan_probe(hp, ref, op, capacity)
    advertised = bytes((ctypes.c_ubyte * 32).from_address(digest_ptr.value)) if status.value == 0 else b''
    return result, list(out[:count.value]) if status.value == 0 else [], advertised

setup()
r, ids, advertised = run()
assert r == 0 and ids == [1, 2, 3] and target.value == 3
assert advertised == bytes([3]) * 32
have = (ctypes.c_ubyte * 32)(*([1] * 32))
r, ids, _ = run(have)
assert r == 0 and ids == [2, 3]

map_mask.value = 0b110
source_two = (ctypes.c_ubyte * 32)(*([0xa2] * 32))
r, ids, advertised = run(source_two)
assert r == 0 and ids == [3] and advertised == bytes([0xa3]) * 32
r, ids, advertised = run(ref=b'refs/heads/old')
assert r == 0 and ids == [1, 2] and target.value == 2
assert advertised == bytes([0xa2]) * 32

setup(); head.value = 0
r, ids, advertised = run()
assert r == 0 and ids == [] and target.value == 0 and advertised == bytes(32)
assert run(have)[0] == 2

setup()
missing = (ctypes.c_ubyte * 32)(*([9] * 32))
assert run(missing)[0] == 2
assert run(capacity=2)[0] == 3
ready.value = 0
assert run()[0] == 4
ready.value = 1
put64(hash_nodes, 2 * 4352 + 248, 31)
assert run()[0] == 5
setup(); ref_status.value = 2
assert run(ref=b'missing')[0] == 2
assert run(output=None)[0] == 8
assert run(capacity=0)[0] == 8
assert run(capacity=65)[0] == 8

print('VCS plan: PASS (ancestry, maps, refs, divergence, capacity, corruption)')
