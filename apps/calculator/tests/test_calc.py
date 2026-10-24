"""Exercise the actual assembly executable; no third-party packages."""
import random
import subprocess
import sys
from pathlib import Path

exe = str(Path(sys.argv[1]).resolve())
MASK = (1 << 64) - 1

def signed(n):
    n &= MASK
    return n - (1 << 64) if n >> 63 else n

def check(expr, expected=None, status=0, base=10):
    flag = {10: '-d', 16: '-x', 2: '-b'}[base]
    result = subprocess.run([exe, flag, expr], capture_output=True, text=True, timeout=3)
    assert result.returncode == status, (expr, result.returncode, result.stderr)
    if status:
        assert result.stderr.startswith('calc: ') and not result.stdout, (expr, result)
    else:
        text = str(signed(expected)) if base == 10 else format(expected & MASK, 'x' if base == 16 else 'b')
        assert result.stdout == text + '\n' and not result.stderr, (expr, result.stdout, text)

vectors = {
    '0': 0, '42': 42, '2+3*4': 14, '(2+3)*4': 20,
    '20-3-2': 15, '100/5/2': 10, '-7/3': -2, '-7%3': -1,
    '7%-3': 1, '0xff & 0b1010': 10, '1 | 2 ^ 3 & 4': 3,
    '1+2<<3': 24, '32>>1+2': 4, '~0': -1, '-~+1': 2,
    '0XfF + 0B10': 257, '18446744073709551615': -1,
    '18446744073709551615+1': 0, '0xffffffffffffffff>>63': 1,
    '1<<63': -(1 << 63), '-9223372036854775808': -(1 << 63),
    ' \t2\n+\r3 ': 5, '8/(-2)': -4, '0009': 9,
}
for expr, value in vectors.items():
    for base in (10, 16, 2):
        check(expr, value, base=base)
for expr in ('()', '1+', '*2', '2 3', '(1', '1)', '0x', '0b',
             '0b2', '0xg', '0b102', '1&&2', '1||2', '1<2', '1>>>2',
             '1.5', 'hello', '2**3', '1\x0b2'):
    check(expr, status=1)
for expr in ('18446744073709551616', '0x10000000000000000', '0b1' + '0'*64):
    check(expr, status=2)
for expr in ('1/0', '1%0', '0x8000000000000000/-1', '0x8000000000000000%-1'):
    check(expr, status=3)
for expr in ('1<<64', '1>>-1', '1<<0xffffffffffffffff'):
    check(expr, status=4)
check('('*65 + '1' + ')'*65, status=5)
check('-'*65 + '1', status=5)
check('('*60 + '1' + ')'*60, 1)
check('+'.join(['1']*100), 100)

rng = random.Random(20261023)
def expression(depth):
    if depth == 0 or rng.randrange(4) == 0:
        value = rng.getrandbits(64)
        return hex(value), signed(value)
    left, a = expression(depth-1)
    if rng.randrange(5) == 0:
        op = rng.choice(['-', '~', '+'])
        return f'{op}({left})', signed(-a if op == '-' else ~a if op == '~' else a)
    op = rng.choice(['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>'])
    right, b = expression(depth-1)
    if op in ('<<', '>>'):
        b = rng.randrange(64)
        right = str(b)
    if op in ('/', '%') and (b == 0 or (a == -(1 << 63) and b == -1)):
        right, b = '1', 1
    if op in ('/', '%'):
        q = abs(a)//abs(b) * (-1 if (a < 0) != (b < 0) else 1)
        value = q if op == '/' else a-q*b
    else:
        value = {'+': lambda: a+b, '-': lambda: a-b, '*': lambda: a*b,
                 '&': lambda: a&b, '|': lambda: a|b, '^': lambda: a^b,
                 '<<': lambda: a<<b, '>>': lambda: (a&MASK)>>b}[op]()
    return f'({left} {op} {right})', signed(value)
for _ in range(400):
    expr, value = expression(3)
    check(expr, value, base=rng.choice([10,16,2]))
for args in (['-z', '1'], ['1','2'], ['-x'], ['-d',''], ['-d',' ']):
    result = subprocess.run([exe, *args], capture_output=True, timeout=3)
    assert result.returncode and result.stderr
result = subprocess.run([exe, '--help'], capture_output=True, text=True, timeout=3)
assert result.returncode == 0 and 'Functions:' in result.stdout and 'Commands:' in result.stdout
print('Calculator: PASS (fixed vectors, errors, depth bounds, 400 generated expressions)')
