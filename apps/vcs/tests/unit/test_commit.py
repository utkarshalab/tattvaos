"""Canonical Git SHA-256 commit object encoder validation."""
import ctypes
import hashlib
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)

class Request(ctypes.Structure):
    _fields_ = [(name, field) for name, field in (
        ('tree', P), ('parent', P), ('message', P),
        ('message_len', ctypes.c_uint64), ('output', P),
        ('capacity', ctypes.c_uint64), ('hash', P))]

lib.commit_encode_probe.argtypes = [ctypes.POINTER(Request)]
lib.commit_encode_probe.restype = ctypes.c_uint64
length = ctypes.c_uint64.in_dll(lib, 'commit_probe_length')

def array(data):
    return (ctypes.c_ubyte * max(1, len(data)))(*data)

def encode(message, parent=True, capacity=512):
    tree = array(bytes(range(32)))
    parent_hash = array(bytes(range(32, 64)))
    text = array(message)
    output = (ctypes.c_ubyte * 512)(*[0xa5] * 512)
    digest = (ctypes.c_ubyte * 32)()
    request = Request(tree, parent_hash if parent else None, text, len(message),
                      output, capacity, digest)
    status = lib.commit_encode_probe(ctypes.byref(request))
    return status, bytes(output[:length.value]), bytes(digest), bytes(output)

identity = (b'author Tattva VCS <vcs@tattva.local> 0 +0000\n'
            b'committer Tattva VCS <vcs@tattva.local> 0 +0000\n\n')
message = b'first line\n\nsecond line\n'
tree_line = b'tree ' + bytes(range(32)).hex().encode() + b'\n'
parent_line = b'parent ' + bytes(range(32, 64)).hex().encode() + b'\n'

status, body, digest, _ = encode(message)
expected = tree_line + parent_line + identity + message
assert status == 0 and body == expected
assert digest == hashlib.sha256(b'commit ' + str(len(expected)).encode() + b'\0' + expected).digest()

status, body, digest, _ = encode(b'root\n', parent=False)
expected = tree_line + identity + b'root\n'
assert status == 0 and body == expected and b'parent ' not in body
assert digest == hashlib.sha256(b'commit ' + str(len(expected)).encode() + b'\0' + expected).digest()

status, _, _, untouched = encode(message, capacity=len(tree_line + parent_line + identity + message) - 1)
assert status == 3 and untouched == bytes([0xa5]) * 512
assert encode(b'x' * 215)[0] == 0
assert encode(b'x' * 216)[0] == 8

tree = array(bytes(32)); text = array(b'x'); output = (ctypes.c_ubyte * 512)(); digest = (ctypes.c_ubyte * 32)()
valid = Request(tree, None, text, 1, output, len(output), digest)
assert lib.commit_encode_probe(None) == 8
for field in ('tree', 'message', 'output', 'hash'):
    request = Request.from_buffer_copy(valid)
    setattr(request, field, None)
    assert lib.commit_encode_probe(ctypes.byref(request)) == 8, field
request = Request.from_buffer_copy(valid); request.message_len = 0
assert lib.commit_encode_probe(ctypes.byref(request)) == 8

print('VCS commit: PASS (canonical body, parent/root, multiline, SHA-256, bounds)')
