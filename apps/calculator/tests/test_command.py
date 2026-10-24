import subprocess
import sys
from pathlib import Path
exe = str(Path(sys.argv[1]).resolve())
for args, status, output in [
    (['2+3*4'], 0, '14\n'),
    (['-x', '255'], 0, 'ff\n'),
    (['-b', '10'], 0, '1010\n'),
    (['-d', '-9223372036854775808'], 0, '-9223372036854775808\n'),
    (['1/0'], 3, 'calc:'),
    (['-d', '1<<64'], 4, 'calc:'),
    (['sqrt(81)+.5'], 0, '9.5\n'),
    (['--deg', 'sin(30)'], 0, '0.5\n'),
    ([], 1, 'Usage:'),
    (['-z', '1'], 1, 'Usage:'),
    (['-', '1'], 1, 'Usage:'),
    (['1', '2'], 1, 'Usage:'),
]:
    result = subprocess.run([exe, *args], capture_output=True, text=True, timeout=3)
    assert result.returncode == status, (args, result)
    assert result.stdout == output if status == 0 else result.stdout.startswith(output), (args, result)
print('Native command: PASS (frontend callback, output bases, error statuses)')
