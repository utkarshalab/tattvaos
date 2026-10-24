#!/usr/bin/env python3
"""Persistent UXFS shell behavior, bounded errors, corrupt-image recovery."""
from pathlib import Path
import importlib.util
import subprocess
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume', ROOT/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
EXE = Path(sys.argv[1]).resolve()

with tempfile.TemporaryDirectory() as work:
    disk = Path(work)/'data.uxfs'
    disk.write_bytes(fmt.image())

    def run(command, code=0):
        result = subprocess.run([str(EXE), '--disk', str(disk), '-c', command],
                                capture_output=True, timeout=10)
        assert result.returncode == code, (command, result)
        return result.stdout

    assert run('pwd; mkdir docs; cd docs; write note "first contents"; '
               'cp note copy; mv copy moved; touch empty; cat moved') == b'/\nfirst contents'
    assert run('ls /docs') == b'note\nmoved\nempty\n'
    assert run('cat /docs/note') == b'first contents'  # new process, real remount
    assert run('touch /docs/note; cat /docs/note') == b'first contents'
    assert run('cd /docs; cd ./../docs//.; pwd') == b'/docs\n'
    for command in ['touch /missing/file', 'touch /docs/note/child',
                    'touch /missing/../oops', 'mkdir /docs',
                    'cat /docs', 'cd /docs/note', 'cp /docs/note /docs/note',
                    'mv /docs/note /docs/moved', 'cp /docs /other',
                    'touch /' + 'a'*240]:
        before = disk.read_bytes()
        run(command, 1)
        assert disk.read_bytes() == before, command
    assert run('cd /docs; mv /docs /renamed; pwd; cat note') == b'/renamed\nfirst contents'
    before = disk.read_bytes()
    run('mv /renamed /renamed/child', 1)
    assert disk.read_bytes() == before
    run('mkdir /renamed/sub; write /renamed/sub/child nested')
    assert run('cd /renamed/sub; mv /renamed /other; pwd; cat child') == b'/other/sub\nnested'
    run('mv /other /docs')
    source = '/'+'a'*110
    target = '/'+'z'*150
    run('mkdir '+source)
    run('mkdir '+source+'/'+'b'*100)
    before = disk.read_bytes()
    run('mv '+source+' '+target, 1)
    assert disk.read_bytes() == before
    run('write /docs/note second')
    good = disk.read_bytes()
    # Damage the newest body: mount must recover the older complete snapshot.
    generations = [int.from_bytes(good[i*fmt.BANK*512+16:i*fmt.BANK*512+24], 'little')
                   for i in range(2)]
    newest = max(range(2), key=generations.__getitem__)
    damaged = bytearray(good)
    damaged[newest*fmt.BANK*512+512+260] ^= 0x80
    disk.write_bytes(damaged)
    assert run('cat /docs/note') == b'first contents'
    disk.write_bytes(bytes(len(good)))
    run('touch should-not-format', 1)
    assert disk.read_bytes() == bytes(len(good))
    disk.write_bytes(fmt.image())
    # Root consumes one node. No silent aliasing or replacement on exhaustion.
    for i in range(63):
        run(f'touch /f{i}')
    before = disk.read_bytes()
    run('touch /overflow', 1)
    assert disk.read_bytes() == before
    # Only one host writer may open an image. Wait for a real command result
    # rather than assuming a sleep means the first process acquired its lock.
    owner = subprocess.Popen([str(EXE), '--disk', str(disk)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    owner.stdin.write(b'echo LOCKED\n')
    owner.stdin.flush()
    assert owner.stdout.readline() == b'LOCKED\n'
    denied = subprocess.run([str(EXE), '--disk', str(disk), '-c', 'pwd'], capture_output=True)
    assert denied.returncode == 2
    owner.stdin.close()
    assert owner.wait(timeout=5) == 0
    link = Path(work)/'link'
    link.symlink_to(disk)
    denied = subprocess.run([str(EXE), '--disk', str(link), '-c', 'pwd'], capture_output=True)
    assert denied.returncode == 2
    assert disk.read_bytes() == before
    # Formatter exclusively creates new files.
    result = subprocess.run([sys.executable, str(ROOT/'storage/uxfs/mkvolume.py'), str(disk)],
                            capture_output=True)
    assert result.returncode != 0 and disk.read_bytes() == before

    # Full-size binary content includes NUL and high bytes: cat/cp/mv must use
    # byte lengths, not NUL-terminated string copies.
    content = bytes(range(256))*16
    raw = bytearray(fmt.image())
    node = 512+fmt.NODE
    raw[node:node+8] = b'/binary\0'
    struct.pack_into('<QQ', raw, node+240, 1, len(content))
    raw[node+256:node+256+len(content)] = content
    struct.pack_into('<Q', raw, 24, fmt.checksum(raw[512:fmt.BANK*512]))
    struct.pack_into('<Q', raw, 32, 0)
    struct.pack_into('<Q', raw, 32, fmt.checksum(raw[:512]))
    disk.write_bytes(raw)
    assert run('cat /binary') == content
    assert run('cp /binary /copied; mv /copied /moved; cat /moved') == content
    run('touch /'+'q'*238)

assert subprocess.run([str(EXE), '-c', 'touch /file'], capture_output=True).returncode == 1
print('UXFS shell persistence, path validation, capacity and recovery: PASS')
