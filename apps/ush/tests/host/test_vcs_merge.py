"""Deferred end-to-end coverage for file-level merge and conflicts."""
from pathlib import Path
import importlib.util
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('mkvolume', root/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)
exe = str(Path(sys.argv[1]).resolve())

with tempfile.TemporaryDirectory() as work:
    disk = Path(work)/'merge.uxfs'
    disk.write_bytes(fmt.image())

    def run(command, status=0):
        result = subprocess.run([exe, '--disk', str(disk), '-c', command],
                                capture_output=True, timeout=10)
        assert result.returncode == status, (command, result)
        return result.stdout

    run('mkdir p; vcs init p; write p/a base; write p/b base; '
        'write p/c "one\ntwo\n"; write p/d "a\nb\nc\n"; cd p; vcs commit base')
    run('cd p; vcs branch main; vcs branch side')
    run('cd p; vcs checkout main --force; write a ours; write c "ONE\ntwo\n"; '
        'write d "X\na\nb\nc\n"; vcs commit ours')
    run('cd p; vcs checkout side --force; write b theirs; write c "one\nTWO\n"; '
        'write d "a\nb\nC\n"; vcs commit theirs')
    run('cd p; vcs checkout main --force; vcs merge side')
    assert run('cd p; vcs conflicts') == b'No unresolved conflicts\n'
    run('cd p; vcs merge --continue merged')
    assert run('cat p/a') == b'ours'
    assert run('cat p/b') == b'theirs'
    assert run('cat p/c') == b'ONE\nTWO\n'
    assert run('cat p/d') == b'X\na\nb\nC\n'
    assert b'branch main 0000000000000004\n' in run('cd p; vcs refs')

    run('cd p; vcs branch other 0000000000000001; vcs checkout other --force; '
        'write a other; vcs commit other-change')
    run('cd p; vcs checkout main --force; write a main-again; vcs commit main-change')
    run('cd p; vcs merge other')
    assert run('cd p; vcs conflicts') == b'a\n'
    run('cd p; vcs merge --abort')
    assert run('cat p/a') == b'main-again'
    run('cd p; vcs merge other')
    run('cd p; write a resolved; vcs resolve a')
    assert run('cd p; vcs conflicts') == b'No unresolved conflicts\n'
    run('cd p; vcs merge --continue resolution')
    assert run('cat p/a') == b'resolved'
    assert run('cd p; vcs status') == b'Working tree clean\n'

    run('write /seed 0123456789abcdef0123456789abcdef; '
        'cd p; vcs identity signer /seed; vcs policy require-signed; '
        'vcs branch signed-side')
    run('cd p; write a main-signed; vcs commit --sign /seed main-signed')
    run('cd p; vcs checkout signed-side --force; write b side-signed; '
        'vcs commit --sign /seed side-signed')
    run('cd p; vcs checkout main --force; vcs merge signed-side')
    run('cd p; vcs merge --continue signed-merge --sign /seed')
    assert run('cd p; vcs verify HEAD').endswith(b'as signer\n')

print('Ush merge: PASS (three-way merge, conflicts, signed continuation, two parents)')
