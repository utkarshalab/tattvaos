"""Real PTY checks of the common editor and Linux terminal restoration."""
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import fcntl
from pathlib import Path
exe=str(Path(sys.argv[1]).resolve())
master,slave=pty.openpty()
fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
original=termios.tcgetattr(slave)
proc=subprocess.Popen([exe],stdin=slave,stdout=slave,stderr=slave,start_new_session=True)
transcript=bytearray()
def wait(needle,start=0):
    end=time.monotonic()+5
    while needle not in transcript[start:]:
        assert time.monotonic()<end,(needle,bytes(transcript[start:]))
        ready,_,_=select.select([master],[],[],.1)
        if ready:
            transcript.extend(os.read(master,65536))
def send(keys,result=None,prompt=b'ush> '):
    start=len(transcript)
    os.write(master,keys)
    wait(prompt,start)
    if result is not None:
        wait(b'\r\n'+result+b'\r\n',start)
try:
    wait(b'ush> ')
    start=len(transcript)
    os.write(master,b'echo ac\x1b[D')
    wait(b'\r\x1b[2Kush> echo ac\x1b[1D',start)
    start=len(transcript)
    os.write(master,b'b')
    wait(b'\r\x1b[2Kush> echo abc\x1b[1D',start)
    send(b'\r',b'abc')
    send(b'echo abxc\x1b[D\x1b[D\x1b[3~\r',b'abc')
    send(b'cho home\x01e\x05!\r',b'home!')
    send(b'echo recall\r',b'recall')
    send(b'\x1b[Aed\r',b'recalled')
    send(b'echo draft\x1b[A\x1b[B\r',b'draft')
    send(b'export BAD=oops\x03')
    send(b'echo $?\r',b'130')
    send(b'echo "${BAD}"\r',b'')
    send(b'echo abxc\x01'+b'\x1b[C'*7+b'\x04\x05\r',b'abc')
    send(b'echo '+b'A'*95+b'\x01'+b'\x1b[C'*5+b'B\r',b'B'+b'A'*95)
    send(b'echo wrong\x15echo clear\r',b'clear')
    send(b'echo cut-tail\x01'+b'\x1b[C'*8+b'\x0b\r',b'cut')
    send(b'calc "x=9"\r',b'9')
    send(b'calc\r',prompt=b'calc> ')
    send(b'x+4\x03',prompt=b'calc> ')
    send(b'x\r',b'9',prompt=b'calc> ')
    send(b'\x04')
    os.write(master,b'exit 0\r')
    assert proc.wait(timeout=5)==0
    assert termios.tcgetattr(slave)==original,'terminal state not restored on exit'
finally:
    if proc.poll() is None:
        proc.terminate()
        proc.wait(timeout=5)
    os.close(master)
    os.close(slave)
# External signals must restore termios too.
master,slave=pty.openpty()
original=termios.tcgetattr(slave)
proc=subprocess.Popen([exe],stdin=slave,stdout=slave,stderr=slave,start_new_session=True)
try:
    transcript=bytearray()
    wait(b'ush> ')
    proc.send_signal(signal.SIGTERM)
    assert proc.wait(timeout=5)==143
    assert termios.tcgetattr(slave)==original,'terminal state not restored on SIGTERM'
finally:
    if proc.poll() is None:
        proc.kill()
        proc.wait(timeout=5)
    os.close(master)
    os.close(slave)
print('Ush PTY: PASS (cursor editing, delete, history/draft, viewport, Ctrl-C/D, calculator, termios restoration)')
