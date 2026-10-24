#!/usr/bin/env python3
"""Differential checks execute native NASM APIs against Python Gregorian dates."""
import calendar,ctypes as C,datetime as D,random,sys
from pathlib import Path
lib=C.CDLL(str(Path(sys.argv[1]).resolve()))
U=C.c_uint64; I=C.c_int64
class Date(C.Structure): _fields_=[(n,U) for n in ('year','month','day','hour','minute','second','weekday','yearday')]
class Month(C.Structure): _fields_=[(n,U) for n in ('year','month','week_start','days','first')]+[('cells',U*42)]
class Event(C.Structure): _fields_=[('id',U),('start',I),('end',I),('flags',U),('title',C.c_char*128)]
class Store(C.Structure): _fields_=[('next_id',U),('events',Event*64)]
def fn(n,args):
 f=getattr(lib,n);f.argtypes=args;f.restype=I;return f
valid=fn('ucal_validate',[C.POINTER(Date)])
to=fn('ucal_to_epoch',[C.POINTER(Date),I,C.POINTER(I)])
fr=fn('ucal_from_epoch',[I,I,C.POINTER(Date)])
grid=fn('ucal_month_grid',[U,U,U,C.POINTER(Month)])
addday=fn('ucal_add_days',[C.POINTER(Date),I,C.POINTER(Date)])
addmonth=fn('ucal_add_months',[C.POINTER(Date),I,C.POINTER(Date)])
iso=fn('ucal_iso_week',[C.POINTER(Date),C.POINTER(U)])
init=fn('ucal_store_init',[C.POINTER(Store)])
put=fn('ucal_event_put',[C.POINTER(Store),C.POINTER(Event),C.POINTER(U)])
get=fn('ucal_event_get',[C.POINTER(Store),U,C.POINTER(Event)])
delete=fn('ucal_event_delete',[C.POINTER(Store),U])
query=fn('ucal_event_query',[C.POINTER(Store),I,I,C.POINTER(U),U,C.POINTER(U)])
def native(d): return Date(d.year,d.month,d.day,d.hour,d.minute,d.second,99,99)
def check(a,b):
 assert tuple(getattr(a,n) for n in ('year','month','day','hour','minute','second'))==(b.year,b.month,b.day,b.hour,b.minute,b.second)
 assert a.weekday==(b.weekday()+1)%7 and a.yearday==b.timetuple().tm_yday-1
rng=random.Random(71);epoch=D.datetime(1970,1,1)
for k in range(6000):
 y=rng.randrange(1,10000);m=rng.randrange(1,13);d=rng.randrange(1,calendar.monthrange(y,m)[1]+1)
 dt=D.datetime(y,m,d,rng.randrange(24),rng.randrange(60),rng.randrange(60))
 src=native(dt);out=Date();seconds=I();offset=rng.randrange(-64800,64801)
 assert valid(C.byref(src))==0 and to(C.byref(src),offset,C.byref(seconds))==0
 assert seconds.value==int((dt-epoch).total_seconds())-offset
 assert fr(seconds,offset,C.byref(out))==0;check(out,dt)
 week=(U*3)();assert iso(C.byref(src),week)==0 and tuple(week)==tuple(dt.isocalendar()),(dt,tuple(week))
 delta=rng.randrange(-700,701)
 try: expected=dt+D.timedelta(days=delta)
 except OverflowError: expected=None
 before=bytes(out);r=addday(C.byref(src),delta,C.byref(out))
 if expected: assert r==0;check(out,expected)
 else: assert r==-2 and bytes(out)==before
 months=rng.randrange(-36,37);index=(y-1)*12+m-1+months
 r=addmonth(C.byref(src),months,C.byref(out))
 if 0<=index<9999*12:
  yy,mm=divmod(index,12);yy+=1;mm+=1
  expected=dt.replace(year=yy,month=mm,day=min(d,calendar.monthrange(yy,mm)[1]));assert r==0;check(out,expected)
 else: assert r==-2
 if k<1500:
  week_start=rng.randrange(7);view=Month();assert grid(y,m,week_start,C.byref(view))==0
  first=((D.date(y,m,1).weekday()+1)%7-week_start)%7;days=calendar.monthrange(y,m)[1]
  assert (view.days,view.first)==(days,first)
  assert list(view.cells)==[i-first+1 if first<=i<first+days else 0 for i in range(42)]
# Exact edges, signed epochs and aliasing.
for dt in (D.datetime.min,D.datetime.max.replace(microsecond=0),D.datetime(1900,2,28),D.datetime(2000,2,29),D.datetime(1970,1,1)):
 a=native(dt);b=Date();v=I();assert to(C.byref(a),0,C.byref(v))==0 and fr(v,0,C.byref(b))==0;check(b,dt)
 w=(U*3)();assert iso(C.byref(a),w)==0 and tuple(w)==tuple(dt.isocalendar())
a=native(D.datetime(2024,1,31,23,59,59));assert addmonth(C.byref(a),1,C.byref(a))==0;check(a,D.datetime(2024,2,29,23,59,59))
for bad in (Date(0,1,1),Date(10000,1,1),Date(1900,2,29),Date(2024,13,1),Date(2024,1,0),Date(2024,1,1,24),Date(2024,1,1,0,0,60)):
 v=I(123);assert valid(C.byref(bad))==-1 and to(C.byref(bad),0,C.byref(v))==-1 and v.value==123
out=Date(123);before=bytes(out)
for sec,offset in ((-(1<<63),-64800),((1<<63)-1,64800),(-62135596801,0),(253402300800,0),(0,64801)):
 assert fr(sec,offset,C.byref(out))<0 and bytes(out)==before
s=Store();assert init(C.byref(s))==0;model={}
for i in range(64):
 start=rng.randrange(-10000,10000);e=Event(0,start,start+rng.randrange(1,500),0,('Meeting '+str(i)+' \u00e9').encode());id=U()
 assert put(C.byref(s),C.byref(e),C.byref(id))==0;model[id.value]=(start,e.end,e.title)
e=Event(0,0,1,0,b'overflow');id=U(999);before=bytes(s)
assert put(C.byref(s),C.byref(e),C.byref(id))==-3 and id.value==999 and bytes(s)==before
for _ in range(250):
 start=rng.randrange(-11000,10000);end=start+rng.randrange(1,2000);capacity=rng.randrange(65);ids=(U*64)();total=U()
 expected=sorted((k for k,(a,b,_) in model.items() if a<end and b>start),key=lambda k:(model[k][0],k))
 r=query(C.byref(s),start,end,ids,capacity,C.byref(total))
 assert r==min(capacity,len(expected)) and total.value==len(expected) and list(ids)[:r]==expected[:r]
assert query(C.byref(s),-20000,20000,None,0,C.byref(total))==0 and total.value==64
first=next(iter(model));updated=Event(first,0,86400,1,b'all day');assert put(C.byref(s),C.byref(updated),C.byref(id))==0 and id.value==first
assert get(C.byref(s),first,C.byref(e))==0 and e.title==b'all day'
assert delete(C.byref(s),first)==0 and get(C.byref(s),first,C.byref(e))==-4
new=Event(0,1,2,0,b'new');assert put(C.byref(s),C.byref(new),C.byref(id))==0 and id.value==65
for bad in (Event(0,1,1,0,b'x'),Event(0,1,2,1,b'x'),Event(0,1,2,2,b'x'),Event(0,1,2,0,b''),Event(0,1,2,0,b'\x1b'),Event(0,1,2,0,b'\xc0\x80'),Event(0,1,2,0,b'x'*128)):
 before=bytes(s);assert put(C.byref(s),C.byref(bad),C.byref(id))==-1 and bytes(s)==before
assert valid(None)==-1 and init(None)==-1
print('Calender: PASS (6000 date/epoch/ISO/arithmetic cases, 1500 grids, event capacity/query/update/UTF-8/atomic errors)')
