#!/usr/bin/env python3
"""Actual NASM core/session regression checks; no replacement editor model."""
import ctypes as C
from collections import deque
from pathlib import Path
import random
import re
import sys
lib = C.CDLL(str(Path(sys.argv[1]).resolve()))
class Context(C.Structure):
    _fields_ = [(k, C.c_uint64) for k in ('length','cursor','top','left','goal','crlf','dirty')] + [('data',C.c_ubyte*4096)]
lib.uedit_load.argtypes = [C.POINTER(Context), C.c_void_p, C.c_uint64]
lib.uedit_load.restype = C.c_int64
lib.uedit_key.argtypes = [C.POINTER(Context), C.c_uint64]
lib.uedit_key.restype = C.c_int64
ctx = Context()
def load(data): return lib.uedit_load(C.byref(ctx),data,len(data))
def contents(): return bytes(ctx.data[:ctx.length])
def key(code): return lib.uedit_key(C.byref(ctx),code)
LEFT,RIGHT,UP,DOWN,HOME,END,DELETE,BACKSPACE,PAGEUP,PAGEDOWN=range(256,266)
assert load(b'long line\nx\nlong line') == 0
for _ in range(7): key(RIGHT)
key(DOWN); assert ctx.cursor == 11
key(DOWN); assert ctx.cursor == 19
key(DOWN); assert ctx.cursor == 19
key(UP); key(UP); assert ctx.cursor == 7 and not ctx.dirty
key(HOME); assert ctx.cursor == 0
key(END); assert ctx.cursor == 9
assert load(b'\tAB\n12345\n\tAB') == 0
key(RIGHT); key(DOWN); assert ctx.cursor == 8
key(DOWN); assert ctx.cursor == 11
rng=random.Random(18)
assert load(b'') == 0
reference=bytearray(); cursor=0
for _ in range(7000):
    code=rng.choice([LEFT,RIGHT,HOME,END,DELETE,BACKSPACE,9,10,32,65,98,126])
    result=key(code)
    if code<256:
        reference[cursor:cursor]=bytes([code]); cursor+=1; assert result==1
    elif code==LEFT: cursor=max(0,cursor-1)
    elif code==RIGHT: cursor=min(len(reference),cursor+1)
    elif code==HOME: cursor=reference.rfind(b'\n',0,cursor)+1
    elif code==END:
        end=reference.find(b'\n',cursor); cursor=len(reference) if end<0 else end
    elif code==BACKSPACE and cursor:
        del reference[cursor-1]; cursor-=1
    elif code==DELETE and cursor<len(reference): del reference[cursor]
    assert ctx.cursor==cursor and contents()==reference,(code,cursor,ctx.cursor)
assert load(b'x'*4096)==0
assert key(65)==-2 and ctx.cursor==0 and not ctx.dirty
key(DELETE); assert ctx.length==4095
key(10); assert ctx.length==4096
for invalid in (b'\0',b'\x1b',b'\r',b'\x7f',b'\xc0\x80',b'\xed\xa0\x80',b'\xf4\x90\x80\x80',b'\xe2\x82',b'\xc2\x85',b'x'*4097):
    before=bytes(ctx); assert load(invalid)==-1 and bytes(ctx)==before,invalid
for text in ('caf\u00e9\r\n\u4e16\u754c\U0001f642\tend','e\u0301\n\U00010400','\r\n\r\n','a\nB\r\nC'):
    raw=text.encode(); assert load(raw)==0
    boundaries=[0]; offset=0
    while offset<len(raw):
        offset+=2 if raw[offset:offset+2]==b'\r\n' else len(raw[offset:].decode()[0].encode())
        boundaries.append(offset)
    for boundary in boundaries[1:]: key(RIGHT); assert ctx.cursor==boundary
    for boundary in boundaries[-2::-1]: key(LEFT); assert ctx.cursor==boundary
for scalar in ('\u00e9','\u0100','\u4e16','\U0001f642','\U00010400','\u0301'):
    assert load(b'')==0
    assert key(0x200000+ord(scalar))==1 and contents()==scalar.encode(),scalar
    assert key(BACKSPACE)==1 and contents()==b''
assert load(b'a\r\nb')==0
key(RIGHT); key(RIGHT); assert ctx.cursor==3
key(BACKSPACE); assert contents()==b'ab'

# Differential edits on mixed-width Unicode scalars and retained CRLF style.
assert load(b'a\r\nb')==0
model=['a','\r\n','b']; pos=0
for _ in range(8000):
    op=rng.choice(['left','right','home','end','bs','del','\t','\n','A','\u0100','\u4e16','\U0001f642','\u0301','\u0928'])
    before=bytes(ctx)
    if op in ('left','right','home','end','bs','del'):
        code={'left':LEFT,'right':RIGHT,'home':HOME,'end':END,'bs':BACKSPACE,'del':DELETE}[op]
        result=key(code)
        if op=='left': pos=max(0,pos-1)
        elif op=='right': pos=min(len(model),pos+1)
        elif op=='home':
            while pos and model[pos-1]!='\r\n': pos-=1
        elif op=='end':
            while pos<len(model) and model[pos]!='\r\n': pos+=1
        elif op=='bs' and pos: del model[pos-1]; pos-=1
        elif op=='del' and pos<len(model): del model[pos]
    else:
        inserted='\r\n' if op=='\n' else op
        n=len(''.join(model).encode())+len(inserted.encode())
        result=key(ord(op) if ord(op)<128 else 0x200000+ord(op))
        if n<=4096: model[pos:pos]=[inserted]; pos+=1; assert result==1
        else: assert result==-2 and bytes(ctx)==before
    assert contents()==''.join(model).encode() and ctx.cursor==len(''.join(model[:pos]).encode()),op
READ=C.CFUNCTYPE(C.c_int64)
WRITE=C.CFUNCTYPE(None,C.c_void_p,C.c_uint64)
SAVE=C.CFUNCTYPE(C.c_int64,C.c_void_p,C.c_uint64)
SIZE=C.CFUNCTYPE(None,C.POINTER(C.c_uint64),C.POINTER(C.c_uint64))
class IO(C.Structure):
    _fields_=[('read',READ),('write',WRITE),('save',SAVE),('size',SIZE)]
lib.uedit_run.argtypes=[C.POINTER(IO),C.c_void_p,C.c_uint64,C.c_char_p,C.c_uint64]
lib.uedit_run.restype=C.c_int64
def session(data,keys,*,new=False,fail_saves=0,inject_log=False,sizes=None):
    pending=deque(keys); output=bytearray(); saves=[]; errors=[]; injected=False
    current=[80,24]
    @READ
    def read():
        nonlocal injected
        if inject_log and not injected:
            injected=True; lib.uedit_log_begin(); output.extend(b'BACKGROUND\n'); lib.uedit_redraw()
        if not pending: return -1
        value=pending.popleft()
        if isinstance(value,tuple): current[:]=value; return -2
        return value
    @WRITE
    def write(ptr,count):
        if count>65536: errors.append(count)
        output.extend(C.string_at(ptr,count))
    @SAVE
    def save(ptr,count):
        saves.append(C.string_at(ptr,count)); return -5 if len(saves)<=fail_saves else 0
    @SIZE
    def size(cols,rows): cols[0],rows[0]=current
    io=IO(read,write,save,size if sizes else SIZE())
    result=lib.uedit_run(C.byref(io),data,len(data),b'/document',new)
    assert not errors and C.c_uint64.in_dll(lib,'uedit_active').value==0
    return result,bytes(output),saves
result,output,saves=session(b'abc',b'\x1b[Cb\x13\x11')
assert result==0 and saves==[b'abbc'] and b'Saved' in output
assert b'\x1b[?1049h' in output and b'\x1b[?1049l' in output
result,output,saves=session(b'original',b'x\x11\x03\x11\x11')
assert result==0 and not saves and output.count(b'Unsaved changes!')==2 and b'Quit cancelled' in output
result,output,saves=session(b'',b'\x13\x11',new=True)
assert result==0 and saves==[b'']
result,output,saves=session(b'abc',b'X\x13\x13\x11',fail_saves=1)
assert result==0 and saves==[b'Xabc',b'Xabc'] and b'Save failed; changes retained' in output
result,output,saves=session(b'abc',b'X')
assert result==1 and not saves and b'unsaved changes were not saved' in output
result,output,saves=session(b'\x00binary',b'\x13\x11')
assert result==-1 and not output and not saves
result,output,saves=session(b'abc\ndef',b'\x1b[B\x1b[F!\x1b[H\x1b[3~\t\x13\x11',inject_log=True)
assert result==0 and saves==[b'abc\n\tef!'] and b'BACKGROUND' in output
# Native scalar encoding/decoding and CRLF-preserving Enter.
result,output,saves=session('caf\u00e9\r\n\u4e16\u754c'.encode(),b'\x1b[F'+'\U0001f642'.encode()+b'\r!\x13\x11')
assert result==0 and saves==['caf\u00e9\U0001f642\r\n!\r\n\u4e16\u754c'.encode()],saves
result,output,saves=session(b'abc',b'X\x1a\x19\x13\x1a\x13\x19\x13\x11')
assert saves==[b'Xabc',b'abc',b'Xabc'] and result==0,saves
result,output,saves=session(b'',b'AB\x1aC\x19\x13\x11')
assert saves==[b'AC'],saves
result,output,saves=session(b'',b'x'*80+b'\x1a'*70+b'\x13\x11')
assert saves==[b'x'*17],saves
result,output,saves=session('\u00e9\u754c!'.encode(),b'\x02\x1b[C\x1b[C\x03\x1b[F\x16\x13\x11')
assert saves==['\u00e9\u754c!\u00e9\u754c'.encode()],saves
result,output,saves=session(b'abc',b'\x02\x1b[C\x1b[C\x18\x1a\x19\x16\x13\x11')
assert saves==[b'abc'],saves
result,output,saves=session(b'abc',b'\x02\x1b[C\x1b[CZ\x1a\x19\x13\x11')
assert saves==[b'Zc'],saves
result,output,saves=session(b'cat cat',b'\x06cat\r\x0e\x12dog\r\x12\x13\x11')
assert saves==[b'cat dog'] and b'Found' in output,saves
result,output,saves=session('\u00e9 \u00e9'.encode(),b'\x06'+'\u00e9'.encode()+b'\r\x12'+'\u4e16\u754c'.encode()+b'\r\x01\x1a\x19\x13\x11')
assert saves==['\u4e16\u754c \u4e16\u754c'.encode()],(result,saves,output[-3000:])
result,output,saves=session(b'x'*4096,b'\x06x\r\x12xx\r\x01\x13\x11')
assert saves==[b'x'*4096] and b'File limit' in output
result,output,saves=session(b'abc',b'\x06missing\r\x12\x03\x13\x11')
assert saves==[b'abc'] and b'Text not found' in output
# Frame interpreter checks actual cells/cursor for ASCII, wide and combining text.
import unicodedata as U
def screen(output,cols=80,rows=24):
    frame=re.findall(rb'\x1b\[\?25l(.*?)\x1b\[\?25h',output,re.S)[-1].decode()
    cells=[[' ']*cols for _ in range(rows)]; row=col=offset=0
    while offset<len(frame):
        if frame[offset]=='\x1b':
            m=re.match(r'\x1b\[([0-9;?]*)([A-Za-z])',frame[offset:]); assert m,frame[offset:]
            params,command=m.groups()
            if command=='H':
                values=params.split(';') if params else ['1','1']; row,col=int(values[0])-1,int(values[1])-1
            elif command=='K':
                assert params=='2'; cells[row]=[' ']*cols
            offset+=m.end()
        else:
            ch=frame[offset]; width=0 if U.category(ch) in ('Mn','Me','Cf') else (2 if U.east_asian_width(ch) in ('W','F') else 1)
            assert 0<=row<rows and 0<=col<cols,(row,col,ch)
            if width: cells[row][col]=ch
            col+=width; offset+=1
    return [''.join(line) for line in cells],(row,col)
data=b'0123456789'*12
result,output,saves=session(data,b'\x1b[F\x13\x11')
cells,cursor=screen(output); assert cells[1][:77]==data[43:].decode() and cursor==(1,77)
data=b'\n'.join(f'L{i:02}'.encode() for i in range(35))
result,output,saves=session(data,b'\x1b[6~\x1b[6~\x13\x11')
cells,cursor=screen(output); assert cells[1].startswith('L13') and cells[22].startswith('L34') and cursor==(22,0)
result,output,saves=session(b'\tAB',b'\x1b[C\x13\x11')
cells,cursor=screen(output); assert cells[1].startswith('    AB') and cursor==(1,4)
result,output,saves=session('e\u0301\u754c'.encode(),b'\x1b[F\x13\x11')
cells,cursor=screen(output); assert cursor==(1,3) and cells[1].startswith('e\u754c ')
keys=[(100,35),END,(40,10),END,(120,40),19,17]
# Events are raw bytes except resize tuples.
keys=[(100,35),27,91,70,(40,10),27,91,70,(120,40),19,17]
result,output,saves=session(b'a'*180+b'\n'+b'b\n'*40,keys,sizes=True)
cells,cursor=screen(output,120,40); assert saves and cursor==(1,37),cursor

for cols,rows in ((20,4),(40,10),(240,100),(10,2),(1,1)):
    result,output,saves=session(b'long title text\n'+b'x\n'*60,[(cols,rows),19,17],sizes=True)
    cells,cursor=screen(output,cols,rows)
    assert saves and 0<=cursor[0]<rows and 0<=cursor[1]<cols,(cols,rows,cursor)
result,output,saves=session(b'\r\n',b'\x04\r\x13\x11')
assert saves==[b'\r\n'],saves
result,output,saves=session(b'a\r\nb',b'\x02\x1b[C\x1b[C\r\x13\x11')
assert saves==[b'\r\nb'],saves
# Invalid input, oversized paste and missing search leave document/history intact.
result,output,saves=session(b'ab',b'\x02\x1b[F\x03'+b'X'*4094+b'\x16\x13\x11')
assert saves==[b'ab'+b'X'*4094] and b'File limit' in output
result,output,saves=session(b'clean',b'X\x1a\x11')
assert result==0 and not saves and b'Unsaved changes!' not in output

result,output,saves=session(b'abc',b'\xe2\x13\x11')
assert saves==[b'abc'] and b'Invalid UTF-8' in output
# Mixed endings are byte-preserved; a document retains CRLF style after deletion.
result,output,saves=session(b'a\nb\r\nc',b'\x13\x11')
assert saves==[b'a\nb\r\nc']

result,output,saves=session(b'abc',b'\x1bOC\x1bOF!\x1bOH\x13\x11')
assert saves==[b'abc!']
result,output,saves=session(b'x'*120,b'\x1b[8;10;40t\x1b[F\x13\x11')
cells,cursor=screen(output,40,10)
assert cursor==(1,37) and saves==[b'x'*120]

# Random literal replacements compare the native atomic operation with Python.
lib.ue_change.argtypes=[C.POINTER(Context),C.c_void_p,C.c_uint64,C.c_void_p,C.c_uint64,C.c_uint64]
lib.ue_change.restype=C.c_int64
for _ in range(350):
    original=''.join(rng.choice(['a','b','\u00e9','\u754c',' ']) for _ in range(rng.randrange(1,90))).encode()
    query=''.join(rng.choice(['a','b','\u00e9','\u754c',' ']) for _ in range(rng.randrange(1,4))).encode()
    repl=''.join(rng.choice(['x','\u4e16',' ']) for _ in range(rng.randrange(0,5))).encode()
    assert load(original)==0
    expected=original.replace(query,repl)
    result=lib.ue_change(C.byref(ctx),query,len(query),repl,len(repl),1)
    assert contents()==expected and result==(1 if query in original else 0),(original,query,repl,contents())

# Every intermediate frame must fit: selection help is longer than the viewport.
for data,keys in ((b'abc',b'\x02\x1b[C\x03\x11'),(b'abc',b'\x06'+b'q'*100+b'\r\x11')):
    result,output,saves=session(data,keys)
    for frame in re.findall(rb'\x1b\[\?25l(.*?)\x1b\[\?25h',output,re.S):
        screen(b'\x1b[?25l'+frame+b'\x1b[?25h')
print('Uedit: PASS (15000 reference edits, 350 replacements, UTF-8/CRLF, history, clipboard, search/replace, save failures, resize/width/log rendering)')
