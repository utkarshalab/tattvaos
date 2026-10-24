#!/usr/bin/env python3
"""Real executable checks for all file tools, binary boundaries and deletion."""
from pathlib import Path
import importlib.util
import random
import re
import struct
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume', ROOT/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
EXE = str(Path(sys.argv[1]).resolve())

with tempfile.TemporaryDirectory() as work:
    disk = Path(work)/'tools.uxfs'

    def image(entries):
        raw = bytearray(fmt.image())
        for i, (path, kind, data) in enumerate(entries, 1):
            offset = 512+i*fmt.NODE
            name = path.encode()+b'\0'
            raw[offset:offset+len(name)] = name
            struct.pack_into('<QQ', raw, offset+240, kind, len(data))
            raw[offset+256:offset+256+len(data)] = data
        struct.pack_into('<Q', raw, 24, fmt.checksum(raw[512:fmt.BANK*512]))
        struct.pack_into('<Q', raw, 32, 0)
        struct.pack_into('<Q', raw, 32, fmt.checksum(raw[:512]))
        disk.write_bytes(raw)

    def run(command, status=0):
        result = subprocess.run([EXE, '--disk', str(disk), '-c', command],
                                capture_output=True, timeout=8)
        assert result.returncode == status, (command, result)
        return result.stdout

    rng = random.Random(47)
    fixtures = [b'', b'\n', b'a\n', b'a\nb', b'a\nb\n', b'\n\nlast',
                b'a.b\naxb\na.b tail', bytes(range(256))*16]
    fixtures += [bytes(rng.choice(b'abc. \n\n\t\v\r\x00') for _ in range(151)) for _ in range(8)]
    for data in fixtures:
        image([('/file', 1, data)])
        lines = re.findall(rb'[^\n]*\n|[^\n]+$', data)
        assert run('head /file') == b''.join(lines[:10])
        assert run('tail /file') == b''.join(lines[-10:])
        for count in (0, 1, 2, 10, 500):
            assert run(f'head -n {count} /file') == b''.join(lines[:count])
            assert run(f'tail -n {count} /file') == (b''.join(lines[-count:]) if count else b'')
        expected = f'{data.count(bytes([10]))} {len(re.findall(rb"[^ \t\n\r\v\f]+", data))} {len(data)}\n'.encode()
        assert run('wc /file') == expected
        for pattern in ('', 'a', 'a.b', 'absent'):
            matches = [line for line in lines if pattern.encode() in line.removesuffix(b'\n')]
            assert run(f'grep "{pattern}" /file', 0 if matches else 1) == b''.join(matches)
        expected = bytearray()
        for offset in range(0, len(data), 16):
            chunk = data[offset:offset+16]
            ascii_text = ''.join(chr(x) if 32 <= x <= 126 else '.' for x in chunk)
            expected.extend((f'{offset:08x}  '+''.join(f'{x:02x} ' for x in chunk)
                            +' '*(3*(16-len(chunk)))+' |'+ascii_text.ljust(16)+'|\n').encode())
        assert run('hexdump /file') == expected
    image([('/dir', 2, b''), ('/dir/a', 1, b'alpha'), ('/dir2', 2, b''),
           ('/dir2/a', 1, b'xyz'), ('/empty', 2, b'')])
    assert run('stat /dir/a') == b'type: file\nsize: 5 bytes\npath: /dir/a\n'
    assert run('stat /dir') == b'type: directory\nsize: 0 bytes\npath: /dir\n'
    assert run('df') == b'records: 6 used, 58 free, 64 total\nlogical data: 8 bytes\nfile limit: 4096 bytes\n'
    assert run('du /dir') == b'5 bytes\n'
    assert run('du /dir/a') == b'5 bytes\n'
    assert run('du') == b'8 bytes\n'
    assert run('find / a') == b'/dir/a\n/dir2/a\n'
    assert run('find /dir') == b'/dir\n/dir/a\n'
    assert run('find /dir missing') == b''
    assert run('cd /dir; find') == b'/dir\n/dir/a\n'
    assert run('append /dir/a " beta"; cat /dir/a') == b'alpha beta'
    assert run('append /new created; cat /new') == b'created'
    for command, code in [('rm /dir', 1), ('rm /missing', 1), ('rmdir /', 1),
                          ('rmdir /dir', 1), ('cd /empty; rmdir /empty', 1),
                          ('append /dir x', 1), ('head -n -1 /new', 1),
                          ('tail -n 2147483648 /new', 1), ('head -x 2 /new', 1),
                          ('head -n /new', 1), ('grep x /dir', 2),
                          ('grep x /missing', 2), ('stat /missing', 1)]:
        before = disk.read_bytes()
        run(command, code)
        assert disk.read_bytes() == before, command
    run('rm /dir/a; rmdir /dir; rmdir /empty')
    assert run('find /dir', 1)
    assert run('cat /dir2/a') == b'xyz'
    image([('/full', 1, b'x'*4096)])
    before = disk.read_bytes()
    run('append /full y', 1)
    assert disk.read_bytes() == before and run('cat /full') == b'x'*4096
    image([(f'/f{i}', 1, b'') for i in range(63)])
    run('touch /overflow', 1)
    run('rm /f31; touch /reused')
    assert b'64 used, 0 free' in run('df')
    assert run('cat /f31', 1)
    assert run('cat /reused') == b''

for command in ('shutdown', 'reboot'):
    result = subprocess.run([EXE, '-c', command], capture_output=True, timeout=5)
    assert result.returncode == 1 and b'unavailable' in result.stdout
assert subprocess.check_output([EXE, '-c', 'clear']) == b'\x1b[2J\x1b[H'
assert re.fullmatch(rb'\d+ seconds\n', subprocess.check_output([EXE, '-c', 'uptime']))
start = time.monotonic()
assert subprocess.run([EXE, '-c', 'sleep 1'], capture_output=True).returncode == 0
assert time.monotonic()-start >= .9
for value in ('-1', '1.5', '86401', '999999999999999', '""'):
    assert subprocess.run([EXE, '-c', 'sleep '+value], capture_output=True).returncode == 2
print('Ush tools: PASS (binary text tools, counts/search, append/delete/reclaim, platform bounds)')
