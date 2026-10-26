"""Exercise the real Ush/VCS assembly adapter against persistent UXFS images."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume', root/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
exe = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as work:
    disk = Path(work)/'vcs.uxfs'
    def seed(a,b):
        raw = bytearray(fmt.image())
        for i,(name,kind,data) in enumerate([('/a',1,a),('/b',1,b),('/dir',2,b'')],1):
            offset = 512+i*fmt.NODE
            raw[offset:offset+len(name)+1] = name.encode()+b'\0'
            struct.pack_into('<QQ',raw,offset+240,kind,len(data))
            raw[offset+256:offset+256+len(data)] = data
        struct.pack_into('<Q',raw,24,fmt.checksum(raw[512:fmt.BANK*512]))
        struct.pack_into('<Q',raw,32,0)
        struct.pack_into('<Q',raw,32,fmt.checksum(raw[:512]))
        disk.write_bytes(raw)
    def run(command,status=0):
        before = disk.read_bytes()
        result = subprocess.run([exe,'--disk',str(disk),'-c',command],capture_output=True,timeout=10)
        assert result.returncode == status,(command,result)
        assert disk.read_bytes() == before,'diff modified the volume'
        return result.stdout
    seed(b'one\ntwo\n',b'one\nthree\n')
    assert run('vcs diff /a /b',1) == b'--- FILE1\n+++ FILE2\n one\n-two\n+three\n'
    assert run('vcs diff /a /a') == b''
    assert run('vcs diff ./a /b; status') .endswith(b'1\n')
    assert run('vcs diff /a /a && echo equal') == b'equal\n'
    assert run('vcs diff /a /b || echo changed').endswith(b'changed\n')
    for cmd in ['vcs','vcs help','vcs --help']:
        assert b'Usage: vcs diff' in run(cmd)
    for cmd in ['vcs nonsense','vcs diff','vcs diff /a','vcs diff /a /b extra',
                'vcs diff /missing /b','vcs diff /a /missing','vcs diff /dir /b',
                'vcs diff /a /dir','vcs commit','vcs --help extra']:
        assert b'vcs:' in run(cmd,2)
    seed(b'',b'last')
    assert run('vcs diff /a /b',1) == b'--- FILE1\n+++ FILE2\n+last\n\\ No newline at end of file\n'
    seed(b'x\r\n\x1b[2J\x00\\\xff',b'')
    assert run('vcs diff /a /b',1) == b'--- FILE1\n+++ FILE2\n-x\\x0d\n-\\x1b[2J\\x00\\x5c\\xff\n\\ No newline at end of file\n'
    seed(b'',b'')
    assert run('vcs diff /a /b') == b''
    seed(b'a\n'*257,b'')
    assert b'256 lines' in run('vcs diff /a /b',2)
    seed(b'a\n'*256,b'b\n'*256)
    result = run('vcs diff /a /b',1)
    assert result == b'--- FILE1\n+++ FILE2\n'+b'-a\n'*256+b'+b\n'*256
    seed(b'\x00'*4096,b'')
    assert run('vcs diff /a /b',1) == b'--- FILE1\n+++ FILE2\n-'+b'\\x00'*4096+b'\n\\ No newline at end of file\n'
    result = subprocess.run([exe,'-c','vcs diff a b'],capture_output=True,timeout=10)
    assert result.returncode == 2 and b'vcs:' in result.stdout
    seed(b'keep old',b'keep new')
    initialized = subprocess.run([exe,'--disk',str(disk),'-c','vcs init /dir'],
                                 capture_output=True,timeout=10)
    assert initialized.returncode == 0 and b'initialized repository' in initialized.stdout
    assert run('cat /dir/.vcs/format') == b'UVCSREP1'+struct.pack('<QQQ',2,0,0)
    assert b'already initialized' in run('cd /dir; vcs init')
    assert run('cat /a; cat /b') == b'keep oldkeep new'
    for command in ['vcs init /a','vcs init /missing','vcs init /dir extra']:
        assert b'vcs:' in run(command,2)
    initialized = subprocess.run([exe,'--disk',str(disk),'-c','vcs init'],
                                 capture_output=True,timeout=10)
    assert initialized.returncode == 0
    assert b'already initialized' in run('vcs init /')
print('Ush VCS: PASS (UXFS paths, exact output, statuses/chaining, escaping, bounds, read-only persistence)')
