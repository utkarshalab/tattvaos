"""Differential checks execute the NASM engine; Python supplies the oracle."""
import ctypes as C
import random
import sys

lib = C.CDLL(sys.argv[1])
U = C.c_uint64
class Request(C.Structure):
    _fields_ = [(n, U) for n in ('old', 'old_size', 'new', 'new_size',
                               'scratch', 'scratch_size', 'output', 'capacity')]
lib.diff_probe.argtypes = [C.POINTER(Request), C.POINTER(U)]
lib.diff_probe.restype = U
SIZE = 8192 + 257*257*4

def lines(data):
    parts = data.split(b'\n')
    return [p+b'\n' for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])

def oracle(a, b):
    x, y = lines(a), lines(b)
    m, n = len(x), len(y)
    dp = [[0]*(n+1) for _ in range(m+1)]
    for i in range(m-1, -1, -1):
        for j in range(n-1, -1, -1):
            dp[i][j] = 1+dp[i+1][j+1] if x[i] == y[j] else max(dp[i+1][j], dp[i][j+1])
    result = []
    i = j = ao = bo = 0
    while i < m or j < n:
        if i < m and j < n and x[i] == y[j]:
            size = len(x[i]); result.append((0, ao, bo, size))
            i += 1; j += 1; ao += size; bo += size
        elif i < m and (j == n or dp[i+1][j] >= dp[i][j+1]):
            size = len(x[i]); result.append((1, ao, bo, size))
            i += 1; ao += size
        else:
            size = len(y[j]); result.append((2, ao, bo, size))
            j += 1; bo += size
    return result

def check(a, b, capacity=512, scratch_size=SIZE, mutate=None, expected_status=0):
    old, new = C.create_string_buffer(a), C.create_string_buffer(b)
    scratch = C.create_string_buffer(SIZE+32)
    output = C.create_string_buffer(512*32+32)
    C.memset(scratch, 0xA5, len(scratch))
    C.memset(output, 0x5A, len(output))
    req = Request(C.addressof(old), len(a), C.addressof(new), len(b),
                  C.addressof(scratch)+16, scratch_size, C.addressof(output)+16, capacity)
    if mutate:
        mutate(req)
    count = U(999)
    status = lib.diff_probe(C.byref(req), C.byref(count))
    assert status == expected_status, (status, expected_status, a[:60], b[:60])
    assert scratch.raw[:16] == scratch.raw[-16:] == b'\xa5'*16
    assert output.raw[:16] == output.raw[-16:] == b'Z'*16
    if status:
        assert output.raw == b'Z'*len(output)
        if status == 3 and scratch_size == SIZE:
            assert count.value == len(oracle(a,b))
        else:
            assert count.value == 0
        return
    expected = oracle(a,b)
    actual = [tuple((U*4).from_buffer(output,16+i*32)) for i in range(count.value)]
    assert actual == expected, (actual, expected)
    assert output.raw[16+count.value*32:] == b'Z'*(len(output)-16-count.value*32)
    reconstructed = b''.join(a[ao:ao+n] if k == 0 else b[bo:bo+n]
                             for k,ao,bo,n in actual if k != 1)
    assert reconstructed == b
    assert C.string_at(old,len(a)) == a and C.string_at(new,len(b)) == b

vectors = [b'', b'a', b'a\n', b'\n', b'\n\n', b'a\r\nb\r\n', b'a\nb\n',
           b'\x00\xff\n', 'नमस्ते\n'.encode(), b'a\nb\na\n', b'b\na\nb']
for a in vectors:
    for b in vectors:
        check(a,b)
rng = random.Random(2718)
for _ in range(1800):
    a = b''.join(rng.choice(vectors) for _ in range(rng.randrange(16)))
    b = b''.join(rng.choice(vectors) for _ in range(rng.randrange(16)))
    check(a,b)
check(b'a\n'*256,b'b\n'*256)
check(b'x'*1048576,b'x'*1048575+b'y')
check(b'a\n'*257,b'',expected_status=8)
check(b'',b'a\n'*257,expected_status=8)
check(b'x'*1048577,b'',expected_status=8)
check(b'a',b'b',capacity=1,expected_status=3)
check(b'a',b'a',capacity=1)
check(b'',b'',capacity=0,mutate=lambda r:setattr(r,'output',0))
check(b'',b'',mutate=lambda r:(setattr(r,'old',0),setattr(r,'new',0)))
check(b'a',b'b',scratch_size=SIZE-1,expected_status=3)
for field in ('old','new','scratch','output'):
    check(b'a',b'b',mutate=lambda r,f=field:setattr(r,f,0),expected_status=8)
count = U(77)
assert lib.diff_probe(None,C.byref(count)) == 8 and count.value == 0
assert lib.diff_trees() == lib.diff_emit() == 9
print('VCS diff: PASS (1800 generated pairs, exact scripts/reconstruction, limits, atomic errors, canaries and native ABI)')
