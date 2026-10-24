"""End-to-end checks of the actual assembly shell executable."""
import random
import itertools
import shlex
import subprocess
import sys
from pathlib import Path
exe=str(Path(sys.argv[1]).resolve())
def command(line,expected=None,status=0):
    p=subprocess.run([exe,'-c',line],text=True,capture_output=True,timeout=4)
    assert p.returncode==status,(line,p.returncode,p.stdout,p.stderr)
    if expected is not None:
        assert p.stdout==expected,(line,p.stdout,expected)
    assert not p.stderr,(line,p.stderr)
    return p.stdout

def session(text,expected=None,status=0):
    p=subprocess.run([exe],input=text,text=True,capture_output=True,timeout=5)
    assert p.returncode==status,(p.returncode,p.stdout,p.stderr)
    if expected is not None:
        assert p.stdout==expected,(p.stdout,expected)
    assert not p.stderr,p.stderr
    return p.stdout

command('echo hello world','hello world\n')
command('echo -n "hello world"','hello world')
command('echo "" x',' x\n')
command("echo 'a b' c\\ d \"e f\"",'a b c d e f\n')
command("echo pre' mid 'post",'pre mid post\n')
command("echo 'literal $X' \\\u0024X",'literal $X $X\n')
command('echo x#y # comment','x#y\n')
command('# comment','')
command('   ','')
command('true','')
command('false','',1)
command('not-a-command',status=127)
command('exit 23','',23)
command('exit -1',status=2)
command('exit 256',status=2)
command('exit ""',status=2)
command('help ignored',status=2)
command('version','Utkarsha Shell 0.1.0-dev\n')
help_text=command('help')
for name in ('calc','export','history','exit'):
    assert name+' - ' in help_text
for line in ('echo "unterminated',"echo 'unterminated",'echo trailing\\',
             'echo x | cat','echo x & true','echo x > file',
             'echo ${MISSING','echo $(false)','echo ${}','echo ' + 'x '*256):
    text=command(line,status=2)
    assert text.startswith('ush: syntax error'),(line,text)
assert 'unsafe\n' not in command('echo unsafe; echo "unterminated',status=2)
command('false && echo wrong || echo yes; true || false && echo left','yes\nleft\n')
command('echo one; echo two;','one\ntwo\n')
command('export X=live; echo "$X"','live\n')
command('true || export X=wrong; echo "${X}"','\n')
command('false && exit 7; echo alive','alive\n')
command('exit 7; echo wrong','',7)
command('false && true','',1)
command('true || false','')
for line in ('; true','true;;false','true &&','true ||','true && ; false',
             'true || # missing operand','echo unsafe; echo ${BAD',
             'echo unsafe; echo '+ 'x '*256):
    assert 'unsafe\n' not in command(line,status=2)
command('true; '*128,'')
command('true; '*129,status=2)
for states in itertools.product((0,1),repeat=3):
    for ops in itertools.product((';','&&','||'),repeat=2):
        status=states[0]
        for op,value in zip(ops,states[1:]):
            if op==';' or (op=='&&' and status==0) or (op=='||' and status!=0):
                status=value
        words=['true' if x==0 else 'false' for x in states]
        expression=f'{words[0]} {ops[0]} {words[1]} {ops[1]} {words[2]}; echo $?'
        command(expression,f'{status}\n')
command('echo ' + 'x'*4096,status=2)
command('echo '+'x '*254,('x '*254).rstrip()+'\n') # argc=255 incl command
command('echo '+'x '*255,('x '*255).rstrip()+'\n') # maximum argc=256
session('false\necho $?\nstatus\ntrue\nexit\n','1\n0\n')
session('false\n\n# comment\nexit\n','',1)
session('export X="hello world"\necho "$X" \'$X\' ${X}\nunset X\necho "${X}"\nexit 0\n',
        'hello world $X hello world\n\n')
session('export X=original\nexport X=updated\necho $X\nexit\n','updated\n')
session('export A=one B=two\nenv\nexit\n','A=one\nB=two\n')
session('export 1BAD=x\necho $?\nexit\n','ush: invalid arguments or environment capacity exceeded\n2\n')
session('export A='+ 'x'*256+'\necho $?\nexit\n','ush: invalid arguments or environment capacity exceeded\n2\n')
# Expansion overflow must reject the entire command, without truncated execution.
text='export A='+ 'x'*255+'\necho '+ '$A '*17+'\necho recovered\nexit\n'
assert session(text).endswith('ush: syntax error, unsupported operator, or argument/expansion limit\nrecovered\n')
# Capacity and reclamation; environment values are owned rather than stale argv pointers.
text=''.join(f'export V{i}={i}\n' for i in range(32))
text+='export FULL=x\necho $?\nunset V0\nexport NEW=ok\necho "$NEW" "$V31"\nexit\n'
assert session(text).endswith('2\nok 31\n')
# History bounded ring; command itself is included, clear removes all entries.
text=''.join('echo '+str(i)+'\n' for i in range(40))+'history\nhistory -c\nhistory\nexit\n'
output=session(text)
expected_history=''.join(f'echo {i}\n' for i in range(9,40))+'history\n'
assert output==''.join(f'{i}\n' for i in range(40))+expected_history+'history\n',output
# A long or NUL-bearing line is drained before later commands.
for bad in ('x'*5000,'echo dangerous\x00hidden'):
    output=session(bad+'\necho recovered\nexit\n')
    assert output=='ush: input exceeds 4095 bytes or contains NUL\nrecovered\n',output
session('echo final-no-newline','final-no-newline\n')
session('exit 9\necho should-not-run\n','',9)
# Calculator one-shot dispatch and nested terminal retain calculator state.
command('calc "sqrt(81)+2**3"','17\n')
command('calc -x "0xff << 4"','ff0\n')
session('calc "x=3"\ncalc "x**2"\ncalc\nx+1\nquit\necho back\nexit\n',
        '3\n9\n4\nBye.\nback\n')
session('calc\n1/0\n2+3\nquit\nexit\n',
        'calc: zero divisor or signed integer division overflow\n5\nBye.\n')
# Generated quoted arguments compared against known literal values.
rng=random.Random(23)
for _ in range(120):
    args=[''.join(rng.choice('ab c$;|&"\'\\') for _ in range(rng.randrange(16)))
          for _ in range(rng.randrange(1,12))]
    command('echo -- '+ ' '.join(shlex.quote(x) for x in args),'-- '+' '.join(args)+'\n')
for args in (['-z'],['-c'],['-c','echo a','extra']):
    p=subprocess.run([exe,*args],capture_output=True,timeout=3)
    assert p.returncode==2
p=subprocess.run([exe,'--help'],capture_output=True,text=True,timeout=3)
assert p.returncode==0 and p.stdout.startswith('Usage:')
print('Ush: PASS (quoting, expansion, dispatch, variables, limits, history, exit, calculator, EOF, 120 generated cases)')
