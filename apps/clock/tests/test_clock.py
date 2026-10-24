#!/usr/bin/env python3
"""Deterministic fake clocks, state-machine models and alarm backpressure checks."""
import ctypes as C,random,sys
from pathlib import Path
lib=C.CDLL(str(Path(sys.argv[1]).resolve()));U=C.c_uint64;I=C.c_int64;MAX=(1<<64)-1
class Watch(C.Structure): _fields_=[(n,U) for n in ('state','elapsed','anchor','last','lap_count')]+[('laps',U*32)]
class Timer(C.Structure): _fields_=[(n,U) for n in ('state','remaining','anchor','last')]
class Alarm(C.Structure): _fields_=[('id',U),('due',I),('period',U),('enabled',U)]
class Store(C.Structure): _fields_=[('next_id',U),('records',Alarm*32)]
class Notice(C.Structure): _fields_=[('id',U),('scheduled',I),('observed',I),('missed',U)]
class Sample(C.Structure): _fields_=[('mono',U),('sec',I),('ns',U)]
class Wall(C.Structure): _fields_=[('sec',I),('ns',U)]
MONO=C.CFUNCTYPE(I,C.POINTER(U));REAL=C.CFUNCTYPE(I,C.POINTER(Wall))
class Sources(C.Structure): _fields_=[('monotonic',MONO),('realtime',REAL)]
def fn(n,args):
 f=getattr(lib,'uclock_'+n);f.argtypes=args;f.restype=I;return f
wi=fn('stopwatch_init',[C.POINTER(Watch)]);ws=fn('stopwatch_start',[C.POINTER(Watch),U]);wp=fn('stopwatch_pause',[C.POINTER(Watch),U]);wr=fn('stopwatch_read',[C.POINTER(Watch),U,C.POINTER(U)]);wl=fn('stopwatch_lap',[C.POINTER(Watch),U,C.POINTER(U)])
ti=fn('countdown_init',[C.POINTER(Timer)]);ts=fn('countdown_start',[C.POINTER(Timer),U,U]);tp=fn('countdown_poll',[C.POINTER(Timer),U,C.POINTER(U)]);tpa=fn('countdown_pause',[C.POINTER(Timer),U]);tr=fn('countdown_resume',[C.POINTER(Timer),U])
ai=fn('alarms_init',[C.POINTER(Store)]);put=fn('alarm_put',[C.POINTER(Store),C.POINTER(Alarm),C.POINTER(U)]);get=fn('alarm_get',[C.POINTER(Store),U,C.POINTER(Alarm)]);delete=fn('alarm_delete',[C.POINTER(Store),U]);poll=fn('alarm_poll',[C.POINTER(Store),I,C.POINTER(Notice),U]);sample=fn('read',[C.POINTER(Sources),C.POINTER(Sample)]);parts=fn('duration_parts',[U,C.POINTER(U)])
rng=random.Random(77)
w=Watch();out=U();assert wi(C.byref(w))==0
assert ws(C.byref(w),100)==0 and wr(C.byref(w),150,C.byref(out))==0 and out.value==50
assert wp(C.byref(w),200)==0 and wr(C.byref(w),1000,C.byref(out))==0 and out.value==100
assert ws(C.byref(w),1100)==0 and wl(C.byref(w),1200,C.byref(out))==0 and out.value==200
for i in range(31): assert wl(C.byref(w),1200+i,C.byref(out))==0
before=bytes(w);assert wl(C.byref(w),1300,C.byref(out))==-4 and bytes(w)==before
assert wr(C.byref(w),1200,C.byref(out))==-2 and bytes(w)==before
# Random stopwatch state model, including independent instances and reset.
wi(C.byref(w));now=0;state=elapsed=anchor=0;laps=[]
for _ in range(5000):
 now+=rng.randrange(100);op=rng.choice(('start','pause','read','lap','reset'))
 if op=='reset': wi(C.byref(w));state=elapsed=anchor=0;laps=[];continue
 expected=elapsed+(now-anchor if state==1 else 0)
 if op=='start':
  r=ws(C.byref(w),now)
  if state==1: assert r==-3
  else: assert r==0;state=1;anchor=now
 elif op=='pause':
  r=wp(C.byref(w),now)
  if state!=1: assert r==-3
  else: assert r==0;elapsed=expected;state=2
 elif op=='read': assert wr(C.byref(w),now,C.byref(out))==0 and out.value==expected
 else:
  r=wl(C.byref(w),now,C.byref(out))
  if state!=1: assert r==-3
  elif len(laps)==32: assert r==-4
  else: assert r==0 and out.value==expected;laps.append(expected)
 assert w.state==state and w.elapsed==elapsed and list(w.laps)[:w.lap_count]==laps
wi(C.byref(w));ws(C.byref(w),0);wp(C.byref(w),MAX-1);ws(C.byref(w),MAX-1)
before=bytes(w);assert wr(C.byref(w),MAX,C.byref(out))==0 and out.value==MAX
# Overflow after resume across a large accumulated interval is rejected atomically.
w.elapsed=MAX;w.anchor=MAX-1;before=bytes(w);out.value=555
assert wr(C.byref(w),MAX,C.byref(out))==-2 and bytes(w)==before and out.value==555
t=Timer();assert ti(C.byref(t))==0 and ts(C.byref(t),100,1000)==0
assert tp(C.byref(t),1040,C.byref(out))==0 and out.value==60
assert tpa(C.byref(t),1050)==0 and t.state==2
assert tp(C.byref(t),2000,C.byref(out))==0 and out.value==50
assert tr(C.byref(t),2000)==0
assert tp(C.byref(t),2050,C.byref(out))==1 and out.value==0 and t.state==3
assert tp(C.byref(t),3000,C.byref(out))==0
before=bytes(t);assert tp(C.byref(t),2999,C.byref(out))==-2 and bytes(t)==before
# Relative arithmetic allows durations which would overflow absolute deadlines.
assert ts(C.byref(t),MAX,MAX-5)==0
assert tp(C.byref(t),MAX,C.byref(out))==0 and out.value==MAX-5
for _ in range(2000):
 duration=rng.randrange(1,10000);start=rng.randrange(100000);ts(C.byref(t),duration,start)
 elapsed=rng.randrange(20000);r=tp(C.byref(t),start+elapsed,C.byref(out))
 assert r==int(elapsed>=duration) and out.value==max(0,duration-elapsed)
for duration in (0,1,999999999,1000000000,3600123456789,MAX):
 p=(U*4)();assert parts(duration,p)==0
 seconds,ns=divmod(duration,10**9);hours,rest=divmod(seconds,3600);minutes,seconds=divmod(rest,60)
 assert tuple(p)==(hours,minutes,seconds,ns)
# Sampling never writes caller output on failed/malformed platform samples.
value={'mono':123,'sec':-1,'ns':999999999,'merr':0,'rerr':0}
@MONO
def mono(out): out[0]=value['mono'];return value['merr']
@REAL
def real(out): out[0].sec=value['sec'];out[0].ns=value['ns'];return value['rerr']
sources=Sources(mono,real);samp=Sample()
assert sample(C.byref(sources),C.byref(samp))==0 and (samp.mono,samp.sec,samp.ns)==(123,-1,999999999)
for field,new in (('merr',1),('rerr',-1),('ns',10**9),('sec',253402300800)):
 old=value[field];before=bytes(samp);value[field]=new
 assert sample(C.byref(sources),C.byref(samp))<0 and bytes(samp)==before;value[field]=old
missing=Sources(MONO(),real);assert sample(C.byref(missing),C.byref(samp))==-3
# Sorted simultaneous alarms, backpressure and skipped-period coalescing.
a=Store();assert ai(C.byref(a))==0;ids=[]
for due,period in ((100,0),(90,10),(100,0)):
 alarm=Alarm(0,due,period,1);id=U();assert put(C.byref(a),C.byref(alarm),C.byref(id))==0;ids.append(id.value)
notices=(Notice*32)();before=bytes(a)
assert poll(C.byref(a),125,None,0)==0 and bytes(a)==before
assert poll(C.byref(a),125,notices,1)==1
assert (notices[0].id,notices[0].scheduled,notices[0].observed,notices[0].missed)==(ids[1],90,125,3)
assert poll(C.byref(a),125,notices,32)==2 and [n.id for n in notices[:2]]==[ids[0],ids[2]]
assert poll(C.byref(a),80,notices,32)==0 # backwards wall clock does not duplicate fired occurrences
assert poll(C.byref(a),130,notices,32)==1 and notices[0].id==ids[1] and notices[0].missed==0
# Random queue polls against a Python model, including backwards wall jumps.
ai(C.byref(a));model={}
for _ in range(32):
 alarm=Alarm(0,rng.randrange(-100,101),rng.choice((0,1,7,60)),1);id=U()
 assert put(C.byref(a),C.byref(alarm),C.byref(id))==0;model[id.value]=[alarm.due,alarm.period,True]
for _ in range(1000):
 now=rng.randrange(-200,1000);capacity=rng.randrange(33)
 expected=sorted((k for k,v in model.items() if v[2] and v[0]<=now),key=lambda k:(model[k][0],k))[:capacity]
 r=poll(C.byref(a),now,notices,capacity);assert r==len(expected)
 for n,k in zip(notices[:r],expected):
  due,period,enabled=model[k];missed=(now-due)//period if period else 0
  assert (n.id,n.scheduled,n.observed,n.missed)==(k,due,now,missed)
  if period:model[k][0]=due+(missed+1)*period
  else:model[k][2]=False
alarm=Alarm(0,1,0,1);id=U(777);before=bytes(a)
assert put(C.byref(a),C.byref(alarm),C.byref(id))==-4 and id.value==777 and bytes(a)==before
assert delete(C.byref(a),1)==0 and get(C.byref(a),1,C.byref(alarm))==-5
alarm.id=1
assert put(C.byref(a),C.byref(alarm),C.byref(id))==-5 # deleted IDs cannot update a different slot
alarm.id=0;assert put(C.byref(a),C.byref(alarm),C.byref(id))==0 and id.value==33
ai(C.byref(a));alarm=Alarm(0,253402300799,1,1);assert put(C.byref(a),C.byref(alarm),C.byref(id))==0
assert poll(C.byref(a),253402300799,notices,1)==1 and get(C.byref(a),id,C.byref(alarm))==0 and alarm.enabled==0
assert wi(None)==-1 and ti(None)==-1 and ai(None)==-1
print('Clock: PASS (5000 stopwatch operations, 2000 countdowns, 1000 alarm polls, fake-clock failures, overflow/backpressure)')
