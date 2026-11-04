"""Repository negotiation policy coverage with a deterministic plan probe."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
byte_pointer = ctypes.POINTER(ctypes.c_ubyte)
result_type = ctypes.c_uint64 * 4
lib.policy_call_probe.argtypes = [ctypes.c_uint32, byte_pointer,
                                  ctypes.c_char_p, ctypes.c_uint64,
                                  ctypes.POINTER(ctypes.c_uint64)]

status_control = ctypes.c_uint64.in_dll(lib, 'policy_test_status')
count_control = ctypes.c_uint64.in_dll(lib, 'policy_test_count')
calls = ctypes.c_uint64.in_dll(lib, 'policy_test_calls')
seen_digest = ctypes.c_uint64.in_dll(lib, 'policy_test_digest')
seen_ref = ctypes.c_uint64.in_dll(lib, 'policy_test_ref')
seen_capacity = ctypes.c_uint64.in_dll(lib, 'policy_test_capacity')
head = (ctypes.c_ubyte * 32).in_dll(lib, 'policy_test_head')
ids = (ctypes.c_uint64 * 64).in_dll(lib, 'vcs_sync_policy_ids')

def configure(status=0, count=3):
    status_control.value = status
    count_control.value = count
    calls.value = 0
    for index in range(32):
        head[index] = 0x80 + index

def invoke(operation, digest, ref=None, incoming=0):
    result = result_type()
    lib.policy_call_probe(operation, digest, ref, incoming, result)
    return tuple(result)

zero = (ctypes.c_ubyte * 32)()
peer = (ctypes.c_ubyte * 32)(*range(1, 33))
head_address = ctypes.addressof(head)

configure()
result = invoke(1, peer, b'main')
assert result == (0, head_address, 3, 3)
assert calls.value == 1 and seen_capacity.value == 64
assert seen_digest.value == ctypes.addressof(peer) and seen_ref.value != 0
assert list(ids[:3]) == [1, 2, 3]

configure(count=2)
assert invoke(3, zero) == (0, head_address, 2, 2)
assert calls.value == 1
configure()
assert invoke(3, peer) == (6, 0, 0, 0)
assert calls.value == 0

configure()
assert invoke(4, peer) == (9, 0, 0, 0)
assert calls.value == 0

configure(count=7)
assert invoke(2, peer, b'ignored', 0) == (0, head_address, 0, 0)
assert calls.value == 1 and seen_digest.value == 0 and seen_ref.value == 0
configure(count=7)
assert invoke(2, peer, None, 5) == (0, head_address, 0, 5)
assert calls.value == 1 and seen_digest.value == 0 and seen_ref.value == 0
configure()
oversized = invoke(2, peer, None, 65)
assert oversized[0] == 8 and oversized[3] == 0
assert calls.value == 0

configure(status=5, count=9)
assert invoke(1, peer) == (5, 9, 64, 0)
assert calls.value == 1
configure(status=5, count=9)
failed_push = invoke(2, peer, None, 4)
assert failed_push[0] == 5 and failed_push[3] == 0
assert calls.value == 1

print('VCS policy: PASS (fetch, clone, push rounds, limits, failures, plan state)')
