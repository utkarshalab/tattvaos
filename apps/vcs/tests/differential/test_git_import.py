"""Import a real Git full-tree fast-export stream through the assembly bridge."""
import ctypes
import pathlib
import subprocess
import sys
import tempfile

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.bridge_import_probe.argtypes = [P, ctypes.c_uint64, P, P]
lib.bridge_import_probe.restype = ctypes.c_uint64

def q(name):
    return ctypes.c_uint64.in_dll(lib, name)

calls, signed, fail_at, checkout, discover, head, root_size = [q(name) for name in (
    'mock_import_calls', 'mock_import_signed', 'mock_import_fail_at',
    'mock_import_checkout', 'mock_import_discover', 'vcs_repo_head',
    'vcs_repo_root_size')]
messages = (ctypes.c_ubyte * (4 * 216)).in_dll(lib, 'mock_import_messages')
nodes = (ctypes.c_ubyte * (64 * 4352)).in_dll(lib, 'uxv_nodes')
root = (ctypes.c_ubyte * 240).in_dll(lib, 'vcs_repo_root')
writer = (ctypes.c_ubyte * 1)()

def git(repo, *args, data=None):
    return subprocess.run(
        ['git', '-C', str(repo), *args], input=data, check=True,
        stdout=subprocess.PIPE,
    ).stdout

def reset_probe():
    ctypes.memset(nodes, 0, len(nodes))
    ctypes.memset(messages, 0, len(messages))
    calls.value = signed.value = fail_at.value = checkout.value = 0
    discover.value = head.value = 0
    ctypes.memset(root, 0, len(root))
    root[0] = ord('/')
    root_size.value = 1

def live_node():
    for index in range(1, 64):
        node = bytes(nodes[index * 4352:(index + 1) * 4352])
        if int.from_bytes(node[240:248], 'little') == 1:
            return node
    raise AssertionError('missing imported file')

with tempfile.TemporaryDirectory(prefix='tattva-vcs-git-import-') as directory:
    repo = pathlib.Path(directory)
    subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True)
    git(repo, 'config', 'user.name', 'Tattva VCS')
    git(repo, 'config', 'user.email', 'vcs@tattva.local')

    (repo / 'root.txt').write_bytes(b'one\x00root')
    git(repo, 'add', 'root.txt')
    git(repo, 'commit', '-q', '--cleanup=verbatim', '-F', '-', data=b'root\n')

    (repo / 'root.txt').unlink()
    quoted = repo / 'src' / '"tip".asm'
    quoted.parent.mkdir()
    quoted.write_bytes(b'two\x00line\n tip')
    git(repo, 'add', '-A')
    git(repo, 'commit', '-q', '--cleanup=verbatim', '-F', '-',
        data=b'line one\nline two\n')

    stream = git(
        repo, 'fast-export', '--full-tree', '--use-done-feature',
        'refs/heads/main',
    )

assert stream.startswith(b'feature done\n')
assert b'reset refs/heads/main\n' in stream
assert b'from :2\n' in stream
assert b'M 100644 :1 root.txt\n' in stream
assert b'M 100644 :3 "src/\\"tip\\".asm"\n' in stream

reset_probe()
raw = (ctypes.c_ubyte * len(stream)).from_buffer_copy(stream)
status = lib.bridge_import_probe(raw, len(stream), None, writer)
assert status == 0, (status, discover.value, calls.value, head.value)
assert calls.value == 2 and signed.value == 0 and head.value == 2
assert bytes(messages[:216]).split(b'\0', 1)[0] == b'root\n'
assert bytes(messages[216:432]).split(b'\0', 1)[0] == b'line one\nline two\n'
final = live_node()
assert final.split(b'\0', 1)[0] == b'/src/"tip".asm'
assert int.from_bytes(final[248:256], 'little') == len(b'two\x00line\n tip')
assert final[256:256 + len(b'two\x00line\n tip')] == b'two\x00line\n tip'

print('VCS Git import differential: PASS (real export, ancestry, messages, paths, binary blobs)')
