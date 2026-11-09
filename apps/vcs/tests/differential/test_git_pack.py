"""Validate assembly-generated SHA-256 PACK history with Git."""
import ctypes
import hashlib
import pathlib
import subprocess
import sys
import tempfile

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.smart_serve_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, P, ctypes.c_uint64, ctypes.c_uint64]
lib.smart_serve_probe.restype = ctypes.c_uint64
length = ctypes.c_uint64.in_dll(lib, 'smart_length')
count = ctypes.c_uint64.in_dll(lib, 'mock_smart_count')
manifests = (ctypes.c_ubyte * (8 * 4096)).in_dll(lib, 'mock_smart_manifests')
nodes = (ctypes.c_ubyte * (8 * 4352)).in_dll(lib, 'mock_smart_nodes')

def put64(buf, offset, value):
    ctypes.c_uint64.from_buffer(buf, offset).value = value

def oid(kind, body):
    return hashlib.sha256(kind + b' ' + str(len(body)).encode() + b'\0' + body).digest()

def commit(tree, parent, message):
    body = b'tree ' + tree.hex().encode() + b'\n'
    if parent:
        body += b'parent ' + parent.hex().encode() + b'\n'
    body += (b'author Tattva VCS <vcs@tattva.local> 0 +0000\n'
             b'committer Tattva VCS <vcs@tattva.local> 0 +0000\n\n' + message)
    return body, oid(b'commit', body)

def pkt(payload):
    return f'{len(payload) + 4:04x}'.encode() + payload

def packets(raw):
    result = []
    position = 0
    while position < len(raw):
        prefix = raw[position:position + 4]
        if prefix in (b'0000', b'0001'):
            result.append(prefix)
            position += 4
            continue
        size = int(prefix, 16)
        result.append(raw[position + 4:position + size])
        position += size
    return result

ctypes.memset(manifests, 0, len(manifests))
ctypes.memset(nodes, 0, len(nodes))
count.value = 2
blobs = (b'root\x00blob', b'tip\nblob')
messages = (b'root\n', b'tip\n')
for index in range(2):
    base = index * 4096
    put64(manifests, base + 16, index)
    put64(manifests, base + 24, 1)
    put64(manifests, base + 32, len(messages[index]))
    manifests[base + 40:base + 40 + len(messages[index])] = messages[index]
    manifests[base + 256:base + 262] = b'a.txt\0'
    put64(manifests, base + 496, index + 1)
    put64(manifests, base + 504, len(blobs[index]))
    node = index * 4352
    put64(nodes, node + 240, 1)
    put64(nodes, node + 248, len(blobs[index]))
    nodes[node + 256:node + 256 + len(blobs[index])] = blobs[index]

blob_ids = [oid(b'blob', body) for body in blobs]
trees = [b'100644 a.txt\0' + blob_id for blob_id in blob_ids]
tree_ids = [oid(b'tree', body) for body in trees]
root_body, root_id = commit(tree_ids[0], None, messages[0])
tip_body, tip_id = commit(tree_ids[1], root_id, messages[1])
tip_hex = tip_id.hex().encode()

request = (pkt(b'command=fetch\n') + pkt(b'object-format=sha256\n') + b'0001'
           + pkt(b'want ' + tip_hex + b'\n') + pkt(b'done\n') + b'0000')
request_buffer = (ctypes.c_ubyte * len(request)).from_buffer_copy(request)
response = (ctypes.c_ubyte * 65519)()
assert lib.smart_serve_probe(1, request_buffer, len(request), response, len(response), 2) == 0
records = packets(bytes(response[:length.value]))
assert records[0] == b'packfile\n' and records[-1] == b'0000'
pack = b''.join(record[1:] for record in records[1:-1] if record[:1] == b'\x01')

with tempfile.TemporaryDirectory(prefix='tattva-vcs-pack-') as directory:
    repo = pathlib.Path(directory)
    subprocess.run(['git', 'init', '-q', '--object-format=sha256', str(repo)], check=True)
    subprocess.run(['git', '-C', str(repo), 'index-pack', '--stdin'], input=pack,
                   stdout=subprocess.DEVNULL, check=True)
    objects = ((blob_ids[0], b'blob', blobs[0]), (tree_ids[0], b'tree', trees[0]),
               (root_id, b'commit', root_body), (blob_ids[1], b'blob', blobs[1]),
               (tree_ids[1], b'tree', trees[1]), (tip_id, b'commit', tip_body))
    for object_id, kind, body in objects:
        name = object_id.hex()
        assert subprocess.check_output(['git', '-C', str(repo), 'cat-file', '-t', name]).strip() == kind
        assert subprocess.check_output(['git', '-C', str(repo), 'cat-file', kind.decode(), name]) == body
    subprocess.run(['git', '-C', str(repo), 'update-ref', 'refs/heads/main', tip_id.hex()], check=True)
    assert subprocess.check_output(
        ['git', '-C', str(repo), 'rev-list', '--reverse', 'refs/heads/main']
    ).splitlines() == [root_id.hex().encode(), tip_hex]

print('VCS Git PACK differential: PASS (SHA-256 index-pack, objects, ancestry, binary blobs)')
