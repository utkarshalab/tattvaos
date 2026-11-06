"""Production Git packet-line codec boundary and round-trip coverage."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bridge_encode_probe.argtypes = [P, ctypes.c_uint64, P, ctypes.c_uint64]
lib.bridge_decode_probe.argtypes = [P, ctypes.c_uint64]
lib.bridge_encode_probe.restype = ctypes.c_uint64
lib.bridge_decode_probe.restype = ctypes.c_uint64

def q(name):
    return ctypes.c_uint64.in_dll(lib, name)

status, pointer, length, consumed, kind = (q(n) for n in
    ('probe_status', 'probe_pointer', 'probe_length', 'probe_consumed', 'probe_kind'))

def decode(raw, available=None):
    buf = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
    result = lib.bridge_decode_probe(buf, len(raw) if available is None else available)
    data = b'' if result or not pointer.value else ctypes.string_at(pointer.value, length.value)
    return result, data, consumed.value, kind.value

payload = (ctypes.c_ubyte * 5)(*b'hello')
encoded = (ctypes.c_ubyte * 16)()
assert lib.bridge_encode_probe(payload, 5, encoded, len(encoded)) == 0
assert length.value == 9 and bytes(encoded[:9]) == b'0009hello'
assert decode(bytes(encoded[:9])) == (0, b'hello', 9, 0)

assert decode(b'0000') == (0, b'', 4, 0)
assert decode(b'0001') == (0, b'', 4, 1)
assert decode(b'0002') == (0, b'', 4, 2)
assert decode(b'0003')[0] == 5
assert decode(b'0009hello', 8)[0] == 1
assert decode(b'00xz')[0] == 5
assert decode(b'000') [0] == 1
assert lib.bridge_decode_probe(None, 4) == 8
assert lib.bridge_encode_probe(None, 1, encoded, len(encoded)) == 8
assert lib.bridge_encode_probe(payload, 5, None, len(encoded)) == 8
assert lib.bridge_encode_probe(payload, 5, encoded, 8) == 3

large = (ctypes.c_ubyte * 65515)(*([0xa5] * 65515))
frame = (ctypes.c_ubyte * 65519)()
assert lib.bridge_encode_probe(large, len(large), frame, len(frame)) == 0
assert length.value == 65519 and bytes(frame[:4]) == b'ffef'
r, data, used, packet_kind = decode(bytes(frame))
assert r == 0 and len(data) == 65515 and data[:1] == b'\xa5'
assert used == 65519 and packet_kind == 0
assert lib.bridge_encode_probe(large, 65516, frame, len(frame)) == 8

print('VCS bridge codec: PASS (round trip, special packets, malformed, maximum bounds)')
