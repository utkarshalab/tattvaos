"""Git fast-import snapshot and first-parent history export validation."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bridge_export_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64]
lib.bridge_export_history_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64]
lib.bridge_export_probe.restype = lib.bridge_export_history_probe.restype = ctypes.c_uint64
length = ctypes.c_uint64.in_dll(lib, 'bridge_export_length')
count = ctypes.c_uint64.in_dll(lib, 'mock_export_count')
manifests = (ctypes.c_ubyte * (8 * 4096)).in_dll(lib, 'mock_export_manifests')
nodes = (ctypes.c_ubyte * (8 * 4352)).in_dll(lib, 'mock_export_nodes')
def put64(buf, offset, value): ctypes.c_uint64.from_buffer(buf, offset).value = value

ctypes.memset(manifests, 0, len(manifests)); ctypes.memset(nodes, 0, len(nodes)); count.value = 2
paths = (b'root.txt', b'src/"tip".asm'); messages = (b'root', b'line one\nline two'); blobs = (b'one', b'two')
for index in range(2):
    base = index * 4096; put64(manifests, base + 16, index); put64(manifests, base + 24, 1)
    put64(manifests, base + 32, len(messages[index])); manifests[base+40:base+40+len(messages[index])] = messages[index]
    manifests[base+256:base+256+len(paths[index])+1] = paths[index] + b'\0'
    put64(manifests, base + 496, index + 1); put64(manifests, base + 504, len(blobs[index]))
    node = index * 4352; put64(nodes, node + 240, 1); put64(nodes, node + 248, len(blobs[index])); nodes[node+256:node+256+len(blobs[index])] = blobs[index]

identity = (b'author Tattva VCS <vcs@tattva.local> 0 +0000\n'
            b'committer Tattva VCS <vcs@tattva.local> 0 +0000\n')
def snapshot(index, blob_mark, commit_mark):
    path = paths[index].replace(b'"', b'\\042')
    return (b'blob\nmark :' + str(blob_mark).encode() + b'\ndata ' + str(len(blobs[index])).encode() + b'\n'
            + blobs[index] + b'\ncommit refs/heads/main\nmark :' + str(commit_mark).encode() + b'\n'
            + identity + b'data ' + str(len(messages[index])).encode() + b'\n' + messages[index]
            + b'\ndeleteall\nM 100644 :' + str(blob_mark).encode() + b' "' + path + b'"\n')

output = (ctypes.c_ubyte * 4096)()
assert lib.bridge_export_probe(2, output, len(output)) == 0
expected = snapshot(1, 1, 2) + b'done\n'
assert bytes(output[:length.value]) == expected

assert lib.bridge_export_history_probe(2, output, len(output)) == 0
expected = snapshot(0, 1, 2) + snapshot(1, 3, 4) + b'done\n'
assert bytes(output[:length.value]) == expected
assert expected.count(b'commit refs/heads/main\n') == 2 and b'line one\nline two' in expected

assert lib.bridge_export_probe(0, output, len(output)) == 8
assert lib.bridge_export_probe(2, None, len(output)) == 8
assert lib.bridge_export_probe(3, output, len(output)) == 5
assert lib.bridge_export_probe(2, output, len(snapshot(1, 1, 2))) == 3
put64(nodes, 4352 + 248, 2)
assert lib.bridge_export_probe(2, output, len(output)) == 5

print('VCS bridge export: PASS (snapshot, history, marks, multiline, quoting, bounds)')
