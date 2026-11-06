"""Contiguous signed bundle frame validation through the native ABI."""
import ctypes
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bundle_seal_probe.argtypes = [P, ctypes.c_uint64, P, ctypes.c_uint64,
                                  ctypes.c_uint32, P]
lib.bundle_open_probe.argtypes = [P, ctypes.c_uint64]
lib.bundle_seal_probe.restype = ctypes.c_uint64
lib.bundle_open_probe.restype = ctypes.c_uint64

status = ctypes.c_uint64.in_dll(lib, 'probe_status')
pointer = ctypes.c_uint64.in_dll(lib, 'probe_pointer')
length = ctypes.c_uint64.in_dll(lib, 'probe_length')
operation = ctypes.c_uint64.in_dll(lib, 'probe_operation')
trust = ctypes.c_uint64.in_dll(lib, 'mock_trust_status')
verify = ctypes.c_uint64.in_dll(lib, 'mock_verify_status')

HEADER, PAYLOAD = 168, 432
NO_MEM, CORRUPT, PERM, USAGE = 3, 5, 7, 8
payload = (ctypes.c_ubyte * PAYLOAD)()
struct.pack_into('<QQQQQ', payload, 0, 0x31444e4253435655, 1, PAYLOAD, 2, 1)
struct.pack_into('<QQQ', payload, 96, 1, 1, 256)
struct.pack_into('<QQQQQ', payload, 120, 0x314d4f4353435655, 1, 0, 0, 1)
payload[160] = ord('x')
struct.pack_into('<QQQ', payload, 376, 2, 1, 32)
digest = (sum(b'UVCSCHK1') + sum(payload[120:376])) & 0xff
payload[400:432] = bytes([digest]) * 32
seed = (ctypes.c_ubyte * 32)(*range(32))
frame = (ctypes.c_ubyte * (HEADER + PAYLOAD))()

assert lib.bundle_seal_probe(frame, len(frame), payload, PAYLOAD, 2, seed) == 0
assert status.value == 0 and length.value == len(frame)
assert bytes(frame[104:168]) == bytes([0x22]) * 64
assert lib.bundle_open_probe(frame, len(frame)) == 0
assert status.value == 0 and length.value == PAYLOAD and operation.value == 2
assert pointer.value == ctypes.addressof(frame) + HEADER

frame[HEADER + 7] ^= 1
assert lib.bundle_open_probe(frame, len(frame)) == CORRUPT
frame[HEADER + 7] ^= 1
trust.value = 1
assert lib.bundle_open_probe(frame, len(frame)) == 1
trust.value = 0
verify.value = 1
assert lib.bundle_open_probe(frame, len(frame)) == PERM
verify.value = 0
assert lib.bundle_open_probe(frame, len(frame) - 1) == CORRUPT
assert lib.bundle_open_probe(None, len(frame)) == USAGE
assert lib.bundle_seal_probe(frame, len(frame) - 1, payload, PAYLOAD, 1, seed) == NO_MEM
assert lib.bundle_seal_probe(frame, len(frame), payload, PAYLOAD, 0, seed) == USAGE
assert lib.bundle_seal_probe(frame, len(frame), payload, PAYLOAD, 1, None) == USAGE
payload[400] ^= 1
assert lib.bundle_seal_probe(frame, len(frame), payload, PAYLOAD, 1, seed) == CORRUPT

print('VCS bundle frame: PASS (seal/open, full signature, tamper, trust, bounds)')
