"""Deferred end-to-end coverage for durable first-parent rebase."""
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
    disk = Path(work)/'rebase.uxfs'
    disk.write_bytes(fmt.image())

    def run(command, status=0):
        result = subprocess.run([exe, '--disk', str(disk), '-c', command],
                                capture_output=True, timeout=10)
        assert result.returncode == status, (command, result)
        return result.stdout

    run('mkdir p; vcs init p; write p/a base; write p/b base; cd p; vcs commit base; '
        'vcs branch main; vcs branch target')
    run('cd p; vcs checkout target --force; write b target; vcs commit target-change')
    run('cd p; vcs checkout main --force; write a source; vcs commit source-change')
    assert b'Rebase complete\n' in run('cd p; vcs rebase target')
    assert run('cat p/a') == b'source'
    assert run('cat p/b') == b'target'
    assert b'branch main 0000000000000004\n' in run('cd p; vcs refs')

    run('cd p; vcs branch left; vcs branch right')
    run('cd p; vcs checkout right --force; write a right; vcs commit right-change')
    run('cd p; vcs checkout left --force; write a left; vcs commit left-change')
    assert b'Rebase paused' in run('cd p; vcs rebase right')
    assert run('cd p; vcs conflicts') == b'a\n'
    run('cd p; write a resolved; vcs resolve a; vcs rebase --continue')
    assert run('cat p/a') == b'resolved'
    assert run('cd p; vcs status') == b'Working tree clean\n'

    run('write /seed 0123456789abcdef0123456789abcdef; '
        'cd p; vcs identity signer /seed; vcs policy require-signed; '
        'vcs branch signed-source; vcs branch signed-target')
    run('cd p; vcs checkout signed-target --force; write b signed-target; '
        'vcs commit --sign /seed signed-target')
    run('cd p; vcs checkout signed-source --force; write a signed-source; '
        'vcs commit --sign /seed signed-source')
    assert b'Rebase complete\n' in run('cd p; vcs rebase signed-target --sign /seed')
    assert run('cd p; vcs verify HEAD').endswith(b'as signer\n')

print('Ush rebase: PASS (ordered replay, conflicts, signed replay, branch reattachment)')
