"""Pending end-to-end Ush tests for local repository history."""
from pathlib import Path
import importlib.util
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume',root/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
exe = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as work:
    disk = Path(work)/'history.uxfs'
    disk.write_bytes(fmt.image())
    def run(command,status=0):
        result = subprocess.run([exe,'--disk',str(disk),'-c',command],capture_output=True,timeout=10)
        assert result.returncode == status,(command,result)
        return result.stdout
    run('mkdir project; mkdir project/sub; vcs init project; write project/a first')
    assert run('cd project/sub; vcs status') == b'No commits yet\nA a\n'
    assert run('cd project; vcs commit "first snapshot"') == b'Committed 0000000000000001\n'
    assert run('cd project; vcs check') == b'Integrity OK\n'
    run('write /seed 0123456789abcdef0123456789abcdef')
    assert run('cd project; vcs identity alice /seed') == b'identity alice\n'
    identity = run('cd project; vcs identity')
    assert identity.startswith(b'identity alice as ') and len(identity) == 83
    assert run('cd project; vcs sign HEAD /seed') == b'Signed 0000000000000001 as alice\n'
    assert run('cd project; vcs verify HEAD') == b'Verified 0000000000000001 as alice\n'
    run('write /wrong fedcba9876543210fedcba9876543210')
    before_sign = disk.read_bytes()
    run('cd project; vcs sign HEAD /wrong',2)
    assert disk.read_bytes() == before_sign
    signed_disk = disk.read_bytes()
    run('write project/.vcs/s0000000000000001 broken')
    run('cd project; vcs verify HEAD',2)
    disk.write_bytes(signed_disk)
    clean_disk = disk.read_bytes()
    run('write project/.vcs/b0000000000000101 other')  # same size: SHA-256 must catch it
    run('cd project; vcs check', 2)
    disk.write_bytes(clean_disk)
    assert run('cd project; vcs status') == b'Working tree clean\n'
    before = disk.read_bytes()
    assert run('cd project; vcs commit again') == b'Nothing to commit\n'
    assert disk.read_bytes() == before
    run('write project/a changed; write project/sub/b new')
    assert run('cd project; vcs status') == b'M a\nA sub/b\n'
    run('cd project/sub; vcs commit "second snapshot"')
    run('rm project/a')
    assert run('cd project; vcs status') == b'D a\n'
    run('cd project; vcs commit deletion')
    before = disk.read_bytes()
    assert run('cd project; vcs log --oneline') == (b'commit 0000000000000003 deletion\n'
        b'commit 0000000000000002 second snapshot\ncommit 0000000000000001 first snapshot\n')
    assert run('cd project; vcs show HEAD') == (b'commit 0000000000000003\n'
        b'    deletion\nfiles:\n  3 sub/b\n')
    assert run('cd project; vcs show 0000000000000001') == (b'commit 0000000000000001\n'
        b'    first snapshot\nfiles:\n  5 a\n')
    run('cd project; vcs branch old 0000000000000001; vcs tag release')
    refs = run('cd project; vcs refs')
    assert refs == (b'branch old 0000000000000001\n'
                    b'tag release 0000000000000003\n')
    # Checkout is destructive only with --force and attaches branch commits.
    before = disk.read_bytes()
    run('cd project; vcs checkout old',2)
    assert disk.read_bytes() == before
    assert run('cd project; vcs checkout old --force') == b'Checked out 0000000000000001\n'
    assert run('cat project/a') == b'first'
    run('write project/a branch; cd project; vcs commit branch-change')
    assert b'branch old 0000000000000004\n' in run('cd project; vcs refs')
    assert run('cd project; vcs checkout 0000000000000003 --force') == b'Checked out 0000000000000003\n'
    assert run('cd project; vcs status') == b'Working tree clean\n'
    run('cd project; vcs restore sub/b')
    assert run('cat project/sub/b') == b'new'
    run('cd project; vcs branch -d old')
    run('cd project; vcs tag -d release')
    assert run('cd project; vcs refs') == b''
    assert disk.read_bytes() == before
    assert b'already initialized' in run('vcs init project')
    run('write project/.vcsignore "ignored\nbuild/\n"; write project/ignored no; '
        'mkdir project/build; write project/build/output no')
    status = run('cd project; vcs status')
    assert b'A .vcsignore\n' in status and b'ignored' not in status and b'build/output' not in status
    for command in ['vcs status','vcs log','vcs commit message',
                    'cd project; vcs commit','cd project; vcs commit ""',
                    'cd project; vcs status extra','cd project; vcs log extra']:
        before = disk.read_bytes()
        assert b'vcs:' in run(command,2)
        assert disk.read_bytes() == before
    run('mkdir empty; vcs init empty; cd empty; vcs commit initial')
    assert run('cd empty; vcs status') == b'Working tree clean\n'
    run('write empty/file changed')
    run('cd empty; vcs commit -m "Title" -m "Body paragraph"')
    assert run('cd empty; vcs log').startswith(
        b'commit 0000000000000002\n    Title\n    \n    Body paragraph\n\n')
    assert run('cd empty; vcs log --oneline').startswith(
        b'commit 0000000000000002 Title\\x0a\\x0aBody paragraph\n')
    # A UXFS file carries real LF bytes without shell escape interpretation.
    run('write /message "File title\n\nSecond line\n"; write empty/file next')
    run('cd empty; vcs commit -F /message')
    assert run('cd empty; vcs log').startswith(
        b'commit 0000000000000003\n    File title\n    \n    Second line\n\n')
    run('write /message "x\r\ny"; write empty/file third')
    run('cd empty; vcs commit -F /message')
    assert b'    x\\x0d\n    y\n' in run('cd empty; vcs log')
    run('touch /empty-message; write /long-message "'+'x'*216+'"')
    for command in ['vcs commit -m','vcs commit -m a -m',
                    'vcs commit -m a junk b','vcs commit -F /missing',
                    'vcs commit -F /empty-message','vcs commit -F /long-message',
                    'vcs commit -F /message extra','vcs log --wrong',
                    'vcs show 1','vcs show 0000000000000000',
                    'vcs show 0000000000009999','vcs show HEAD extra',
                    'vcs checkout HEAD --force','vcs checkout 0000000000000001',
                    'vcs branch bad/name','vcs tag .hidden','vcs branch -d missing',
                    'vcs commit -m "'+'x'*214+'" -m y']:
        before = disk.read_bytes()
        run('cd empty; '+command,2)
        assert disk.read_bytes() == before
    run('mkdir staged; vcs init staged; write staged/a one; write staged/b one; '
        'cd staged; vcs commit initial')
    run('write staged/a two; write staged/b two; cd staged; vcs add a')
    assert run('cd staged; vcs staged') == b'a\n'
    run('cd staged; vcs commit staged-only')
    assert run('cd staged; vcs staged') == b'No staged paths\n'
    assert run('cd staged; vcs status') == b'M b\n'
    run('cd staged; vcs add --all; vcs reset b')
    assert run('cd staged; vcs staged') == b'No staged paths\n'
    run('cd staged; vcs add b; vcs reset --all')
    assert run('cd staged; vcs staged') == b'No staged paths\n'
    run('cd staged; vcs add --all; vcs commit indexed-rest')
    run('mkdir signed; vcs init signed; write signed/file one; '
        'cd signed; vcs identity signer /seed')
    run('cd signed; vcs commit --sign /seed initial')
    assert run('cd signed; vcs verify HEAD') == b'Verified 0000000000000001 as signer\n'
    assert run('cd signed; vcs policy require-signed') == b'signed commits required\n'
    run('write signed/file two')
    before = disk.read_bytes()
    run('cd signed; vcs commit unsigned',2)
    assert disk.read_bytes() == before
    run('cd signed; vcs commit --sign /seed -m second -m body')
    run('cd signed; vcs identity --rotate successor /wrong')
    assert run('cd signed; vcs verify 0000000000000001').endswith(b'as signer\n')
    run('write signed/file three; cd signed; vcs commit --sign /wrong third')
    assert run('cd signed; vcs verify HEAD').endswith(b'as successor\n')
    assert run('cd signed; vcs check --signatures').count(b'Verified ') == 3
    run('cd signed; vcs identity --revoke signer')
    run('cd signed; vcs verify 0000000000000001',2)
    run('cd signed; vcs check --signatures',2)
    run('cd signed; vcs policy allow-unsigned')
    assert run('cd signed; vcs policy') == b'unsigned commits allowed\n'
print('Ush history: PASS (snapshots, signed identity, multiline messages, log and errors)')
