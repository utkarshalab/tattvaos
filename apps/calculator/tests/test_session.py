"""Exercise session state and interactive terminal, using assembled code."""
import ctypes as C
import subprocess
import sys
from pathlib import Path
lib=C.CDLL(str(Path(sys.argv[1]).resolve()))
init=lib.calc_session_init
init.argtypes=[C.c_void_p]
session=lib.calc_session
session.argtypes=[C.c_void_p,C.c_char_p,C.c_void_p]
session.restype=C.c_int
ctx=C.create_string_buffer(6272)
out=C.create_string_buffer(8192)
init(ctx)

def run(line,expected=None,status=0):
    result=session(ctx,line.encode(),out)
    text=out.value.decode()
    assert result==status,(line,result,text,status)
    if expected is not None:
        assert text==expected,(line,text,expected)
    return text

run('2+3','5\n')
run('ms','Memory updated\n')
run('ans*2','10\n')
run('m+','Memory updated\n')
run('mr','15\n')
run('sqrt(-1)',status=7)
run('ans','15\n') # failed evaluations must not overwrite ans
run('mem+1','16\n')
run('x = sqrt(81)','9\n')
run('y=2*x','18\n')
run('z = pow(x,2) + y','99\n')
run('x = 1/0',status=3)
run('x','9\n')
run('a=1','1\n')
run('b=2','2\n')
run('c=3','3\n')
run('a+b+c','6\n')
run('e=4',status=1)
run('deg','Degrees\n')
run('sin(30)','0.5\n')
run('rad','Radians\n')
run('sin(pi/2)','1\n')
run('precision 4','Precision updated\n')
run('pi','3.142\n')
run('precision 0',status=1)
run('precision 16',status=1)
run('precision 12','Precision updated\n')
run('prog','Programmer mode (64-bit wrapping integers)\n')
run('0xffffffffffffffff','-1\n')
run('ms','Memory updated\n')
run('1','1\n')
run('m+','Memory updated\n')
run('mr','0\n') # integer memory wraps exactly
run('hex','Programmer output base updated\n')
run('0x8000000000000001','8000000000000001\n')
run('ans+1','8000000000000002\n')
run('ms','Memory updated\n')
run('mem^ans','0\n')
run('mr','8000000000000002\n')
run('bin','Programmer output base updated\n')
run('5','101\n')
run('sci','Scientific mode\n')
run('mr','15\n') # independent scientific and exact integer memories
run('1e308','1e+308\n')
run('ms','Memory updated\n')
run('m+',status=2)
run('mem','1e+308\n') # overflowing memory updates must not overwrite memory
run('clear','History cleared\n')
run('history','History is empty\n')
for i in range(20):
    run(str(i),str(i)+'\n')
text=run('history')
assert text==''.join(f'{i} = {i}\n' for i in range(4,20)),text
run('  3 + 4  ','7\n')
run(' '*255,'')
run('1'*256,status=1)
run('mc','Memory updated\n')
run('mr','0\n')
run('reset','Session reset\n')
run('x+ans+mem','0\n')
run('history','x+ans+mem = 0\n')
run('quit','Bye.\n',255)
# Independent caller-owned sessions.
other=C.create_string_buffer(6272)
init(other)
assert session(other,b'ans',out)==0 and out.value==b'0\n'
assert session(ctx,None,out)==1
assert session(None,b'1',out)==6
# Guard caller-owned state/output against accidental writes beyond their bounds.
guarded_ctx=C.create_string_buffer(b'Q'*16 + b'\0'*6272 + b'Q'*16,6304)
guarded_out=C.create_string_buffer(b'R'*16 + b'\0'*8192 + b'R'*16,8224)
ctx_ptr=C.byref(guarded_ctx,16)
out_ptr=C.byref(guarded_out,16)
init(ctx_ptr)
for line in [b'1+'*127+b'1']*20 + [b'history',b'1'*256,b'help',b'reset']:
    session(ctx_ptr,line,out_ptr)
    assert guarded_ctx.raw[:16]==b'Q'*16 and guarded_ctx.raw[-16:]==b'Q'*16
    assert guarded_out.raw[:16]==b'R'*16 and guarded_out.raw[-16:]==b'R'*16
# REPL operation, error recovery, long-line draining, quit and EOF.
exe=str(Path(sys.argv[2]).resolve())
result=subprocess.run([exe],input='2+3\nms\n1/0\nans*2\ndeg\nsin(30)\nprog\nhex\n255\nhistory\nquit\n',text=True,capture_output=True,timeout=5)
assert result.returncode==0,(result.returncode,result.stderr)
assert '5\n' in result.stdout and '10\n' in result.stdout and '0.5\n' in result.stdout
assert 'ff\n' in result.stdout and '255 = ff\n' in result.stdout and 'Bye.' in result.stdout
assert 'zero divisor' in result.stderr
result=subprocess.run([exe],input='1'*300+'\n2+3\nquit\n',text=True,capture_output=True,timeout=5)
assert result.returncode==0 and 'exceeds 255' in result.stderr and '5\n' in result.stdout
result=subprocess.run([exe],input='6*7',text=True,capture_output=True,timeout=5)
assert result.returncode==0 and result.stdout.endswith('42\n')
for args,expected in [(['--deg','sin(30)'],'0.5\n'),(['--science','1/2'],'0.5\n'),(['--programmer','1/2'],'0\n')]:
    result=subprocess.run([exe,*args],capture_output=True,text=True,timeout=3)
    assert result.returncode==0 and result.stdout==expected,(args,result)
print('Session: PASS (memory, ans, modes, history ring, precision, REPL error recovery, EOF)')
