"""Git protocol-v2 response encoder executable coverage."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
Q = ctypes.POINTER(ctypes.c_uint64)
lib.advertise_probe.argtypes = [P, ctypes.c_uint64]
lib.ls_refs_probe.argtypes = [P, ctypes.c_uint64, P, ctypes.c_uint64]
lib.object_info_probe.argtypes = [P, Q, ctypes.c_uint64, P, ctypes.c_uint64]
lib.acknowledge_probe.argtypes = [P, ctypes.c_uint64, P, ctypes.c_uint64, ctypes.c_uint64]
lib.fetch_probe.argtypes = [P, ctypes.c_uint64, P, ctypes.c_uint64, ctypes.c_uint64, P]
for name in ('advertise_probe', 'ls_refs_probe', 'object_info_probe',
             'acknowledge_probe', 'fetch_probe', 'git_protocol_v2_set_session_id'):
    getattr(lib, name).restype = ctypes.c_uint64
status = ctypes.c_uint64.in_dll(lib, 'probe_status')
length = ctypes.c_uint64.in_dll(lib, 'probe_length')

def packets(data):
    out = []
    pos = 0
    while pos < len(data):
        prefix = data[pos:pos+4]
        if prefix in (b'0000', b'0001'):
            out.append(prefix); pos += 4; continue
        size = int(prefix, 16)
        assert 4 <= size <= len(data)-pos
        out.append(data[pos+4:pos+size]); pos += size
    return out

out = (ctypes.c_ubyte * 4096)()
assert lib.advertise_probe(out, len(out)) == 0
records = packets(bytes(out[:length.value]))
assert records[0] == b'version 2\n' and records[-1] == b'0000'
assert b'object-format=sha256\n' in records and b'fetch=wait-for-done ref-in-want sideband-all filter shallow\n' in records
session = (ctypes.c_ubyte * 16)(*range(16))
assert lib.git_protocol_v2_set_session_id(session) == 0
assert lib.advertise_probe(out, len(out)) == 0
assert b'session-id=000102030405060708090a0b0c0d0e0f\n' in packets(bytes(out[:length.value]))
assert lib.advertise_probe(out, 4) == 3

oid = (ctypes.c_ubyte * 32)(*range(32))
assert lib.ls_refs_probe(oid, 7, out, len(out)) == 0
records = packets(bytes(out[:length.value]))
hexoid = bytes(range(32)).hex().encode()
assert hexoid + b' HEAD symref-target:refs/heads/main\n' in records
assert hexoid + b' refs/heads/main\n' in records and records[-1] == b'0000'

oids = (ctypes.c_ubyte * 64)(*range(64))
sizes = (ctypes.c_uint64 * 2)(0, 18446744073709551615)
assert lib.object_info_probe(oids, sizes, 2, out, len(out)) == 0
records = packets(bytes(out[:length.value]))
assert records[0] == b'size\n'
assert records[1] == bytes(range(32)).hex().encode() + b' 0\n'
assert records[2].endswith(b' 18446744073709551615\n')

assert lib.acknowledge_probe(None, 0, out, len(out), 0) == 0
assert packets(bytes(out[:length.value])) == [b'acknowledgments\n', b'NAK\n', b'0000']
assert lib.acknowledge_probe(oid, 1, out, len(out), 0) == 0
assert hexoid in packets(bytes(out[:length.value]))[1]

pack = (ctypes.c_ubyte * 4)(*b'PACK')
assert lib.fetch_probe(pack, 4, out, len(out), 0, None) == 0
records = packets(bytes(out[:length.value]))
assert records == [b'packfile\n', b'\x01PACK', b'0000']
assert lib.fetch_probe(None, 4, out, len(out), 0, None) == 8
assert lib.object_info_probe(None, sizes, 2, out, len(out)) == 8
assert lib.object_info_probe(oids, sizes, 0, out, len(out)) == 8

print('VCS upload protocol: PASS (advertise, refs, object-info, ACK, sideband, bounds)')
