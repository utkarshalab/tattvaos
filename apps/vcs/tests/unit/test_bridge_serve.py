"""Top-level Git protocol-v2 bridge orchestration validation."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bridge_serve_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, P, ctypes.c_uint64, ctypes.c_uint64]
lib.bridge_serve_probe.restype = ctypes.c_uint64
lib.bridge_git_serve_terminal.restype = ctypes.c_uint64
def q(name): return ctypes.c_uint64.in_dll(lib, name)
operation, wanted, flags, parse_status, common, shallow_count, shallow_oid, haves_count = [q(name) for name in (
    'mock_operation', 'mock_wanted', 'mock_flags', 'mock_parse_status',
    'mock_common_index', 'mock_shallow_count', 'mock_shallow_oid', 'mock_haves_count')]
pack_calls, seen_flags, seen_cut, unshallow = [q(name) for name in (
    'mock_pack_cut', 'mock_seen_flags', 'mock_seen_cut', 'mock_unshallow')]
calls = (ctypes.c_uint64 * 8).in_dll(lib, 'mock_calls')
request = (ctypes.c_ubyte * 4)(*b'req\n'); response = (ctypes.c_ubyte * 128)()
oid = (ctypes.c_ubyte * 32)(*([0xaa] * 32)); shallow = (ctypes.c_ubyte * 32)(*([0xbb] * 32))

def reset(op=0, request_flags=0):
    for control in (operation, wanted, flags, parse_status, shallow_count, shallow_oid, haves_count,
                    pack_calls, seen_flags, seen_cut, unshallow): control.value = 0
    common.value = 0xffffffffffffffff; operation.value = op; flags.value = request_flags
    ctypes.memset(calls, 0, ctypes.sizeof(calls)); ctypes.memset(response, 0, len(response))
def serve(): return lib.bridge_serve_probe(1, request, len(request), response, len(response), 7)

reset(); assert lib.bridge_serve_probe(0, None, 0, response, len(response), 0) == 0
assert response[0] == ord('V') and lib.bridge_git_serve_terminal() == 0

reset(1, 3); assert serve() == 0
assert response[0] == ord('R') and calls[1] == calls[2] == 1 and lib.bridge_git_serve_terminal() == 0

reset(3, 2); wanted.value = ctypes.addressof(oid); assert serve() == 0
assert response[0] == ord('I') and calls[3] == calls[4] == 1 and lib.bridge_git_serve_terminal() == 0

reset(2); common.value = 1; haves_count.value = 1
assert serve() == 0 and response[0] == ord('F') and pack_calls.value == 1
assert seen_cut.value == 1 and calls[6] == 1 and lib.bridge_git_serve_terminal() == 1

reset(2, 8192); common.value = 0xffffffffffffffff
assert serve() == 0 and response[0] == ord('A') and calls[7] == 1
assert pack_calls.value == 0 and lib.bridge_git_serve_terminal() == 0

reset(2, 1024 | (2 << 16)); shallow_count.value = 1; shallow_oid.value = ctypes.addressof(shallow); common.value = 1
assert serve() == 0 and pack_calls.value == 1 and seen_cut.value == 0xffffffffffffffff
assert (seen_flags.value >> 16) & 255 == 4 and unshallow.value == ctypes.addressof(shallow)

reset(2); wanted.value = ctypes.addressof(shallow); assert serve() == 2
reset(2); parse_status.value = 5; assert serve() == 5
reset(); assert lib.bridge_serve_probe(1, None, 1, response, len(response), 7) == 8

print('VCS bridge serve: PASS (advertise, refs, object-info, fetch, negotiate, shallow, errors)')
