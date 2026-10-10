"""bits: property tests against Python integer reference implementations."""
import ctypes as C
import random

from umath_ref import I32, P, U64, Checker, cpu_has, fn, load

lib = load()
ck = Checker('bits')
random.seed(5)
M = lambda w: (1 << w) - 1


def s(v, w):
    v &= M(w)
    return v - (1 << w) if v >> (w - 1) else v


def T(name, nargs, ref, gen, wout=64, n=2000):
    """Compare umath_<name>(args...) & mask(wout) with ref(args...) on n inputs."""
    f = fn(lib, name, U64, *([U64] * nargs))
    for _ in range(n):
        a = gen()
        want = ref(*a)
        if want is None:
            continue
        got = f(*a) & M(wout)
        if not ck.check(name, got == want & M(wout), f'{tuple(hex(x) for x in a)} -> {hex(got)}, want {hex(want & M(wout))}'):
            break


r64 = lambda: random.choice([0, 1, M(64), 1 << 63, (1 << 63) - 1, random.getrandbits(64), random.getrandbits(random.randrange(1, 65))])
r32 = lambda: r64() & M(32)
pc = lambda v: bin(v).count('1')


def ctz(v, w):
    v &= M(w)
    return w if v == 0 else (v & -v).bit_length() - 1


for w in (8, 16, 32, 64):
    g = lambda w=w: (r64() & M(w),)
    T(f'umath_clz{w}', 1, lambda v, w=w: w - v.bit_length(), g, wout=w)
    T(f'umath_ctz{w}', 1, lambda v, w=w: ctz(v, w), g, wout=w)
    T(f'umath_popcount{w}', 1, pc, g, wout=w)
    T(f'umath_bitrev{w}', 1, lambda v, w=w: int(format(v, f'0{w}b')[::-1], 2), g, wout=w)
for nm in ('u8', 'u16', 'u32', 'u64'):
    w = int(nm[1:])
    T(f'umath_parity_{nm}', 1, lambda v: pc(v) & 1, lambda w=w: (r64() & M(w),), wout=32)
T('umath_clz32_bsr', 1, lambda v: 32 - v.bit_length(), lambda: (r32(),), wout=32)
T('umath_clz64_bsr', 1, lambda v: 64 - v.bit_length(), lambda: (r64(),))
T('umath_ctz32_bsf', 1, lambda v: ctz(v, 32), lambda: (r32(),), wout=32)
T('umath_ctz64_bsf', 1, lambda v: ctz(v, 64), lambda: (r64(),))
T('umath_popcount64_soft', 1, pc, lambda: (r64(),))
T('umath_parity_u128', 2, lambda a, b: (pc(a) + pc(b)) & 1, lambda: (r64(), r64()), wout=32)

T('umath_mask_low32', 1, M, lambda: (random.randrange(33),), wout=32)
T('umath_mask_low64', 1, M, lambda: (random.randrange(65),))
T('umath_mask_high64', 1, lambda n: M(n) << (64 - n), lambda: (random.randrange(65),))


def rng(w):
    def g():
        lo = random.choice([0, random.randrange(w)])
        return (lo, random.choice([w - 1, random.randrange(lo, w)]))
    return g


T('umath_mask_range32', 2, lambda lo, hi: M(hi - lo + 1) << lo, rng(32), wout=32)
T('umath_mask_range64', 2, lambda lo, hi: M(hi - lo + 1) << lo, rng(64))


def ext(w):
    def g():
        p = random.randrange(w)
        return (r64() & M(w), p, random.randrange(1, w - p + 1))
    return g


T('umath_bitextract_u32', 3, lambda v, p, wd: (v >> p) & M(wd), ext(32), wout=32)
T('umath_bitextract_u64', 3, lambda v, p, wd: (v >> p) & M(wd), ext(64))
T('umath_bitextract_s64', 3, lambda v, p, wd: s(v >> p, wd), ext(64))


def ins(w):
    def g():
        p = random.randrange(w)
        return (r64() & M(w), r64(), p, random.randrange(1, w - p + 1))
    return g


T('umath_bitinsert_u32', 4, lambda v, f, p, wd: (v & ~(M(wd) << p) | (f & M(wd)) << p) & M(32), ins(32), wout=32)
T('umath_bitinsert_u64', 4, lambda v, f, p, wd: (v & ~(M(wd) << p) | (f & M(wd)) << p) & M(64), ins(64))
T('umath_bitinsert_range', 4, lambda v, f, hi, lo: (v & ~(M(hi - lo + 1) << lo) | (f & M(hi - lo + 1)) << lo) & M(64),
  lambda: (lambda lo, hi: (r64(), r64(), hi, lo))(*rng(64)()))

# buffer insert: compare the whole buffer against a Python big integer. The
# routine reads/writes whole qwords around the field, so the field stays in
# the first 256 bits of a 64-byte buffer.
put = fn(lib, 'umath_bitinsert_buf', None, P, U64, U64, U64)
put128 = fn(lib, 'umath_bitinsert_buf128', None, P, U64, U64, U64, U64)
for _ in range(500):
    data = random.getrandbits(512)
    b = (C.c_ubyte * 64).from_buffer_copy(data.to_bytes(64, 'little'))
    wide = random.random() < .5
    width = random.randrange(1, 129 if wide else 65)
    off = random.randrange(0, 256 - width + 1)
    val = random.getrandbits(128)
    if wide:
        put128(C.addressof(b), off, width, val & M(64), val >> 64)
    else:
        put(C.addressof(b), off, width, val & M(64))
    want = data & ~(M(width) << off) | (val & M(width)) << off
    ck.check('umath_bitinsert_buf128' if wide else 'umath_bitinsert_buf',
             int.from_bytes(bytes(b), 'little') == want, f'off={off} width={width}')

T('umath_align_up64', 2, lambda v, a: None if v + a - 1 >= 1 << 64 else (v + a - 1) & ~(a - 1), lambda: (r64(), 1 << random.randrange(13)))
T('umath_align_down64', 2, lambda v, a: v & ~(a - 1), lambda: (r64(), 1 << random.randrange(13)))
T('umath_round_pow2_up32', 1, lambda v: 1 if v <= 1 else min(1 << 31, 1 << (v - 1).bit_length()),
  lambda: (random.choice([r32(), 1 << 31, (1 << 31) + 1, M(32)]),), wout=32)
T('umath_round_pow2_up64', 1, lambda v: 1 if v <= 1 else min(1 << 63, 1 << (v - 1).bit_length()),
  lambda: (random.choice([r64(), 1 << 63, (1 << 63) + 1, M(64)]),))
T('umath_round_pow2_down64', 1, lambda v: 0 if v == 0 else 1 << (v.bit_length() - 1), lambda: (r64(),))
T('umath_log2_ceil64', 1, lambda v: M(32) if v == 0 else (v - 1).bit_length(), lambda: (r64(),), wout=32)

sat = lambda lo, hi: (lambda x: max(lo, min(hi, x)))
b8 = lambda: (random.randrange(256), random.randrange(256))
T('umath_bit8_add_sat_s', 2, lambda a, b: sat(-128, 127)(s(a, 8) + s(b, 8)), b8, wout=8)
T('umath_bit8_sub_sat_u', 2, lambda a, b: max(0, a - b), b8, wout=8)
T('umath_bit8_rotl', 2, lambda a, n: ((a << (n & 7)) | (a >> (8 - (n & 7)))) & 255, lambda: (random.randrange(256), random.randrange(16)), wout=8)
T('umath_bit16_add_sat_s', 2, lambda a, b: sat(-32768, 32767)(s(a, 16) + s(b, 16)), lambda: (random.randrange(65536), random.randrange(65536)), wout=16)
T('umath_bit32_add_sat_u', 2, lambda a, b: min(M(32), a + b), lambda: (r32(), r32()), wout=32)
e64 = lambda: (r64(), r64())
T('umath_bit64_add_sat_s', 2, lambda a, b: sat(-2 ** 63, 2 ** 63 - 1)(s(a, 64) + s(b, 64)), e64)
T('umath_bit64_sub_sat_u', 2, lambda a, b: max(0, a - b), e64)
T('umath_bit64_abs_s', 1, lambda a: min(2 ** 63 - 1, abs(s(a, 64))), lambda: (random.choice([r64(), 1 << 63, M(64), (1 << 63) + 1]),))
T('umath_bit2_pack4', 4, lambda a, b, c, d: (a & 3) | (b & 3) << 2 | (c & 3) << 4 | (d & 3) << 6,
  lambda: tuple(random.randrange(256) for _ in range(4)), wout=8)
T('umath_bit4_pack', 2, lambda lo, hi: (lo & 15) | (hi & 15) << 4, b8, wout=8)

il = fn(lib, 'umath_nibble_interleave', None, P, P, P, U64)
for n in (0, 1, 7, 33):
    lo, hi = bytes(random.randrange(256) for _ in range(n)), bytes(random.randrange(256) for _ in range(n))
    dst = (C.c_ubyte * max(n, 1))()
    il(dst, lo, hi, n)
    ck.check('umath_nibble_interleave', bytes(dst)[:n] == bytes((h & 15) << 4 | (l & 15) for l, h in zip(lo, hi)), n)


# 128-bit values come back in rax:rdx, which ctypes reads as a 16-byte struct
class U128(C.Structure):
    _fields_ = [('lo', C.c_uint64), ('hi', C.c_uint64)]


r128 = lambda: random.choice([0, M(128), 1 << 127, random.getrandbits(128), random.getrandbits(random.randrange(1, 129))])
for name, ref in (('shl', lambda v, n: (v << n) & M(128)), ('shr', lambda v, n: v >> n),
                  ('sar', lambda v, n: (s(v, 128) >> n) & M(128))):
    f = fn(lib, f'umath_bit128_{name}', U128, U64, U64, U64)
    for _ in range(1000):
        v, n = r128(), random.choice([0, 1, 63, 64, 65, 127, random.randrange(128)])
        r = f(v & M(64), v >> 64, n)
        ck.check(f'umath_bit128_{name}', r.lo | r.hi << 64 == ref(v, n), f'v={v:#x} n={n}')
for name, ref in (('add', lambda a, b: (a + b) & M(128)), ('sub', lambda a, b: (a - b) & M(128))):
    f = fn(lib, f'umath_bit128_{name}', U128, U64, U64, U64, U64)
    for _ in range(500):
        a, b = r128(), r128()
        r = f(a & M(64), a >> 64, b & M(64), b >> 64)
        ck.check(f'umath_bit128_{name}', r.lo | r.hi << 64 == ref(a, b), f'{a:#x} {b:#x}')
cmp_s = fn(lib, 'umath_bit128_cmp_s', I32, U64, U64, U64, U64)
for _ in range(500):
    a, b = r128(), random.choice([r128(), None])
    b = a if b is None else b
    want = (s(a, 128) > s(b, 128)) - (s(a, 128) < s(b, 128))
    ck.check('umath_bit128_cmp_s', cmp_s(a & M(64), a >> 64, b & M(64), b >> 64) == want, f'{a:#x} {b:#x}')

w512 = lambda v: (C.c_uint64 * 8)(*[(v >> (64 * i)) & M(64) for i in range(8)])
v512 = lambda a: sum(x << (64 * i) for i, x in enumerate(a))
for name, ref in (('shl', lambda v, n: (v << n) & M(512)), ('shr', lambda v, n: v >> n)):
    f = fn(lib, f'umath_bit512_{name}', None, P, P, U64)
    for _ in range(300):
        v, n = random.getrandbits(512), random.choice([0, 1, 63, 64, 65, 200, 511, random.randrange(512)])
        dst = (C.c_uint64 * 8)()
        f(dst, w512(v), n)
        ck.check(f'umath_bit512_{name}', v512(dst) == ref(v, n), f'n={n}')

# byte-buffer rotation (bit i lives in byte i/8, bit i%8), multi-word rotation
for name, words, unit in (('l_bytes', False, 8), ('r_bytes', False, 8), ('l_buf', True, 64), ('r_buf', True, 64)):
    f = fn(lib, f'umath_bitrot_{name}', None, P, P, U64, U64)
    for _ in range(200):
        count = random.randrange(1, 9 if words else 65)
        total = count * unit
        v, amt = random.getrandbits(total), random.randrange(3 * total)
        src = (C.c_ubyte * (total // 8)).from_buffer_copy(v.to_bytes(total // 8, 'little'))
        dst = (C.c_ubyte * (total // 8))()
        f(dst, src, count, amt)
        k = amt % total if name[0] == 'l' else (-amt) % total
        want = ((v << k) | (v >> (total - k))) & M(total)
        ck.check(f'umath_bitrot_{name}', int.from_bytes(bytes(dst), 'little') == want, f'count={count} amount={amt}')
big = (C.c_ubyte * 600)(*([0x5A] * 600))
fn(lib, 'umath_bitrot_l_bytes', None, P, P, U64, U64)(big, big, 600, 3)
ck.check('umath_bitrot_l_bytes rejects > 512 bytes', bytes(big) == bytes([0x5A] * 600))

ck.finish()
