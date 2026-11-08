"""Bounded first-parent history planner validation."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_uint64)
lib.history_plan_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64]
lib.history_plan_probe.restype = ctypes.c_uint64
count = ctypes.c_uint64.in_dll(lib, 'history_probe_count')
mock_count = ctypes.c_uint64.in_dll(lib, 'mock_history_count')
manifests = (ctypes.c_ubyte * (8 * 256)).in_dll(lib, 'mock_history_manifests')
output = (ctypes.c_uint64 * 8)(*[0xfeed] * 8)

def setup(parents):
    ctypes.memset(manifests, 0, len(manifests))
    mock_count.value = len(parents)
    for index, parent in enumerate(parents):
        ctypes.c_uint64.from_buffer(manifests, index * 256 + 16).value = parent

setup((0, 1, 2, 3))
assert lib.history_plan_probe(4, output, 4) == 0
assert count.value == 4 and list(output[:4]) == [4, 3, 2, 1]

setup((0, 1, 2, 3))
output[:] = [0xfeed] * 8
assert lib.history_plan_probe(3, output, 8) == 0
assert count.value == 3 and list(output[:3]) == [3, 2, 1]

setup((0, 1, 2, 3))
assert lib.history_plan_probe(4, output, 3) == 3
assert list(output[:3]) == [4, 3, 2]
setup((0, 1, 9))
assert lib.history_plan_probe(3, output, 8) == 5
setup((0, 2))
assert lib.history_plan_probe(2, output, 4) == 3

setup((0,))
assert lib.history_plan_probe(0, output, 8) == 8
assert lib.history_plan_probe(1, None, 8) == 8
assert lib.history_plan_probe(1, output, 0) == 8

print('VCS history plan: PASS (first-parent order, subchains, capacity, corruption, cycles)')
