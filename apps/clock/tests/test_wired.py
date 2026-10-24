#!/usr/bin/env python3
"""Real app -> lib/time -> RTC/mono -> lib/cal paths; only raw hardware is fake."""
import calendar,ctypes as C,datetime as D,random,sys
from pathlib import Path
lib=C.CDLL(str(Path(sys.argv[1]).resolve()));U=C.c_uint64;I=C.c_int64
class Date(C.Structure): _fields_=[(n,U) for n in ('year','month','day','hour','minute','second','weekday','yearday')]
class Month(C.Structure): _fields_=[(n,U) for n in ('year','month','week_start','days','first')]+[('cells',U*42)]
class Sample(C.Structure): _fields_=[('mono',U),('sec',I),('ns',U)]
class Stamp(C.Structure): _fields_=[('sec',I),('ns',U)]
def fn(n,args):
 f=getattr(lib,n);f.argtypes=args;f.restype=I;return f
read=fn('uclock_read_native',[C.POINTER(Sample)])
now=fn('ucal_now',[I,C.POINTER(Date)])
local=fn('uclock_local_now',[I,C.POINTER(Date)])
month=fn('ucal_month_now',[I,U,C.POINTER(Month)])
wall=fn('time_read_realtime',[C.POINTER(Stamp)])
mono=fn('time_read_monotonic',[C.POINTER(U)])
mem=(C.c_ubyte*128).in_dll(lib,'time_test_cmos')
ticks=U.in_dll(lib,'time_test_ticks');reads=U.in_dll(lib,'time_test_reads');unstable=U.in_dll(lib,'time_test_unstable');stuck=U.in_dll(lib,'time_test_stuck')
s=Sample(111,222,333);before=bytes(s)
assert read(C.byref(s))==-3 and bytes(s)==before
out=Date(444);before=bytes(out)
assert now(0,C.byref(out))==-5 and bytes(out)==before
assert local(0,C.byref(out))==-3 and bytes(out)==before
lib.mono_time_init();lib.time_native_init()
def program(dt,binary=False,hour12=False,century=True):
 for i in range(128):mem[i]=0
 def encode(n):return n if binary else (n//10)*16+n%10
 hour=dt.hour
 if hour12:hour=(hour%12 or 12)
 mem[0]=encode(dt.second);mem[2]=encode(dt.minute);mem[4]=encode(hour)|(0x80 if hour12 and dt.hour>=12 else 0)
 mem[7]=encode(dt.day);mem[8]=encode(dt.month);mem[9]=encode(dt.year%100)
 mem[0x32]=encode(dt.year//100) if century else 0
 mem[0xb]=(4 if binary else 0)|(0 if hour12 else 2);mem[0xd]=0x80
rng=random.Random(91);epoch=D.datetime(1970,1,1)
for _ in range(800):
 y=rng.randrange(1970,2200);m=rng.randrange(1,13);d=rng.randrange(1,calendar.monthrange(y,m)[1]+1)
 dt=D.datetime(y,m,d,rng.randrange(24),rng.randrange(60),rng.randrange(60))
 program(dt,binary=rng.choice((False,True)),hour12=rng.choice((False,True)))
 ticks.value+=rng.randrange(1,10000)
 assert read(C.byref(s))==0 and s.sec==int((dt-epoch).total_seconds()) and s.ns==0 and s.mono==ticks.value
 offset=rng.choice((0,20700,-18000,64800,-64800));expect=dt+D.timedelta(seconds=offset)
 for call in (now,local):
  assert call(offset,C.byref(out))==0
  assert tuple(getattr(out,n) for n in ('year','month','day','hour','minute','second'))==(expect.year,expect.month,expect.day,expect.hour,expect.minute,expect.second)
  assert out.weekday==(expect.weekday()+1)%7 and out.yearday==expect.timetuple().tm_yday-1
 view=Month();assert month(offset,1,C.byref(view))==0 and view.year==expect.year and view.month==expect.month
for hour in (0,12,23):
 for binary in (False,True):
  dt=D.datetime(2026,10,24,hour,0,0);program(dt,binary,hour12=True,century=False)
  assert read(C.byref(s))==0 and s.sec==int((dt-epoch).total_seconds())
program(D.datetime(2026,10,24));mem[0x32]=255
assert read(C.byref(s))==0 # Explicit absent-century fallback.
for index,value in ((0,0x6a),(8,0x13),(7,0),(9,0xfa),(0xb,0x82),(0xd,0)):
 program(D.datetime(2026,10,24));mem[index]=value
 before=bytes(s);assert read(C.byref(s))==-3 and bytes(s)==before,(index,value)
for flag in (stuck,unstable):
 program(D.datetime(2026,10,24));flag.value=1;reads.value=0
 before=bytes(s);assert read(C.byref(s))==-3 and bytes(s)==before
 assert reads.value<70000 # Bounded even for permanent UIP / continuous rollover.
 flag.value=0
program(D.datetime(1900,2,28));mem[7]=0x29
assert read(C.byref(s))==-3
program(D.datetime(2000,2,29));assert read(C.byref(s))==0
before=bytes(out);assert now(64801,C.byref(out))==-1 and bytes(out)==before
assert read(None)==-1 and now(0,None)==-1
print('Native library wiring: PASS (800 real RTC/mono/calendar paths, BCD/binary/12h/24h, century, invalid/stuck/rollover/availability)')
