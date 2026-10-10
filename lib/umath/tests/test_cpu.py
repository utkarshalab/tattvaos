"""cpuid: the feature-detection API, and the SSE2 fallbacks bit-for-bit
against the native fast paths.

Two copies of the library are loaded so each has its own feature state:
`native` uses everything the CPU has, `base` is restricted to the x86-64
baseline (umath_cpu_restrict(0)), which sends every guarded instruction
through its cpuid/fallback.asm emulation. Float results are compared as raw
bits, which the tolerance-based reference tests in test_math_fn.py would
not notice; integer and bit operations are checked exactly against Python
by the whole suite's baseline pass (UMATH_CPU_MASK=0, see run_tests.sh).
"""
import ctypes as C
import math
import os
import random
import shutil
import struct
import sys
import tempfile

from umath_ref import D, F, I32, I64, P, U64, Z, Checker, fn

ck = Checker('cpuid')
random.seed(11)

tmp = tempfile.mkdtemp()
shutil.copy(sys.argv[1], os.path.join(tmp, 'umath_base.so'))
native = C.CDLL(sys.argv[1])
base = C.CDLL(os.path.join(tmp, 'umath_base.so'))
shutil.rmtree(tmp, ignore_errors=True)      # the mapping stays valid

NAMES = ['sse3', 'ssse3', 'sse41', 'sse42', 'popcnt', 'lzcnt', 'bmi1', 'bmi2',
         'avx', 'avx2', 'fma', 'avx512', 'prfchw']
# /proc/cpuinfo flags for each bit (Linux also clears AVX flags the OS has not enabled)
LINUX = [['pni'], ['ssse3'], ['sse4_1'], ['sse4_2'], ['popcnt'], ['abm'], ['bmi1'], ['bmi2'],
         ['avx'], ['avx2'], ['fma'], ['avx512f', 'avx512bw', 'avx512vl'], ['3dnowprefetch']]
ALL = (1 << len(NAMES)) - 1

# --- API ---------------------------------------------------------------------
init = fn(native, 'umath_cpu_init', U64)
features = fn(native, 'umath_cpu_features', U64)
has = fn(native, 'umath_cpu_has', I32, I32)
restrict = fn(native, 'umath_cpu_restrict', U64, U64)

mask = init()
ck.check('cpu_init is idempotent', init() == mask and features() == mask)
ck.check('cpu_init sets only defined bits', mask & ~ALL == 0, hex(mask))
ck.check('cpu_has agrees with the mask',
         all(has(b) == (mask >> b & 1) for b in range(len(NAMES))))
try:
    flags = set()
    with open('/proc/cpuinfo') as cpuinfo:
        for line in cpuinfo:
            if line.startswith('flags'):
                flags = set(line.split(':', 1)[1].split())
                break
except OSError:
    flags = None
if flags:
    for b, (name, want) in enumerate(zip(NAMES, LINUX)):
        ck.check(f'cpu detects {name} like the kernel does',
                 bool(mask >> b & 1) == all(f in flags for f in want),
                 f'umath={mask >> b & 1} linux={[f in flags for f in want]}')

ck.check('cpu_restrict(0) leaves the baseline', restrict(0) == 0 and features() == 0)
ck.check('cpu_has is 0 under the baseline', not any(has(b) for b in range(len(NAMES))))
for _ in range(20):
    m = random.getrandbits(len(NAMES))
    ck.check('cpu_restrict only removes features', restrict(m) == mask & m, hex(m))
ck.check('cpu_restrict(-1) restores everything', restrict(2 ** 64 - 1) == mask and features() == mask)
ck.check('the base copy has its own state',
         fn(base, 'umath_cpu_restrict', U64, U64)(0) == 0 and features() == mask)

# --- fallbacks vs native, bit for bit ----------------------------------------
inf, nan = math.inf, math.nan


def inputs(n, f32):
    big, tiny = (3e38, 1e-44) if f32 else (1e308, 5e-323)
    pool = [0.0, -0.0, inf, -inf, nan, -nan, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 0.49999997,
            1.0, -1.0, tiny, -tiny, big, -big, 2.0 ** 23, 2.0 ** 52, -(2.0 ** 52) + 0.5,
            2.0 ** 63, -(2.0 ** 63), 2.0 ** 31, -(2.0 ** 31), 8388607.5, 4503599627370495.5]
    out = []
    for _ in range(n):
        r = random.random()
        if r < 0.25:
            out.append(random.choice(pool))
        elif r < 0.45:
            out.append(random.randrange(-40, 40) / 2 + random.choice([0, 0, 1e-9, -1e-9]))
        elif r < 0.6:
            out.append(random.uniform(-100, 100))
        elif r < 0.8:
            out.append(random.choice([1, -1]) * 10.0 ** random.uniform(-45 if f32 else -320, 38 if f32 else 308))
        else:   # raw bit patterns: every exponent, signalling NaNs, payloads
            out.append(('raw', random.getrandbits(32 if f32 else 64)))
    return out


def to_buf(vals, f32):
    t = C.c_uint32 if f32 else C.c_uint64
    fmt = '<f' if f32 else '<d'
    words = []
    for v in vals:
        if isinstance(v, tuple):
            words.append(v[1])
        else:
            try:
                words.append(struct.unpack('<I' if f32 else '<Q', struct.pack(fmt, v))[0])
            except OverflowError:
                words.append(0x7F800000 if v > 0 else 0xFF800000)
    return (t * max(len(words), 1))(*words)


def bits(x):
    return struct.pack('<d', x) if isinstance(x, float) else x


def same(name, a, b, detail):
    ck.check(f'{name} fallback matches native bit for bit', a == b, detail)


def scalar_arg(word, f32):
    raw = struct.pack('<I' if f32 else '<Q', word)
    return struct.unpack('<f' if f32 else '<d', raw)[0]


SIZES = (0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 33, 300)
for sfx, t, it, f32 in (('_f64', D, I64, False), ('_f32', F, I32, True)):
    w = 4 if f32 else 8
    unary = [f'umath_{n}{sfx}' for n in ('sin', 'cos', 'exp', 'floor', 'ceil', 'round', 'trunc')]
    rounding = [f'umath_{n}{sfx}' for n in ('floor', 'ceil', 'round', 'trunc')]
    ibits = 'i32' if f32 else 'i64'
    for name in unary:
        sc = [fn(lib, name, t, t) for lib in (native, base)]
        ar = [fn(lib, name + '_array', None, P, P, Z) for lib in (native, base)]
        ip = [fn(lib, name + '_inplace', None, P, Z) for lib in (native, base)]
        for n in SIZES:
            src = to_buf(inputs(n, f32), f32)
            outs = []
            for a, i in zip(ar, ip):
                dst = (C.c_ubyte * (n * w + 1))()
                a(C.addressof(dst), C.addressof(src), n)
                buf = (C.c_ubyte * (n * w + 1)).from_buffer_copy(bytes(src)[:n * w] + b'\0')
                i(C.addressof(buf), n)
                outs.append((bytes(dst), bytes(buf)))
            same(name + '_array', outs[0][0], outs[1][0], f'n={n}')
            same(name + '_inplace', outs[0][1], outs[1][1], f'n={n}')
            ws = list(src)[:n]
            for word in ws:
                x = scalar_arg(word, f32)
                same(name, bits(sc[0](x)), bits(sc[1](x)), f'x={word:#x}')
    for name in rounding:
        pairs = [
            ('_fractional', t, (t,)),
            ('_is_integer', I32, (t,)),
            (f'_to_{ibits}', it, (t,)),
        ]
        for tail, rt, args in pairs:
            if not hasattr(native, name + tail):     # round has no _is_integer
                continue
            fs =[fn(lib, name + tail, rt, *args) for lib in (native, base)]
            for word in list(to_buf(inputs(400, f32), f32)):
                x = scalar_arg(word, f32)
                same(name + tail, bits(fs[0](x)), bits(fs[1](x)), f'x={word:#x}')
        conv = [fn(lib, f'{name}_to_{ibits}_array', None, P, P, Z) for lib in (native, base)]
        for n in SIZES:
            src = to_buf(inputs(n, f32), f32)
            outs = []
            for f in conv:
                dst = (C.c_ubyte * (n * w + 1))()
                f(C.addressof(dst), C.addressof(src), n)
                outs.append(bytes(dst))
            same(f'{name}_to_{ibits}_array', outs[0], outs[1], f'n={n}')
    wm = [fn(lib, f'umath_round{sfx}_with_mode', t, t, I32) for lib in (native, base)]
    for word in list(to_buf(inputs(400, f32), f32)):
        x = scalar_arg(word, f32)
        for mode in range(4):
            same(f'umath_round{sfx}_with_mode', bits(wm[0](x, mode)), bits(wm[1](x, mode)),
                 f'x={word:#x} mode={mode}')
    pw = [fn(lib, f'umath_pow{sfx}', t, t, t) for lib in (native, base)]
    pa = [fn(lib, f'umath_pow{sfx}_array', None, P, P, P, Z) for lib in (native, base)]
    for n in SIZES:
        xs, ys = to_buf(inputs(n, f32), f32), to_buf(inputs(n, f32), f32)
        outs = []
        for f in pa:
            dst = (C.c_ubyte * (n * w + 1))()
            f(C.addressof(dst), C.addressof(xs), C.addressof(ys), n)
            outs.append(bytes(dst))
        same(f'umath_pow{sfx}_array', outs[0], outs[1], f'n={n}')
        for a, b in zip(list(xs)[:n], list(ys)[:n]):
            x, y = scalar_arg(a, f32), scalar_arg(b, f32)
            same(f'umath_pow{sfx}', bits(pw[0](x, y)), bits(pw[1](x, y)), f'x={a:#x} y={b:#x}')

ck.finish()
