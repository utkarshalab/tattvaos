"""Git fast-import parser, materialization, and rollback validation."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bridge_import_probe.argtypes = [P, ctypes.c_uint64, P, P]
lib.bridge_import_probe.restype = ctypes.c_uint64
def q(name): return ctypes.c_uint64.in_dll(lib, name)
calls, signed, fail_at, checkout, discover, head, root_size = [q(name) for name in (
    'mock_import_calls', 'mock_import_signed', 'mock_import_fail_at',
    'mock_import_checkout', 'mock_import_discover', 'vcs_repo_head', 'vcs_repo_root_size')]
messages = (ctypes.c_ubyte * (4 * 216)).in_dll(lib, 'mock_import_messages')
nodes = (ctypes.c_ubyte * (64 * 4352)).in_dll(lib, 'uxv_nodes')
root = (ctypes.c_ubyte * 240).in_dll(lib, 'vcs_repo_root')
writer = (ctypes.c_ubyte * 1)(); seed = (ctypes.c_ubyte * 32)(*range(32))

identity = (b'author Tattva VCS <vcs@tattva.local> 0 +0000\n'
            b'committer Tattva VCS <vcs@tattva.local> 0 +0000\n')
def snapshot(blob, message, path, blob_mark, commit_mark):
    return (b'blob\nmark :' + str(blob_mark).encode() + b'\ndata ' + str(len(blob)).encode() + b'\n' + blob
            + b'\ncommit refs/heads/main\nmark :' + str(commit_mark).encode() + b'\n' + identity
            + b'data ' + str(len(message)).encode() + b'\n' + message + b'\ndeleteall\nM 100644 :'
            + str(blob_mark).encode() + b' "' + path + b'"\n')
stream = snapshot(b'one', b'root', b'root.txt', 1, 2) + snapshot(
    b'two', b'line one\nline two', b'src/\\042tip\\042.asm', 3, 4) + b'done\n'

def reset():
    ctypes.memset(nodes, 0, len(nodes)); ctypes.memset(messages, 0, len(messages))
    calls.value = signed.value = fail_at.value = checkout.value = discover.value = head.value = 0
    ctypes.memset(root, 0, len(root)); root[0] = ord('/'); root_size.value = 1
def run(raw, signing=None):
    data = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
    return lib.bridge_import_probe(data, len(raw), signing, writer)
def live_node():
    for index in range(1, 64):
        value = bytes(nodes[index*4352:(index+1)*4352])
        if int.from_bytes(value[240:248], 'little') == 1: return value
    raise AssertionError('missing imported file')

reset(); status = run(stream); assert status == 0, (status, discover.value, calls.value, head.value)
assert calls.value == 2 and signed.value == 0 and head.value == 2
assert ctypes.string_at(ctypes.addressof(messages), 216).split(b'\0', 1)[0] == b'root'
assert ctypes.string_at(ctypes.addressof(messages) + 216, 216).split(b'\0', 1)[0] == b'line one\nline two'
final = live_node(); assert final.split(b'\0', 1)[0] == b'/src/"tip".asm'
assert int.from_bytes(final[248:256], 'little') == 3 and final[256:259] == b'two'

reset(); one = snapshot(b'one', b'signed', b'a.txt', 1, 2) + b'done\n'
assert run(one, seed) == 0 and calls.value == 1 and signed.value == 1

reset(); fail_at.value = 2
assert run(stream) == 6 and calls.value == 2 and checkout.value == 1

reset(); head.value = 7
assert run(one) == 6
reset(); nodes[4352:4358] = b'/busy\0'; ctypes.c_uint64.from_buffer(nodes, 4352 + 240).value = 1
assert run(one) == 6
reset(); assert run(one.replace(b'mark :1', b'mark :9', 1)) == 5
reset(); assert run(one.replace(b'"a.txt"', b'"../x"')) == 5
assert lib.bridge_import_probe(None, 1, None, writer) == 8

print('VCS bridge import: PASS (history, marks, quoting, signed, safety, rollback, malformed)')
