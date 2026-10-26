"""Pending end-to-end Ush tests for cherry-pick and revert."""
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
    disk = Path(work)/'pick.uxfs'
    disk.write_bytes(fmt.image())

    def run(command, status=0):
        result = subprocess.run([exe, '--disk', str(disk), '-c', command],
                                capture_output=True, timeout=10)
        assert result.returncode == status, (command, result)
        return result.stdout

    run('mkdir repo; vcs init repo; write repo/file base; cd repo; vcs commit base')
    run('write repo/file source; cd repo; vcs commit source')
    run('cd repo; vcs checkout 0000000000000001 --force')
    assert run('cd repo; vcs cherry-pick 0000000000000002') == b'Operation complete\n'
    assert run('cat repo/file') == b'source'
    assert run('cd repo; vcs revert 0000000000000003') == b'Operation complete\n'
    assert run('cat repo/file') == b'base'
    run('write repo/file ours; cd repo; vcs commit ours')
    assert b'Operation paused' in run('cd repo; vcs cherry-pick 0000000000000002')
    assert run('cd repo; vcs conflicts') == b'file\n'
    pending = disk.read_bytes()
    run('cd repo; vcs commit bypass', 2)
    assert disk.read_bytes() == pending
    run('write repo/file resolved; cd repo; vcs resolve file')
    assert run('cd repo; vcs cherry-pick --continue') == b'Operation complete\n'
    assert run('cat repo/file') == b'resolved'
    run('cd repo; vcs checkout 0000000000000005 --force')
    run('cd repo; vcs cherry-pick 0000000000000002')
    assert run('cd repo; vcs cherry-pick --abort') == b'Operation aborted\n'
    assert run('cat repo/file') == b'ours'
    run('rm repo/file; cd repo; vcs commit deletion')
    run('cd repo; vcs cherry-pick 0000000000000001')
    assert run('cat repo/file') == b'base'
    run('cd repo; vcs revert 0000000000000001')
    run('cat repo/file', 2)

print('Ush pick: PASS (cherry-pick, revert, conflicts, abort, root replay)')
