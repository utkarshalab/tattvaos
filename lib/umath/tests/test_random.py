"""random — xoshiro256** PRNG, splitmix64 seeding and uniform samplers.

Every result is compared bit-for-bit against a Python reference of the
published algorithms (Blackman & Vigna), so a given seed must give the same
stream as the reference C code.
"""
import ctypes as C
import random

from umath_ref import D, F, P, U64, Z, Checker, fn, load, r32, same

M64 = (1 << 64) - 1

lib = load()
ck = Checker('random')
random.seed(12345)

State = U64 * 4

next_u64 = fn(lib, 'umath_random_xoshiro256_next', U64, P)
seed_u64 = fn(lib, 'umath_random_xoshiro256_seed_from_u64', None, P, U64)
FILL_CB = C.CFUNCTYPE(U64, P, Z)
seed_urand = fn(lib, 'umath_random_xoshiro256_seed_from_urand', U64, P, FILL_CB)
uni32 = fn(lib, 'umath_random_uniform_f32', F, P)
uni64 = fn(lib, 'umath_random_uniform_f64', D, P)
range32 = fn(lib, 'umath_random_uniform_f32_range', F, P, F, F)
range64 = fn(lib, 'umath_random_uniform_f64_range', D, P, D, D)
fill32 = fn(lib, 'umath_random_fill_uniform_f32', None, P, P, Z)
fill64 = fn(lib, 'umath_random_fill_uniform_f64', None, P, P, Z)


def rotl(x, k):
    return ((x << k) | (x >> (64 - k))) & M64


def ref_next(s):
    """xoshiro256** step on a 4-element list; returns the output."""
    result = (rotl((s[1] * 5) & M64, 7) * 9) & M64
    t = (s[1] << 17) & M64
    s[2] ^= s[0]
    s[3] ^= s[1]
    s[1] ^= s[2]
    s[0] ^= s[3]
    s[2] ^= t
    s[3] = rotl(s[3], 45)
    return result


def ref_seed(seed):
    """First four splitmix64 outputs for seed."""
    x, out = seed, []
    for _ in range(4):
        x = (x + 0x9E3779B97F4A7C15) & M64
        z = x
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        out.append(z ^ (z >> 31))
    return out


def make_state(words):
    return State(*words)


def random_state():
    return [random.getrandbits(64) for _ in range(4)]


# --- splitmix64 seeding ----------------------------------------------------
# Published vector: the first splitmix64 output for seed 0 is
# 0xE220A8397B1DCDAF.
st = State()
seed_u64(st, 0)
ck.check('seed_from_u64 known vector', st[0] == 0xE220A8397B1DCDAF, hex(st[0]))
for seed in [0, 1, M64, 0x0123456789ABCDEF] + [random.getrandbits(64) for _ in range(200)]:
    st = State()
    seed_u64(st, seed)
    ck.check('seed_from_u64 matches splitmix64', list(st) == ref_seed(seed), f'seed={seed:#x}')

# --- xoshiro256** core ------------------------------------------------------
for _ in range(50):
    words = random_state()
    st, ref = make_state(words), list(words)
    for i in range(200):
        got, want = next_u64(st), ref_next(ref)
        if not ck.check('next output', got == want, f'step {i}: {got:#x} != {want:#x}'):
            break
    ck.check('next state', list(st) == ref, 'state diverged')

# --- uniform samplers -------------------------------------------------------
for _ in range(20):
    words = random_state()
    st, ref = make_state(words), list(words)
    for _ in range(100):
        got, want = uni32(st), (ref_next(ref) >> 40) * 2.0 ** -24
        ck.check('uniform_f32 value', same(got, want), f'{got!r} != {want!r}')
        ck.check('uniform_f32 in [0,1)', 0.0 <= got < 1.0, repr(got))
    st, ref = make_state(words), list(words)
    for _ in range(100):
        got, want = uni64(st), (ref_next(ref) >> 11) * 2.0 ** -53
        ck.check('uniform_f64 value', same(got, want), f'{got!r} != {want!r}')
        ck.check('uniform_f64 in [0,1)', 0.0 <= got < 1.0, repr(got))

# --- range variants -----------------------------------------------------------
for lo, hi in [(0.0, 1.0), (-2.5, 7.25), (-1.0, 1.0), (100.0, 100.5), (-3e5, -1e5)]:
    words = random_state()
    st, ref = make_state(words), list(words)
    for _ in range(50):
        u = (ref_next(ref) >> 40) * 2.0 ** -24
        lo32, hi32 = r32(lo), r32(hi)
        want = r32(r32(u * r32(hi32 - lo32)) + lo32)
        got = range32(st, lo, hi)
        ck.check('uniform_f32_range value', same(got, want), f'[{lo},{hi}): {got!r} != {want!r}')
    st, ref = make_state(words), list(words)
    for _ in range(50):
        u = (ref_next(ref) >> 11) * 2.0 ** -53
        want = u * (hi - lo) + lo
        got = range64(st, lo, hi)
        ck.check('uniform_f64_range value', same(got, want), f'[{lo},{hi}): {got!r} != {want!r}')

# --- array fill matches repeated scalar calls ---------------------------------
for n in [0, 1, 2, 7, 64, 1000]:
    words = random_state()
    st_a, st_s = make_state(words), make_state(words)
    buf = (F * (n + 1))()
    buf[n] = -1.0                                   # canary past the end
    fill32(st_a, buf, n)
    scalar = [uni32(st_s) for _ in range(n)]
    ck.check('fill_uniform_f32 matches scalar', list(buf)[:n] == scalar, f'n={n}')
    ck.check('fill_uniform_f32 state', list(st_a) == list(st_s), f'n={n}')
    ck.check('fill_uniform_f32 no overrun', buf[n] == -1.0, f'n={n}')

    st_a, st_s = make_state(words), make_state(words)
    buf = (D * (n + 1))()
    buf[n] = -1.0
    fill64(st_a, buf, n)
    scalar = [uni64(st_s) for _ in range(n)]
    ck.check('fill_uniform_f64 matches scalar', list(buf)[:n] == scalar, f'n={n}')
    ck.check('fill_uniform_f64 state', list(st_a) == list(st_s), f'n={n}')
    ck.check('fill_uniform_f64 no overrun', buf[n] == -1.0, f'n={n}')

# --- seeding from a urand-style callback ----------------------------------------
calls = []


def make_fill(data, ret=1):
    def fill(buf, nbytes):
        calls.append(nbytes)
        C.memmove(buf, bytes(data), nbytes)
        return ret
    return FILL_CB(fill)


entropy = bytes(random.getrandbits(8) for _ in range(32))
st = State()
calls.clear()
ok = seed_urand(st, make_fill(entropy))
ck.check('seed_from_urand success', ok == 1, repr(ok))
ck.check('seed_from_urand asks for 32 bytes', calls == [32], repr(calls))
ck.check('seed_from_urand copies entropy', bytes(st) == entropy, bytes(st).hex())

st = State(7, 7, 7, 7)
ok = seed_urand(st, make_fill(bytes(32)))
ck.check('seed_from_urand all-zero fixed', ok == 1 and list(st) == [1, 0, 0, 0], f'{ok} {list(st)}')

st = State(7, 7, 7, 7)
ok = seed_urand(st, make_fill(entropy, ret=0))
ck.check('seed_from_urand fill failure', ok == 0, repr(ok))

st = State(7, 7, 7, 7)
ok = seed_urand(st, C.cast(None, FILL_CB))
ck.check('seed_from_urand NULL', ok == 0 and list(st) == [7, 7, 7, 7], f'{ok} {list(st)}')

ck.finish()
