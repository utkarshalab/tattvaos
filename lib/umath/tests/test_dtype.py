"""dtype: classification consistency, promotion, support levels, value traits."""
import ctypes as C
import itertools
import math
import os
import re
import struct

from umath_ref import D, I32, P, U32, U64, Checker, fn, load

lib = load()
ck = Checker('dtype')

ids = {}
with open(os.path.join(os.path.dirname(__file__), '..', 'dtype', 'dtype_id.asm'), encoding='utf-8') as src:
    for line in src:
        m = re.match(r'^(DTYPE_[A-Z0-9_]+)\s+equ\s+(0x[0-9A-Fa-f]+|\d+)', line)
        if m:
            ids[m.group(1)] = int(m.group(2), 0)
meta = {'DTYPE_SPEC_VERSION', 'DTYPE_COUNT', 'DTYPE_ID_BITS', 'DTYPE_ID_MAX', 'DTYPE_NONE', 'DTYPE_UNKNOWN', 'DTYPE_MAX'}
T = {k[6:]: v for k, v in ids.items() if k not in meta}
name_of = {v: k for k, v in T.items()}

u = lambda name, n=1: fn(lib, f'umath_dtype_{name}', I32, *([U32] * n))
size, fam, isf, isi, iss, isu = u('size_bits'), u('get_family'), u('is_float'), u('is_integer'), u('is_signed'), u('is_unsigned')
ck.check('DTYPE_COUNT matches the defined ids', ids['DTYPE_COUNT'] == len(T), f'{ids["DTYPE_COUNT"]} vs {len(T)}')

for k, b in (('INT8', 8), ('INT16', 16), ('INT32', 32), ('INT64', 64), ('UINT8', 8), ('UINT64', 64), ('FP16', 16),
             ('BF16', 16), ('FP32', 32), ('FP64', 64), ('FP8_E4M3', 8), ('INT4', 4), ('UINT4', 4), ('INT1', 1)):
    ck.check('size_bits', size(T[k]) == b, k)
for k, v in T.items():
    F, I, S, U = isf(v), isi(v), iss(v), isu(v)
    ck.check('every dtype has a family', fam(v) not in (0, 0xFF, -1), k)
    ck.check('not both integer and float', not (I and F), k)
    ck.check('not both signed and unsigned', not (S and U), k)
    if re.fullmatch(r'UINT\d+', k):
        ck.check('UINTn is an unsigned integer', I and U and not S, k)
    if re.fullmatch(r'INT\d+', k):
        ck.check('INTn is a signed integer', I and not U, k)
    if re.fullmatch(r'(FP|BF)\d+', k):
        ck.check('FPn/BFn is a float', F, k)

prom = u('promote', 2)
vals = sorted(T.values())
asym = [(name_of[a], name_of[b]) for a, b in itertools.combinations(vals, 2) if prom(a, b) != prom(b, a)]
ck.check('promote is commutative', not asym, f'{len(asym)} pairs, e.g. {asym[:3]}')
for a, b, want in (('INT8', 'FP32', 'FP32'), ('FP16', 'BF16', 'FP32'), ('INT32', 'INT64', 'INT64'),
                   ('UINT8', 'INT8', 'INT16'), ('UINT8', 'INT16', 'INT16'), ('UINT32', 'INT32', 'INT64'),
                   ('UINT64', 'INT64', 'INT128'), ('FP32', 'FP64', 'FP64'), ('INT1', 'UINT8', 'UINT8'),
                   ('INT64', 'FP16', 'FP32'), ('CF32', 'FP64', 'CF64'), ('FP16', 'FP16', 'FP16'),
                   # the promotion table documented in dtype/README.md
                   ('INT8', 'INT16', 'INT16'), ('INT8', 'FP64', 'FP64'), ('FP16', 'FP32', 'FP32'),
                   ('BF16', 'BF16', 'BF16'), ('BF16', 'FP32', 'FP32'), ('FP8_E4M3', 'FP16', 'FP16'),
                   ('FP8_E4M3', 'FP32', 'FP32'), ('FP8_E4M3', 'BF16', 'BF16'), ('INT4', 'INT4', 'INT4'),
                   ('INT4', 'FP32', 'FP32'), ('CF32', 'CF32', 'CF32'), ('CF32', 'CF64', 'CF64'),
                   ('CF32', 'FP32', 'CF32'), ('BIGINT', 'INT64', 'BIGINT'), ('BIGINT', 'FP64', 'BIGFLOAT')):
    got = prom(T[a], T[b])
    ck.check('promote expected pairs', got == T[want], f'promote({a}, {b}) = {name_of.get(got, hex(got))}, want {want}')

acc = u('accumulator')
for k in T:
    a = acc(T[k])
    ck.check('accumulator returns a defined dtype', a == 0 or a in name_of, f'{k} -> {a:#x}')

fn(lib, 'umath_dtype_support_init', None)()
lvl = u('support_level')
for k in ('INT8', 'INT32', 'INT64', 'FP32', 'FP64'):
    ck.check('support_level of basic types is not NONE', lvl(T[k]) in (1, 2, 3), f'{k} = {lvl(T[k])}')
    ck.check('support_level is stable (cache)', lvl(T[k]) == lvl(T[k]), k)

bits32 = lambda x: struct.unpack('<I', struct.pack('<f', x))[0]
bits64 = lambda x: struct.unpack('<Q', struct.pack('<d', x))[0]
trait = lambda name: fn(lib, f'umath_dtype_{name}', I32, U32, U64)
is_nan, is_inf, is_zero, is_nz, is_normal, is_sub = (trait(n) for n in ('is_nan_val', 'is_inf_val', 'is_zero_val',
                                                                         'is_neg_zero_val', 'is_normal', 'is_subnormal_val'))
for k, enc in (('FP32', bits32), ('FP64', bits64)):
    for x in (0.0, -0.0, 1.0, -2.5, math.inf, -math.inf, math.nan, 1e-310 if k == 'FP64' else 1e-40):
        b = enc(x)
        sub = x != 0 and abs(x) < (2.2250738585072014e-308 if k == 'FP64' else 1.1754943508222875e-38)
        ck.check('is_nan_val', is_nan(T[k], b) == int(math.isnan(x)), (k, x))
        ck.check('is_inf_val', is_inf(T[k], b) == int(math.isinf(x)), (k, x))
        ck.check('is_zero_val', is_zero(T[k], b) == int(x == 0), (k, x))
        ck.check('is_neg_zero_val', is_nz(T[k], b) == int(x == 0 and math.copysign(1, x) < 0), (k, x))
        ck.check('is_normal', is_normal(T[k], b) == int(math.isfinite(x) and x != 0 and not sub), (k, x))
        ck.check('is_subnormal_val', is_sub(T[k], b) == int(sub), (k, x))
for k in ('INT8', 'INT32', 'INT64', 'UINT64'):
    ck.check('is_zero_val integer', is_zero(T[k], 0) == 1 and is_zero(T[k], 5) == 0, k)

ulp = fn(lib, 'umath_dtype_ulp_f64', D, U32, D)
for k, eps in (('FP64', 2.0 ** -52), ('FP32', 2.0 ** -23)):
    for x in (1.0, 3.0, 1024.5, 1e-5, 6e4):
        want = eps * 2.0 ** math.floor(math.log2(abs(x)))
        ck.check('ulp_f64', ulp(T[k], x) == want, (k, x, ulp(T[k], x), want))
ck.check('round_error_f64 is half epsilon', fn(lib, 'umath_dtype_round_error_f64', D, U32)(T['FP64']) == 2.0 ** -53)

vu = fn(lib, 'umath_dtype_validate_u64', I32, U32, U64)
for k, mx in (('UINT8', 255), ('UINT32', 2 ** 32 - 1), ('UINT64', 2 ** 64 - 1)):
    ck.check('validate_u64 at max', vu(T[k], mx) == 1, k)
    if mx < 2 ** 64 - 1:
        ck.check('validate_u64 above max', vu(T[k], mx + 1) == 0, k)
ck.check('validate_u64 large values are not negative', vu(T['UINT8'], 1 << 63) == 0)

full = fn(lib, 'umath_dtype_name_full', C.c_char_p, U32)
for k, want in (('FP32', b'float32'), ('FP64', b'float64'), ('BF16', b'bfloat16'), ('INT8', b'int8'), ('UINT32', b'uint32')):
    ck.check('name_full', full(T[k]) == want, (k, full(T[k])))

ck.finish()
