"""Pending end-to-end Ush coverage for repository-aware diff modes."""
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
    disk = Path(work)/'repo-diff.uxfs'
    disk.write_bytes(fmt.image())

    def run(command, status=0):
        result = subprocess.run([exe, '--disk', str(disk), '-c', command],
                                capture_output=True, timeout=10)
        assert result.returncode == status, (command, result)
        return result.stdout

    run('mkdir p; vcs init p; write p/a "one\ntwo\n"; write p/c old')
    unborn = run('cd p; vcs diff', 1)
    assert b'--- /dev/null\n+++ b/a\n' in unborn
    run('cd p; vcs commit base')
    assert run('cd p; vcs diff') == b''

    run('write p/a "ONE\ntwo\n"; write p/b added; rm p/c')
    working = run('cd p; vcs diff', 1)
    assert b'--- a/a\n+++ b/a\n' in working
    assert b'--- /dev/null\n+++ b/b\n' in working
    assert b'--- a/c\n+++ /dev/null\n' in working

    run('cd p; vcs add a c')
    staged = run('cd p; vcs diff --staged', 1)
    assert b'+++ b/a\n' in staged and b'--- a/c\n' in staged
    assert b'b/b\n' not in staged
    run('cd p; vcs commit staged')

    commits = run('cd p; vcs diff 0000000000000001 0000000000000002', 1)
    assert b'--- a/a\n+++ b/a\n' in commits
    assert b'--- a/c\n+++ /dev/null\n' in commits
    assert b'b/b\n' not in commits

    run('write /left x; write /right y')
    assert run('vcs diff /left /right', 1).startswith(b'--- FILE1\n+++ FILE2\n')

print('Ush repository diff: PASS (working, staged, commits, additions/deletions)')
