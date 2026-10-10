"""memory: copy/move/set/zero/compare/fill fuzzing, allocators, spans."""
import ctypes as C
import random

from umath_ref import I64, P, U64, Z, Checker, cpu_has, fn, load

lib = load()
ck = Checker('memory')
random.seed(7)
N = 4096
avx2 = cpu_has('avx2')


def buf(n=N, fill=None):
    return (C.c_ubyte * n)(*([random.randrange(256) for _ in range(n)] if fill is None else [fill] * n))


def addr(b, off=0):
    return C.addressof(b) + off


SIZES = [0, 1, 7, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 1000]
simd = lambda names: [n for n in names if avx2 or 'avx2' not in n]

for name in simd(['umath_memcpy', 'umath_memcpy_sse', 'umath_memcpy_avx2', 'umath_memcpy_aligned']):
    f = fn(lib, name, P, P, P, Z)
    for _ in range(300):
        n = random.choice(SIZES + [random.randrange(1500)])
        so, do = (0, 0) if name.endswith('aligned') and random.random() < .5 else (random.randrange(64), random.randrange(64))
        src, dst = buf(), buf()
        before = bytes(dst)
        r = f(addr(dst, do), addr(src, so), n)
        want = before[:do] + bytes(src)[so:so + n] + before[do + n:]
        ck.check(f'{name} copies exactly n bytes', bytes(dst) == want, f'n={n} so={so} do={do}')
        ck.check(f'{name} returns dst', r == addr(dst, do), f'n={n}')

for name in simd(['umath_memmove', 'umath_memmove_sse', 'umath_memmove_avx2']):
    f = fn(lib, name, P, P, P, Z)
    for _ in range(500):
        n = random.choice(SIZES)
        b = buf()
        so = random.randrange(1500)
        do = max(0, so + random.randrange(-70, 70))
        want = bytearray(b)
        want[do:do + n] = bytes(b)[so:so + n]
        r = f(addr(b, do), addr(b, so), n)
        ck.check(f'{name} handles overlap', bytes(b) == bytes(want), f'n={n} so={so} do={do}')
        ck.check(f'{name} returns dst', r == addr(b, do), f'n={n}')

for name in simd(['umath_memset', 'umath_memset_sse', 'umath_memset_avx2']):
    f = fn(lib, name, P, P, U64, Z)
    for _ in range(300):
        n, o, v = random.choice(SIZES), random.randrange(64), random.randrange(256)
        b = buf()
        want = bytearray(b)
        want[o:o + n] = bytes([v]) * n
        r = f(addr(b, o), v | random.getrandbits(20) << 8, n)
        ck.check(f'{name} fills n bytes', bytes(b) == bytes(want), f'n={n} o={o}')
        ck.check(f'{name} returns dst', r == addr(b, o), f'n={n}')

for name in simd(['umath_memzero', 'umath_memzero_sse', 'umath_memzero_avx2', 'umath_memzero_nt']):
    f = fn(lib, name, P, P, Z)
    for _ in range(300):
        n = random.choice(SIZES)
        b = buf(N + 64, 0xAA)
        o = (-addr(b)) % 16 + (0 if name.endswith('nt') else random.randrange(64))
        want = bytearray(b)
        want[o:o + n] = bytes(n)
        r = f(addr(b, o), n)
        ck.check(f'{name} zeroes n bytes', bytes(b) == bytes(want), f'n={n}')
        ck.check(f'{name} returns dst', r == addr(b, o), f'n={n}')

sign = lambda x: (x > 0) - (x < 0)
for name in simd(['umath_memcmp', 'umath_memcmp_sse', 'umath_memcmp_avx2']):
    f = fn(lib, name, I64, P, P, Z)
    for _ in range(600):
        n = random.choice(SIZES)
        a = buf()
        b = (C.c_ubyte * N)(*a)
        if n and random.random() < .8:
            b[random.randrange(n)] = random.randrange(256)
        x, y = bytes(a[:n]), bytes(b[:n])
        ck.check(f'{name} sign matches lexicographic order', f(addr(a), addr(b), n) == sign((x > y) - (x < y)), f'n={n}')

if avx2:
    for name, w in (('umath_memfill_pattern2', 2), ('umath_memfill_pattern4', 4), ('umath_memfill_pattern8', 8)):
        f = fn(lib, name, P, P, U64, Z)
        for _ in range(300):
            n, o, pat = random.choice(SIZES), random.randrange(16), random.getrandbits(64)
            b = buf()
            want = bytearray(b)
            pb = pat.to_bytes(8, 'little')[:w]
            want[o:o + n] = (pb * (n // w + 1))[:n]
            r = f(addr(b, o), pat, n)
            ck.check(f'{name} repeats the pattern', bytes(b) == bytes(want), f'n={n} o={o}')
            ck.check(f'{name} returns dst', r == addr(b, o), f'n={n}')
    for name, w in (('umath_memfill_pattern16', 16), ('umath_memfill_pattern32', 32)):
        f = fn(lib, name, P, P, P, Z)
        for _ in range(300):
            n, o = random.choice(SIZES), random.randrange(16)
            pat = buf(64)
            b = buf()
            want = bytearray(b)
            want[o:o + n] = (bytes(pat)[:w] * (n // w + 1))[:n]
            r = f(addr(b, o), addr(pat), n)
            ck.check(f'{name} repeats the pattern', bytes(b) == bytes(want), f'n={n} o={o}')
            ck.check(f'{name} returns dst', r == addr(b, o), f'n={n}')

# --- allocators: every operation after init must work (64-bit magic checks)
S = C.c_ubyte * 128
ar, back = S(), buf(4096, 0)
ck.check('arena_init', fn(lib, 'umath_arena_init', I64, P, P, Z, Z)(addr(ar), addr(back), 4096, 0) == 1)
alloc = fn(lib, 'umath_arena_alloc', P, P, Z, Z)
p = alloc(addr(ar), 100, 16)
ck.check('arena_alloc aligned', p is not None and p % 16 == 0)
ck.check('arena_verify', fn(lib, 'umath_arena_verify', I64, P)(addr(ar)) == 1)
ck.check('arena_available', fn(lib, 'umath_arena_available', I64, P)(addr(ar)) == 4096 - (p + 100 - addr(back)))
mark = fn(lib, 'umath_arena_mark', P, P)(addr(ar))
ck.check('arena_mark', mark == p + 100)
ck.check('arena_realloc grows the top block in place', fn(lib, 'umath_arena_realloc', P, P, P, Z, Z)(addr(ar), p, 100, 200) == p)
ck.check('arena_rewind', fn(lib, 'umath_arena_rewind', I64, P, P)(addr(ar), p) == 1)
fn(lib, 'umath_arena_reset', None, P, U64)(addr(ar), 0)
ck.check('arena_reset', fn(lib, 'umath_arena_available', I64, P)(addr(ar)) == 4096)

for kind, init_name, obj in (('pool', 'umath_pool_init', 'object'), ('slab', 'umath_slab_init', 'block')):
    st, back = S(), buf(4096, 0)
    ck.check(f'{kind}_init', fn(lib, init_name, I64, P, P, Z, Z)(addr(st), addr(back), 4096, 64) == 1)
    a = fn(lib, f'umath_{kind}_alloc', P, P)
    free = fn(lib, f'umath_{kind}_free', I64, P, P)
    verify = fn(lib, f'umath_{kind}_verify', I64, P)
    got = [a(addr(st)) for _ in range(64)]
    ck.check(f'{kind}_alloc hands out every {obj} once', None not in got and len(set(got)) == 64)
    ck.check(f'{kind}_alloc returns NULL when exhausted', a(addr(st)) is None)
    ck.check(f'{kind}_free', all(free(addr(st), q) == 1 for q in got[::2]))
    ck.check(f'{kind}_free rejects a misaligned pointer', free(addr(st), got[1] + 8) == 0)
    ck.check(f'{kind}_verify', verify(addr(st)) == 1)

rg, back = S(), buf(4096, 0)
ck.check('region_init', fn(lib, 'umath_region_init', I64, P, P, Z, P)(addr(rg), addr(back), 4096, None) == 1)
ralloc = fn(lib, 'umath_region_alloc', P, P, Z, Z)
q = ralloc(addr(rg), 64, 16)
ck.check('region_alloc', q is not None and q % 16 == 0)
child = S()
ck.check('region_create_child', fn(lib, 'umath_region_create_child', P, P, P, Z)(addr(rg), addr(child), 512) == addr(child))
ck.check('region_is_descendant', fn(lib, 'umath_region_is_descendant', I64, P, P)(addr(child), addr(rg)) == 1)
ck.check('region_verify', fn(lib, 'umath_region_verify', I64, P)(addr(rg)) == 1)

st, back = S(), buf(4096, 0)
ck.check('stack_init', fn(lib, 'umath_stack_init', I64, P, P, Z)(addr(st), addr(back), 4096) == 1)
salloc = fn(lib, 'umath_stack_alloc', P, P, Z, Z)
s1, s2 = salloc(addr(st), 64, 16), salloc(addr(st), 32, 64)
ck.check('stack_alloc', s1 is not None and s2 is not None and s2 % 64 == 0)
ck.check('stack_verify', fn(lib, 'umath_stack_verify', I64, P)(addr(st)) == 1)
ck.check('stack_free', fn(lib, 'umath_stack_free', I64, P, P)(addr(st), s2) == 1)

# --- spans (span_compare inherits memcmp's sign)
class Span(C.Structure):
    _fields_ = [('ptr', C.c_void_p), ('size', C.c_size_t)]


a_buf, b_buf = (C.c_ubyte * 4)(1, 2, 3, 4), (C.c_ubyte * 4)(1, 2, 9, 4)
sa, sb = Span(addr(a_buf), 4), Span(addr(b_buf), 4)
cmp = fn(lib, 'umath_span_compare', I64, P, P)
ck.check('span_compare a < b', cmp(C.addressof(sa), C.addressof(sb)) == -1)
ck.check('span_compare b > a', cmp(C.addressof(sb), C.addressof(sa)) == 1)
pat = Span(addr(b_buf, 2), 2)
ck.check('span_find_subspan', fn(lib, 'umath_span_find_subspan', I64, P, P)(C.addressof(sb), C.addressof(pat)) == 2)

ck.finish()
