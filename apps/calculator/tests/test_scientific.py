"""Check assembled scientific core and formatter against Python math."""
import ctypes as C
from decimal import Decimal
import math
import random
import sys
from pathlib import Path
lib = C.CDLL(str(Path(sys.argv[1]).resolve()))
f = lib.test_scientific
f.argtypes = [C.c_char_p, C.c_void_p, C.POINTER(C.c_double)]
f.restype = C.c_int
fmt = lib.calc_float_format
fmt.argtypes = [C.c_double, C.c_void_p, C.c_uint]
fmt.restype = C.c_void_p

ctx = (C.c_uint64 * 16)()
def evaluate(expr, expected=None, status=0, tolerance=3e-12):
    before = ctx[0]
    value = C.c_double()
    code = f(expr.encode() if expr is not None else None, ctx, C.byref(value))
    assert code == status, (expr, code, status, value.value)
    if code:
        assert ctx[0] == before and value.value == 0, (expr, ctx[0], before)
    else:
        assert math.isclose(value.value, expected, rel_tol=tolerance, abs_tol=1e-14), (expr,value.value,expected)
    return value.value

vectors = {
 '0':0, '.5':.5, '1.':1, '1e3 + .25':1000.25, '1.25e-3':.00125,
 '2+3*4':14, '20-3-2':15, '100/5/2':10, '2**3**2':512,
 '-2**2':-4, '(-2)**2':4, '2**-3':.125, '-3!':-6,
 '0!':1, '3!!':720, 'fact(5)':120, '5!/(3!*2!)':10,
 'pi':math.pi,'e':math.e,'tau':math.tau,'sqrt(81)':9,
 'cbrt(-8)':-2, 'sin(pi/2)':1, 'cos(pi)':-1, 'tan(pi/4)':1,
 'asin(1)':math.pi/2, 'acos(-1)':math.pi, 'atan(1)':math.pi/4,
 'ln(e)':1,'log(1000)':3,'log10(100)':2,'log2(8)':3,'exp(1)':math.e,
 'abs(-4.5)':4.5,'floor(-1.2)':-2,'ceil(-1.2)':-1,'trunc(-1.8)':-1,
 'round(2.5)':2,'round(3.5)':4,'pow(-2,3)':-8,'hypot(3,4)':5,
 'atan2(1,0)':math.pi/2,'min(4,2)':2,'max(-1,-2)':-1,
 '-7%3':-1,'7%-3':1, '1e300%3':math.fmod(1e300,3),
 '1.7976931348623157e308':sys.float_info.max,'5e-324':5e-324,
 '2.2250738585072014e-308':sys.float_info.min,
 '000.0000123':.0000123, '12345678901234567890123e-22':1.2345678901234568,
}
for expr, expected in vectors.items():
    evaluate(expr,expected)
evaluate('2',2)
evaluate('ans*3',6)
C.cast(C.byref(ctx,8),C.POINTER(C.c_double))[0]=4.5
evaluate('mem+ans',10.5)
ctx[2]=1
for expr,expected in [('sin(30)',.5),('cos(180)',-1),('asin(1)',90),('atan2(1,0)',90)]:
    evaluate(expr,expected)
ctx[2]=0
for expr in ('', ' ', '.', '1e', '1e+', '1.2.3', '1 2', 'sin', 'sine(1)',
             'sqrt()', 'pow(2)', 'sqrt(1,2)', 'pow(2,3,4)', '(1', '1)',
             '2^3','1&2','0x10','2pi','PI','1e2e3','unknown','1+', '2**'):
    evaluate(expr,status=1)
for expr in ('1e309','1e-999','1e99999','exp(1000)','1e308*10','sin(1e12)'):
    evaluate(expr,status=2)
for expr in ('1/0','1%0'):
    evaluate(expr,status=3)
for expr in ('sqrt(-1)','ln(-1)','asin(2)','(-2)**.5','fact(171)','(-1)!','1.5!'):
    evaluate(expr,status=7)
evaluate('('*65+'1'+')'*65,status=5)
evaluate('-'*65+'1',status=5)
evaluate('1'*4096,status=1)
evaluate(None,status=1)
evaluate('1/0 + )',status=3)

rng=random.Random(57)
for name,reference,lo,hi in [
 ('sin',math.sin,-100,100),('cos',math.cos,-100,100),('tan',math.tan,-1,1),
 ('asin',math.asin,-1,1),('acos',math.acos,-1,1),('atan',math.atan,-100,100),
 ('ln',math.log,.001,1000),('log',math.log10,.001,1000),
 ('exp',math.exp,-30,30),('sqrt',math.sqrt,0,1e8),('cbrt',math.cbrt,-1e5,1e5),
]:
    for _ in range(100):
        x=rng.uniform(lo,hi)
        evaluate(f'{name}({x:.17g})',reference(x))
for _ in range(200):
    a,b,c=[rng.uniform(-100,100) for _ in range(3)]
    evaluate(f'({a:.17g} + {b:.17g}) * {c:.17g}',(a+b)*c,tolerance=1e-10)

# Formatter runs across every exponent, subnormals, signs, precision and rounding carries.
values=[0.,-0.,1.,-1.,sys.float_info.max,sys.float_info.min,5e-324,
        9.99999999999999,99.999999999,0.000099999999999,math.pi]
values += [math.ldexp(rng.uniform(1,2),e) for e in range(-1074,1023,7)]
for x in values:
    for precision in (1,6,12,15):
        for value in (x,-x):
            buf=C.create_string_buffer(64)
            assert fmt(value,buf,precision)
            actual=Decimal(buf.value.decode())
            exact=Decimal(value)
            tolerance=max(abs(exact)*Decimal('5.1')*Decimal(10)**(-precision),Decimal('5e-324'))
            assert abs(actual-exact)<=tolerance, (value,precision,buf.value)
for value in (math.nan,math.inf,-math.inf):
    buf=C.create_string_buffer(b'unchanged',64)
    assert not fmt(value,buf,12) and buf.value==b'unchanged'
for precision in (0,16):
    assert not fmt(1.,C.create_string_buffer(64),precision)
print('Scientific: PASS (functions, precedence, state, domains, 1300 generated checks, decimal formatting)')
