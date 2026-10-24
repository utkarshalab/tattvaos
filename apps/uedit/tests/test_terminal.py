#!/usr/bin/env python3
"""Real PTY/Ush/UXFS integration: editing, durable save, discard and cleanup."""
import fcntl
import importlib.util
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[3]
EXE = str(Path(sys.argv[1]).resolve())
spec = importlib.util.spec_from_file_location('mkvolume', ROOT/'storage/uxfs/mkvolume.py')
fmt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fmt)

def image(path, entries=()):
    raw = bytearray(fmt.image())
    for i, (name, kind, data) in enumerate(entries, 1):
        at = 512+i*fmt.NODE
        encoded = name.encode()+b'\0'
        raw[at:at+len(encoded)] = encoded
        struct.pack_into('<QQ', raw, at+240, kind, len(data))
        raw[at+256:at+256+len(data)] = data
    struct.pack_into('<Q', raw, 24, fmt.checksum(raw[512:fmt.BANK*512]))
    struct.pack_into('<Q', raw, 32, 0)
    struct.pack_into('<Q', raw, 32, fmt.checksum(raw[:512]))
    path.write_bytes(raw)

def files(path):
    raw = path.read_bytes()
    banks = []
    for bank in range(2):
        offset = bank*fmt.BANK*512
        header = bytearray(raw[offset:offset+512])
        magic, version, generation, checksum, header_sum = struct.unpack_from('<5Q', header)
        if magic != fmt.MAGIC or version != 2:
            continue
        struct.pack_into('<Q', header, 32, 0)
        body = raw[offset+512:offset+fmt.BANK*512]
        if fmt.checksum(header) == header_sum and fmt.checksum(body) == checksum:
            banks.append((generation, body))
    assert banks
    body = max(banks, key=lambda x:x[0])[1]
    result = {}
    for i in range(fmt.NODES):
        record = body[i*fmt.NODE:(i+1)*fmt.NODE]
        kind, length = struct.unpack_from('<QQ', record, 240)
        if kind:
            result[record[:240].split(b'\0', 1)[0].decode()] = record[256:256+length]
    return result

class Terminal:
    def __init__(self, disk, rows=24, cols=80):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        self.original = termios.tcgetattr(self.slave)
        self.output = bytearray()
        self.proc = subprocess.Popen([EXE, '--disk', str(disk)], stdin=self.slave,
                                     stdout=self.slave, stderr=self.slave, start_new_session=True)
    def __enter__(self):
        self.wait(b'ush> ')
        return self
    def wait(self, needle, start=0):
        deadline = time.monotonic()+8
        while needle not in self.output[start:]:
            assert time.monotonic() < deadline, (needle, bytes(self.output[start:])[-2000:])
            ready, _, _ = select.select([self.master], [], [], .05)
            if ready:
                chunk = os.read(self.master, 65536)
                assert chunk, self.proc.poll()
                self.output.extend(chunk)
        return self.output.index(needle, start)+len(needle)
    def keys(self, keys, expected):
        start = len(self.output)
        os.write(self.master, keys)
        return self.wait(expected, start)
    def command(self, text, expected=b'ush> '):
        start = len(self.output)
        os.write(self.master, text.encode()+b'\r')
        entered = self.wait(text[-63:].encode()+b'\r\n', start)
        return self.wait(expected, entered)
    def edit(self, path):
        return self.command('uedit '+path, b'Ctrl-S Save | Ctrl-Q Quit | Ready')
    def quit_editor(self, keys=b'\x11'):
        closed = self.keys(keys, b'Uedit closed.\r\n')
        self.wait(b'ush> ', closed)
    def finish(self):
        os.write(self.master, b'exit 0\r')
        assert self.proc.wait(timeout=5) == 0
        assert termios.tcgetattr(self.slave) == self.original
    def __exit__(self, *args):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        os.close(self.master)
        os.close(self.slave)

with tempfile.TemporaryDirectory() as directory:
    disk = Path(directory)/'data.uxfs'
    image(disk)
    with Terminal(disk) as terminal:
        terminal.edit('/new')
        assert '/new' not in files(disk)  # opening a new document does not create it
        terminal.keys(b'first\rsecond\tline\x13', b'Ctrl-S Save | Ctrl-Q Quit | Saved')
        assert files(disk)['/new'] == b'first\nsecond\tline'
        terminal.quit_editor()
        before = disk.read_bytes()
        terminal.edit('/new')
        terminal.keys(b'X\x11', b'Unsaved changes! Ctrl-Q again discards')
        terminal.keys(b'\x03', b'Quit cancelled')
        terminal.keys(b'\x11', b'Unsaved changes! Ctrl-Q again discards')
        terminal.quit_editor()
        assert disk.read_bytes() == before
        terminal.edit('/new')
        terminal.keys(b'\x1b[B\x1b[F\x7f\x1b[H\x1b[3~\x1b[A\x1b[F!\x13',
                      b'Ctrl-S Save | Ctrl-Q Quit | Saved')
        assert files(disk)['/new'] == b'first!\necond\tlin'
        terminal.quit_editor()
        terminal.edit('/not-created')
        terminal.keys(b'\x11', b'Unsaved changes! Ctrl-Q again discards')
        terminal.quit_editor()
        assert '/not-created' not in files(disk)
        terminal.command('mkdir /dir')
        start = len(terminal.output)
        terminal.command('uedit /dir')
        assert b'uedit: requires' in terminal.output[start:] and b'\x1b[?1049h' not in terminal.output[start:]
        terminal.command('echo EDITOR_RETURNED')
        terminal.finish()
    assert subprocess.check_output([EXE, '--disk', str(disk), '-c', 'cat /new']) == b'first!\necond\tlin'
    # A signal while editing restores both termios and the primary screen;
    # it never silently saves the unsaved buffer.
    before = disk.read_bytes()
    with Terminal(disk) as terminal:
        terminal.edit('/new')
        terminal.keys(b'Z', b'Uedit /new *')
        start = len(terminal.output)
        terminal.proc.send_signal(signal.SIGTERM)
        assert terminal.proc.wait(timeout=5) == 143
        terminal.wait(b'\x1b[?1049l', start)
        assert termios.tcgetattr(terminal.slave) == terminal.original
    assert disk.read_bytes() == before
    with Terminal(disk, rows=10, cols=40) as terminal:
        terminal.command('uedit /new', b'Ready')
        terminal.keys(b'\x0c', b'\x1b[10;1H')
        terminal.quit_editor()
        terminal.finish()
    image(disk, [('/binary', 1, b'\0binary'), ('/crlf', 1, b'line\r\n'), ('/full', 1, b'x'*4096)]
          + [(f'/f{i}', 1, b'') for i in range(60)])
    before = disk.read_bytes()
    with Terminal(disk) as terminal:
        for path in ('/binary',):
            start = len(terminal.output)
            terminal.command('uedit '+path)
            assert b'UTF-8/LF/CRLF/TAB' in terminal.output[start:] and b'\x1b[?1049h' not in terminal.output[start:]
        terminal.edit('/crlf')
        terminal.quit_editor()
        terminal.edit('/full')
        terminal.keys(b'!', b'File limit: 4096 bytes')
        terminal.quit_editor()
        terminal.edit('/overflow')
        terminal.keys(b'X\x13', b'Save failed; changes retained')
        terminal.keys(b'\x11', b'Unsaved changes! Ctrl-Q again discards')
        terminal.quit_editor()
        terminal.finish()
    assert disk.read_bytes() == before
    result = subprocess.run([EXE, '--disk', str(disk), '-c', 'uedit /full'], capture_output=True)
    assert result.returncode == 1 and b'\x1b[?1049h' not in result.stdout


    # Every new feature through the real frontend and persistent volume.
    image(disk, [('/unicode', 1, 'caf\u00e9\r\n\u4e16\u754c'.encode())])
    with Terminal(disk) as terminal:
        terminal.edit('/unicode')
        terminal.keys(b'\x1b[F'+'\U0001f642'.encode()+b'\r!', b'Ready')
        terminal.keys(b'\x1a', b'Undo')
        terminal.keys(b'\x19', b'Redo')
        terminal.keys(b'\x06'+'\u4e16\u754c'.encode()+b'\r', b'Found')
        terminal.keys(b'\x12world\r\x01', b'Replaced')
        terminal.keys(b'\x06world\r\x02\x1b[C\x1b[C\x03\x1b[F\x16\x13', b'Saved')
        expected='caf\u00e9\U0001f642\r\n!\r\nworldwo'.encode()
        assert files(disk)['/unicode']==expected,files(disk)
        for rows,cols in ((35,100),(10,40),(2,10),(24,80)):
            fcntl.ioctl(terminal.slave,termios.TIOCSWINSZ,struct.pack('HHHH',rows,cols,0,0))
            start=len(terminal.output)
            terminal.proc.send_signal(signal.SIGWINCH)
            terminal.wait(b'\x1b[?25h',start)
            frame=bytes(terminal.output[start:])
            assert b'\x1b[?1049l' not in frame
            assert (f'\x1b[{rows};1H'.encode() in frame) if rows>=4 else b'Resize' in frame
        terminal.quit_editor()
        terminal.edit('/unicode')
        terminal.keys(b'\x06world\r\x02\x1b[C\x1b[C\x18\x1a\x13',b'Saved')
        assert files(disk)['/unicode']==expected
        terminal.quit_editor()
        terminal.finish()
    assert subprocess.check_output([EXE,'--disk',str(disk),'-c','cat /unicode'])==expected

print('Uedit PTY: PASS (persistent save/edit/discard, return to Ush, full/invalid files, signal/terminal cleanup)')
