"""Shared helpers for the umath ctypes tests (see run_tests.sh)."""
import ctypes as C
import math
import os
import struct
import sys

D, F = C.c_double, C.c_float
I32, I64, U32, U64 = C.c_int32, C.c_int64, C.c_uint32, C.c_uint64
P, Z = C.c_void_p, C.c_size_t


def load():
    """Load the library under test. UMATH_CPU_MASK (e.g. 0 = SSE2 baseline)
    limits the CPU features it may use, to exercise the fallbacks."""
    lib = C.CDLL(sys.argv[1])
    mask = os.environ.get('UMATH_CPU_MASK')
    if mask is not None:
        fn(lib, 'umath_cpu_restrict', C.c_uint64, C.c_uint64)(int(mask, 0) & (2 ** 64 - 1))
    return lib


def fn(lib, name, restype, *argtypes):
    f = getattr(lib, name)
    f.restype = restype
    f.argtypes = list(argtypes)
    return f


def cpu_has(flag):
    try:
        with open('/proc/cpuinfo') as cpuinfo:
            return any(flag in line.split() for line in cpuinfo if line.startswith('flags'))
    except OSError:
        return False


def r32(x):
    """Round a Python float to the nearest float32 (overflow -> +/-Inf)."""
    try:
        return struct.unpack('<f', struct.pack('<f', x))[0]
    except OverflowError:
        return math.copysign(math.inf, x)


def _ordered(bits, sign_bit):
    return -(bits & (sign_bit - 1)) if bits & sign_bit else bits


def ulp_diff(got, want, f32=False):
    """Distance in units in the last place; inf on NaN/Inf mismatch."""
    if f32:
        want = r32(want)
    if math.isnan(got) or math.isnan(want):
        return 0 if math.isnan(got) and math.isnan(want) else math.inf
    if math.isinf(got) or math.isinf(want):
        return 0 if got == want else math.inf
    if f32:
        a = struct.unpack('<I', struct.pack('<f', got))[0]
        b = struct.unpack('<I', struct.pack('<f', want))[0]
        return abs(_ordered(a, 1 << 31) - _ordered(b, 1 << 31))
    a = struct.unpack('<Q', struct.pack('<d', got))[0]
    b = struct.unpack('<Q', struct.pack('<d', want))[0]
    return abs(_ordered(a, 1 << 63) - _ordered(b, 1 << 63))


def same(got, want):
    """Exact equality including NaN == NaN and the sign of zero."""
    if math.isnan(got) or math.isnan(want):
        return math.isnan(got) and math.isnan(want)
    return got == want and math.copysign(1, got) == math.copysign(1, want)


class Checker:
    """Collects failures per test name and prints a short report."""

    def __init__(self, title):
        self.title = title
        self.failures = {}
        self.checks = 0

    def check(self, name, ok, detail=''):
        self.checks += 1
        if not ok:
            self.failures.setdefault(name, []).append(detail)
        return ok

    def finish(self):
        for name, details in self.failures.items():
            print(f'  FAIL {name}: {len(details)} case(s); e.g. {details[0]}')
        status = 'FAILED' if self.failures else 'ok'
        print(f'  {self.title}: {self.checks} checks, {len(self.failures)} failing tests -> {status}')
        sys.exit(1 if self.failures else 0)
