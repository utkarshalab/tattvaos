"""Differentially validate assembly fast-import history against Git."""
import ctypes
import pathlib
import subprocess
import sys
import tempfile

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bridge_export_history_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64]
lib.bridge_export_history_probe.restype = ctypes.c_uint64
length = ctypes.c_uint64.in_dll(lib, 'bridge_export_length')
count = ctypes.c_uint64.in_dll(lib, 'mock_export_count')
manifests = (ctypes.c_ubyte * (8 * 4096)).in_dll(lib, 'mock_export_manifests')
nodes = (ctypes.c_ubyte * (8 * 4352)).in_dll(lib, 'mock_export_nodes')

def put64(buf, offset, value):
    ctypes.c_uint64.from_buffer(buf, offset).value = value

ctypes.memset(manifests, 0, len(manifests))
ctypes.memset(nodes, 0, len(nodes))
count.value = 2
paths = (b'root.txt', b'src/"tip".asm')
messages = (b'root', b'line one\nline two')
blobs = (b'one\x00root', b'two\n tip')
for index in range(2):
    base = index * 4096
    put64(manifests, base + 16, index)
    put64(manifests, base + 24, 1)
    put64(manifests, base + 32, len(messages[index]))
    manifests[base + 40:base + 40 + len(messages[index])] = messages[index]
    manifests[base + 256:base + 256 + len(paths[index]) + 1] = paths[index] + b'\0'
    put64(manifests, base + 496, index + 1)
    put64(manifests, base + 504, len(blobs[index]))
    node = index * 4352
    put64(nodes, node + 240, 1)
    put64(nodes, node + 248, len(blobs[index]))
    nodes[node + 256:node + 256 + len(blobs[index])] = blobs[index]

output = (ctypes.c_ubyte * 4096)()
assert lib.bridge_export_history_probe(2, output, len(output)) == 0
stream = bytes(output[:length.value])

with tempfile.TemporaryDirectory(prefix='tattva-vcs-git-') as directory:
    repo = pathlib.Path(directory)
    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
    subprocess.run(['git', '-C', str(repo), 'fast-import', '--quiet'], input=stream, check=True)

    commits = subprocess.check_output(
        ['git', '-C', str(repo), 'rev-list', '--reverse', 'refs/heads/main']
    ).splitlines()
    assert len(commits) == 2
    root, tip = commits
    assert subprocess.check_output(
        ['git', '-C', str(repo), 'rev-list', '--parents', '-n', '1', tip]
    ).split() == [tip, root]

    for commit, message, path, blob in zip(commits, messages, paths, blobs):
        raw = subprocess.check_output(['git', '-C', str(repo), 'cat-file', 'commit', commit])
        assert raw.split(b'\n\n', 1)[1] == message
        tree = subprocess.check_output(
            ['git', '-C', str(repo), 'ls-tree', '-rz', '--full-tree', commit]
        )
        meta, actual_path = tree[:-1].split(b'\t', 1)
        mode, kind, object_id = meta.split()
        assert (mode, kind, actual_path) == (b'100644', b'blob', path)
        assert subprocess.check_output(
            ['git', '-C', str(repo), 'cat-file', 'blob', object_id]
        ) == blob

print('VCS Git differential: PASS (fast-import ancestry, messages, quoting, modes, binary blobs)')
