"""Strict Git protocol-v2 request parser coverage."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.upload_request_probe.argtypes = [P, ctypes.c_uint64]
lib.upload_request_probe.restype = ctypes.c_uint64
lib.upload_haves_probe.restype = ctypes.c_uint64

def q(name):
    return ctypes.c_uint64.in_dll(lib, name)

status, operation, pointer, flags, count = (q(n) for n in
    ('probe_status', 'probe_operation', 'probe_pointer', 'probe_flags', 'probe_count'))

def pkt(payload):
    size = len(payload) + 4
    return f'{size:04x}'.encode() + payload

def request(command, arguments, headers=()):
    return (pkt(b'command=' + command + b'\n') +
            b''.join(pkt(h) for h in (b'object-format=sha256\n',) + tuple(headers)) +
            b'0001' + b''.join(pkt(a) for a in arguments) + b'0000')

def parse(raw):
    buf = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
    result = lib.upload_request_probe(buf, len(buf))
    data = b'' if result or not pointer.value else ctypes.string_at(pointer.value, 32)
    return result, operation.value, flags.value, data

raw = request(b'ls-refs', (b'symrefs\n', b'unborn\n', b'ref-prefix refs/heads/\n'),
              (b'agent=test/1\n', b'session-id=abc\n'))
r, op, bits, _ = parse(raw)
assert r == 0 and op == 1 and bits & 1 and bits & 8 and bits & 4, (r, op, bits)

want = bytes(range(32)); want_hex = want.hex().encode()
raw = request(b'fetch', (b'want ' + want_hex + b'\n', b'thin-pack\n',
                         b'sideband-all\n', b'done\n'))
r, op, bits, parsed = parse(raw)
assert r == 0 and op == 2 and parsed == want and bits & 32, (r, op, bits, parsed)
have = bytes(reversed(range(32)))
raw = request(b'fetch', (b'want ' + want_hex + b'\n',
                         b'have ' + have.hex().encode() + b'\n'))
r, op, bits, parsed = parse(raw)
assert r == 0 and op == 2 and parsed == want and bits & 8192, (r, op, bits, parsed)
lib.upload_haves_probe()
assert count.value == 1 and ctypes.string_at(pointer.value, 32) == have

info = bytes([0xa5]) * 32
raw = request(b'object-info', (b'size\n', b'oid ' + info.hex().encode() + b'\n'))
r, op, items, parsed = parse(raw)
assert r == 0 and op == 3 and items == 1 and parsed == info

bad = [
    b'',
    pkt(b'command=ls-refs\n') + b'0001' + b'0000',
    request(b'unknown', ()),
    request(b'fetch', (b'want ' + b'z'*64 + b'\n', b'done\n')),
    request(b'fetch', (b'want ' + want_hex + b'\n', b'done\n', b'done\n')),
    request(b'object-info', (b'oid ' + info.hex().encode() + b'\n',)),
    b'zzzz',
    b'0010short',
    request(b'ls-refs', ()) + b'x',
]
for malformed in bad:
    if not malformed:
        assert lib.upload_request_probe(None, 0) == 8
    else:
        assert parse(malformed)[0] != 0

print('VCS upload request: PASS (commands, OIDs, haves, capabilities, malformed packets)')
