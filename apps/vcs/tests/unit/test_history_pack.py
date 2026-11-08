"""Executable multi-commit Git history object graph and PACK validation."""
import ctypes
import hashlib
import struct
import sys
import zlib

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
for name in ('history_pack_probe', 'history_pack_cut_probe', 'history_oid_probe',
             'history_common_probe'):
    getattr(lib, name).restype = ctypes.c_uint64
value = ctypes.c_uint64.in_dll(lib, 'history_pack_value')
manifest_count = ctypes.c_uint64.in_dll(lib, 'mock_history_manifest_count')
manifests = (ctypes.c_ubyte * (8 * 4096)).in_dll(lib, 'mock_history_manifests')
nodes = (ctypes.c_ubyte * (8 * 4352)).in_dll(lib, 'mock_history_nodes')

def put64(buf, offset, number): ctypes.c_uint64.from_buffer(buf, offset).value = number
def object_id(kind, body): return hashlib.sha256(kind + b' ' + str(len(body)).encode() + b'\0' + body).digest()
def commit(tree, parent, message):
    body = b'tree ' + tree.hex().encode() + b'\n'
    if parent: body += b'parent ' + parent.hex().encode() + b'\n'
    body += (b'author Tattva VCS <vcs@tattva.local> 0 +0000\n'
             b'committer Tattva VCS <vcs@tattva.local> 0 +0000\n\n' + message)
    return body, object_id(b'commit', body)
def parse_pack(raw):
    assert raw[:4] == b'PACK' and struct.unpack('>I', raw[4:8])[0] == 2
    count = struct.unpack('>I', raw[8:12])[0]; pos = 12; result = []
    for _ in range(count):
        byte = raw[pos]; pos += 1; kind = (byte >> 4) & 7; size = byte & 15; shift = 4
        while byte & 128:
            byte = raw[pos]; pos += 1; size |= (byte & 127) << shift; shift += 7
        stream = zlib.decompressobj(); body = stream.decompress(raw[pos:-32])
        assert stream.eof and len(body) == size
        pos += len(raw[pos:-32]) - len(stream.unused_data); result.append((kind, body))
    assert pos == len(raw) - 32 and raw[-32:] == hashlib.sha256(raw[:-32]).digest()
    return result

ctypes.memset(manifests, 0, len(manifests)); ctypes.memset(nodes, 0, len(nodes)); manifest_count.value = 2
messages = (b'root\n', b'tip\n'); blobs = (b'one', b'two')
for index in range(2):
    base = index * 4096; put64(manifests, base + 16, index); put64(manifests, base + 24, 1)
    put64(manifests, base + 32, len(messages[index])); manifests[base+40:base+40+len(messages[index])] = messages[index]
    manifests[base+256:base+262] = b'a.txt\0'; put64(manifests, base + 496, index + 1); put64(manifests, base + 504, 3)
    node = index * 4352; put64(nodes, node + 240, 1); put64(nodes, node + 248, 3); nodes[node+256:node+259] = blobs[index]

blob_ids = [object_id(b'blob', body) for body in blobs]
trees = [b'100644 a.txt\0' + oid for oid in blob_ids]
tree_ids = [object_id(b'tree', body) for body in trees]
root_body, root_id = commit(tree_ids[0], None, messages[0])
tip_body, tip_id = commit(tree_ids[1], root_id, messages[1])

oid = (ctypes.c_ubyte * 32)(); lib.history_oid_probe.argtypes = [ctypes.c_uint64, P]
assert lib.history_oid_probe(2, oid) == 0 and value.value == 32 and bytes(oid) == tip_id

pack = (ctypes.c_ubyte * 8192)(); lib.history_pack_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, P]
assert lib.history_pack_probe(2, pack, len(pack), oid) == 0 and bytes(oid) == tip_id
objects = parse_pack(bytes(pack[:value.value]))
assert objects == [(3, blobs[0]), (2, trees[0]), (1, root_body),
                   (3, blobs[1]), (2, trees[1]), (1, tip_body)]

haves = (ctypes.c_ubyte * 32).from_buffer_copy(root_id)
lib.history_common_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64]
assert lib.history_common_probe(2, haves, 1) == 0 and value.value == 1
lib.history_pack_cut_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, P, ctypes.c_int64, ctypes.c_uint64]
assert lib.history_pack_cut_probe(2, pack, len(pack), oid, 1, 0) == 0
assert parse_pack(bytes(pack[:value.value])) == [(3, blobs[1]), (2, trees[1]), (1, tip_body)]

# Filtered packs retain the canonical graph identities while omitting blobs.
assert lib.history_pack_cut_probe(2, pack, len(pack), oid, -1, 1 << 6) == 0
assert parse_pack(bytes(pack[:value.value])) == [
    (2, trees[0]), (1, root_body), (2, trees[1]), (1, tip_body)]

# A one-commit absolute depth reports the tip as the shallow boundary.
assert lib.history_pack_cut_probe(2, pack, len(pack), oid, -1, 1 << 16) == 0
assert parse_pack(bytes(pack[:value.value])) == [(3, blobs[1]), (2, trees[1]), (1, tip_body)]
lib.git_history_shallow.restype = ctypes.c_void_p
shallow = lib.git_history_shallow()
assert shallow and ctypes.string_at(shallow, 32) == tip_id
lib.git_history_set_unshallow.argtypes = [P]
lib.git_history_set_unshallow(haves)
lib.git_history_unshallow.restype = ctypes.c_void_p
assert ctypes.string_at(lib.git_history_unshallow(), 32) == root_id
lib.git_history_set_unshallow(None)
assert not lib.git_history_unshallow()

queries = (ctypes.c_ubyte * 96).from_buffer_copy(blob_ids[1] + tree_ids[1] + tip_id)
sizes = (ctypes.c_uint64 * 3)(); found = (ctypes.c_ubyte * 3)()
lib.git_history_object_sizes.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, ctypes.POINTER(ctypes.c_uint64), P]
assert lib.git_history_object_sizes(2, queries, 3, sizes, found) == 0
assert list(found) == [1, 1, 1] and list(sizes) == [3, len(trees[1]), len(tip_body)]

assert lib.history_pack_probe(0, pack, len(pack), oid) == 8
assert lib.history_pack_probe(2, None, len(pack), oid) == 8
assert lib.history_common_probe(2, None, 1) == 8
assert lib.git_history_object_sizes(2, queries, 33, sizes, found) == 8

print('VCS history pack: PASS (OID chain, PACK graph, common cut, filters, shallow, sizes, bounds)')
