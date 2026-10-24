#!/usr/bin/env python3
"""Boot the real kernel and drive Ush through a QEMU serial socket."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import select
import shutil
import socket
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]
BOOT=ROOT/'boot'
LOGS=ROOT/'apps/ush/build'

def test(firmware,smp,strict_nx=False,data_disk=None,storage_phase=None,power_action=None,editor_phase=None,native_time=False):
    LOGS.mkdir(parents=True,exist_ok=True)
    label=f'{firmware}-{smp}cpu'+('-strictnx' if strict_nx else '')
    if native_time:
        label+='-native-time'
    if storage_phase:
        label+='-uxfs-'+storage_phase
    if power_action:
        label+='-power-'+power_action
    if editor_phase:
        label+='-uedit-'+editor_phase
    log=LOGS/f'qemu-{label}.log'
    stderr=LOGS/f'qemu-{label}.stderr'
    boot_digest=hashlib.sha256((BOOT/'utkarsha.img').read_bytes()).digest() if firmware=='bios' else None
    transcript=bytearray()
    proc=None
    serial=None
    qmp=None
    with tempfile.TemporaryDirectory(prefix='utkarsha-ush-') as work:
        work=Path(work)
        path=work/'serial.sock'
        args=['qemu-system-x86_64','-accel','tcg','-cpu','max','-smp',str(smp),
              '-m','512','-netdev','user,id=n0','-device','e1000,netdev=n0',
              '-display','none','-monitor','none','-no-reboot','-no-shutdown',
              '-serial',f'unix:{path},server=on,wait=off']
        if native_time:
            args+=['-rtc','base=2026-10-24T00:00:00,clock=vm']
        if power_action:
            args+=['-qmp',f'unix:{work / "qmp.sock"},server=on,wait=off']
            args.remove('-no-reboot' if power_action=='reboot' else '-no-shutdown')
        if firmware=='bios':
            args+=['-drive',f'file={BOOT / "utkarsha.img"},format=raw,if=ide']
        else:
            esp=work/'esp'
            (esp/'EFI/BOOT').mkdir(parents=True)
            shutil.copy2(BOOT/'BOOTX64.EFI',esp/'EFI/BOOT/BOOTX64.EFI')
            shutil.copy2(BOOT/'kernel.bin',esp/'kernel.ulf')
            varsfile=work/'vars.fd'
            shutil.copy2('/usr/share/OVMF/OVMF_VARS_4M.fd',varsfile)
            code=('/usr/share/OVMF/OVMF_CODE_4M.secboot.strictnx.fd' if strict_nx
                  else '/usr/share/OVMF/OVMF_CODE_4M.fd')
            args+=['-machine','q35','-drive',f'if=pflash,format=raw,unit=0,readonly=on,file={code}',
                   '-drive',f'if=pflash,format=raw,unit=1,file={varsfile}',
                   '-drive',f'format=raw,file=fat:rw:{esp}']
        if data_disk is not None:
            if firmware=='bios':
                args+=['-drive',f'file={data_disk},format=raw,if=ide,index=2,cache=writeback']
            else:
                args+=['-device','piix3-ide,id=uxide',
                       '-drive',f'file={data_disk},format=raw,if=none,id=uxdata,cache=writeback',
                       '-device','ide-hd,drive=uxdata,bus=uxide.1,unit=0']
        try:
            with stderr.open('wb') as err:
                proc=subprocess.Popen(args,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=err)
                serial=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
                deadline=time.monotonic()+10
                while True:
                    try:
                        serial.connect(str(path))
                        break
                    except (FileNotFoundError,ConnectionRefusedError):
                        if proc.poll() is not None or time.monotonic()>deadline:
                            raise RuntimeError('QEMU serial socket did not start')
                        time.sleep(.05)
                serial.setblocking(False)
                if power_action:
                    qmp=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
                    qmp.connect(str(work/'qmp.sock'))
                    qmp.setblocking(False)
                    qmp_buffer=bytearray()
                    def qmp_until(predicate,timeout=15):
                        deadline=time.monotonic()+timeout
                        while True:
                            while b'\n' in qmp_buffer:
                                line,_,rest=qmp_buffer.partition(b'\n')
                                qmp_buffer[:]=rest
                                message=json.loads(line)
                                if predicate(message):
                                    return message
                            if time.monotonic()>deadline:
                                raise TimeoutError('missing QMP event/response')
                            ready,_,_=select.select([qmp],[],[],.2)
                            if ready:
                                chunk=qmp.recv(65536)
                                if not chunk:
                                    raise RuntimeError('QMP closed before expected event')
                                qmp_buffer.extend(chunk)
                    qmp_until(lambda m:'QMP' in m)
                    qmp.sendall(b'{"execute":"qmp_capabilities"}\n')
                    qmp_until(lambda m:'return' in m)
                def receive_until(needle,start=0,timeout=18):
                    deadline=time.monotonic()+timeout
                    while needle not in transcript[start:]:
                        if proc.poll() is not None:
                            raise RuntimeError(f'QEMU exited {proc.returncode}')
                        if time.monotonic()>deadline:
                            raise TimeoutError(f'missing {needle!r}; see {log}')
                        ready,_,_=select.select([serial],[],[],.2)
                        if ready:
                            chunk=serial.recv(65536)
                            if not chunk:
                                raise RuntimeError('QEMU closed the serial socket')
                            transcript.extend(chunk)
                    return transcript.index(needle,start)+len(needle)
                receive_until(b'ush> ',timeout=100)
                for milestone in (b'Utkarsha Kernel Booting...',b'Boot memory self-test: PASS',
                                  b'Utkarsha Kernel Ready. Entering main execution.',
                                  b'[ush] kernel console starting',b'Utkarsha Shell 0.1.0-dev'):
                    assert milestone in transcript, milestone

                if native_time:
                    match=re.search(rb'\[apps/time\] native clock/calendar: PASS utc=0x([0-9A-Fa-f]+) local=([0-9]+)/([0-9]+)/([0-9]+) ([0-9]+):([0-9]+)',transcript)
                    assert match,bytes(transcript[-4000:])
                    import datetime
                    base=int(datetime.datetime(2026,10,24,tzinfo=datetime.timezone.utc).timestamp())
                    assert base<=int(match[1],16)<=base+120,match[0]
                    assert tuple(map(int,match.groups()[1:]))==(2026,10,24,5,45),match[0]
                # An idle shell must yield: prove another heartbeat arrives.
                start=len(transcript)
                receive_until(b'heartbeat #',start,12)
                def command(line,result=None,prompt=b'ush> ',submitted=None):
                    start=len(transcript)
                    serial.sendall(line.encode()+b'\x05\r') # end-of-line before Enter
                    echoed=(line if submitted is None else submitted)[-63:]
                    entered=receive_until(echoed.encode()+b'\r\n',start)
                    if result is not None:
                        receive_until(result.encode()+b'\r\n',entered)
                    receive_until(prompt,entered)
                    actual=bytes(transcript[start:]).replace(b'\r',b'')
                    if result is not None:
                        assert ('\n'+result+'\n').encode() in actual,(line,actual)
                if power_action:
                    command('write /power-note POWER_SURVIVES')
                    qmp_buffer.clear()
                    while select.select([qmp],[],[],0)[0]:
                        assert qmp.recv(65536)
                    start=len(transcript)
                    serial.sendall(power_action.encode()+b'\r')
                    event_name='RESET' if power_action=='reboot' else 'SHUTDOWN'
                    event=qmp_until(lambda m:m.get('event')==event_name)
                    assert event['data']['guest'] is True,event
                    expected_reason='guest-reset' if power_action=='reboot' else 'guest-shutdown'
                    assert event['data']['reason']==expected_reason,event
                    (LOGS/f'qemu-{label}.qmp.json').write_text(json.dumps(event,indent=2))
                    if power_action=='reboot':
                        booted=receive_until(b'Utkarsha Kernel Booting...',start,100)
                        receive_until(b'ush> ',booted,100)
                        command('cat /power-note; echo','POWER_SURVIVES')
                        assert b'Rebooting Utkarsha OS...' in transcript[start:]
                    else:
                        assert proc.wait(timeout=15)==0
                        while select.select([serial],[],[],.1)[0]:
                            chunk=serial.recv(65536)
                            if not chunk:
                                break
                            transcript.extend(chunk)
                        assert b'Shutting down Utkarsha OS...' in transcript[start:]
                    text=bytes(transcript)
                    for fatal in (b'PANIC',b'ERROR:',b'TRIPLE FAULT',b'Page Fault',b'[EXCEPTION]'):
                        assert fatal not in text,fatal
                    if boot_digest is not None:
                        assert hashlib.sha256((BOOT/'utkarsha.img').read_bytes()).digest()==boot_digest
                    print(f'Ush QEMU {label}: PASS (guest {event_name}, storage flush/persistence)')
                    return
                if editor_phase:
                    editor_ready=b'Ctrl-S Save | Ctrl-Q Quit | Ready'
                    editor_saved=b'Ctrl-S Save | Ctrl-Q Quit | Saved'
                    def close_editor(keys=b'\x11'):
                        start=len(transcript)
                        serial.sendall(keys)
                        closed=receive_until(b'Uedit closed.\r\n',start)
                        receive_until(b'ush> ',closed)
                    if editor_phase=='create':
                        command('uedit /edited',prompt=editor_ready)
                        start=len(transcript)
                        serial.sendall(b'first\rsecond\tline\x13')
                        receive_until(editor_saved,start)
                        start=len(transcript)
                        serial.sendall(b'\x1b[D\x1b[D')
                        receive_until(b'\x1b[3;11H\x1b[?25h',start)
                        start=len(transcript)
                        beat=receive_until(b'heartbeat #',start,12)
                        restored=receive_until(editor_saved,beat)
                        receive_until(b'\x1b[3;11H\x1b[?25h',restored)
                        assert b'second  line' in transcript[beat:]
                        start=len(transcript)
                        serial.sendall(b'X')
                        receive_until(b'second  liXne',start)
                        receive_until(editor_ready,start)
                        start=len(transcript)
                        serial.sendall(b'\x13')
                        receive_until(editor_saved,start)
                        close_editor()
                        command('wc /edited','1 3 18')
                        command('uedit /edited',prompt=editor_ready)
                        start=len(transcript)
                        serial.sendall(b'Z\x11')
                        receive_until(b'Unsaved changes! Ctrl-Q again discards',start)
                        start=len(transcript)
                        serial.sendall(b'\x03')
                        receive_until(b'Quit cancelled',start)
                        start=len(transcript)
                        serial.sendall(b'\x11')
                        receive_until(b'Unsaved changes! Ctrl-Q again discards',start)
                        close_editor()
                        command('wc /edited','1 3 18')
                        command('uedit /not-created',prompt=editor_ready)
                        start=len(transcript)
                        serial.sendall(b'\x11')
                        receive_until(b'Unsaved changes! Ctrl-Q again discards',start)
                        close_editor()
                    else:
                        command('wc /edited','1 3 18')
                        command('head -n 1 /edited','first')
                        command('tail -n 1 /edited; echo','second\tliXne')
                        start=len(transcript)
                        command('uedit /edited',prompt=editor_ready)
                        assert b'Uedit /edited  Ln ' in transcript[start:]
                        assert b'second  liXne' in transcript[start:]
                        start=len(transcript)
                        serial.sendall(b'\x1b[F!\x13')
                        receive_until(editor_saved,start)
                        close_editor()
                        command('head -n 1 /edited','first!')
                        command('wc /edited','1 3 19')

                    if editor_phase=='create':
                        command('uedit /advanced',prompt=editor_ready)
                        start=len(transcript)
                        serial.sendall('caf\u00e9 \u4e16\u754c'.encode()+b'\x1a\x19\x13')
                        receive_until(editor_saved,start)
                        start=len(transcript)
                        serial.sendall(b'\x06'+'\u4e16\u754c'.encode()+b'\r\x12world\r\x01')
                        receive_until(b'Replaced',start)
                        start=len(transcript)
                        serial.sendall(b'\x06world\r\x02\x1b[C\x1b[C\x03\x1b[F\x16\x13')
                        receive_until(editor_saved,start)
                        # VT reports exercise UART geometry, not a host-only ioctl.
                        start=len(transcript)
                        serial.sendall(b'\x1b[8;10;40t')
                        receive_until(b'\x1b[10;1H',start)
                        start=len(transcript)
                        serial.sendall(b'\x1b[8;24;80t')
                        receive_until(b'\x1b[24;1H',start)
                        close_editor()
                        command('cat /advanced; echo','caf\u00e9 worldwo')
                        command('uedit /crlf',prompt=editor_ready)
                        start=len(transcript)
                        serial.sendall(b'\x1b[F!\rnext\x13')
                        receive_until(editor_saved,start)
                        close_editor()
                    else:
                        command('cat /advanced; echo','caf\u00e9 worldwo')
                        command('uedit /advanced',prompt=editor_ready)
                        start=len(transcript)
                        serial.sendall(b'\x06world\r\x12'+ '\u4e16\u754c'.encode()+b'\r\x12\x13')
                        receive_until(editor_saved,start)
                        close_editor()
                        command('cat /advanced; echo','caf\u00e9 \u4e16\u754cwo')
                        command('wc /crlf','2 2 13')
                    command('stat /not-created')
                    command('echo $?','1')
                    command('echo UEDIT_RETURNED','UEDIT_RETURNED')
                if storage_phase=='create':
                    command('pwd','/')
                    command('mkdir /persist')
                    command('cd /persist')
                    command('write note UXFS_PERSISTED')
                    command('cp note duplicate')
                    command('mv duplicate moved')
                    command('touch empty')
                    command('mkdir nested')
                    command('write nested/inside UXFS_CHILD')
                    command('mv /persist /saved')
                    command('pwd','/saved')
                    command('cat moved; echo','UXFS_PERSISTED')
                    command('append note _APPENDED')
                    command('cat note; echo','UXFS_PERSISTED_APPENDED')
                    command('head -n 1 note; echo','UXFS_PERSISTED_APPENDED')
                    command('tail -n 1 note; echo','UXFS_PERSISTED_APPENDED')
                    command('grep APPENDED note; echo','UXFS_PERSISTED_APPENDED')
                    command('wc note','0 1 23')
                    command('du note','23 bytes')
                    command('stat note','type: file')
                    command('find /saved moved','/saved/moved')
                    command('hexdump note')
                    command('df')
                    command('rm empty; mkdir empty; rmdir empty')
                    command('touch deleted; rm deleted')
                elif storage_phase=='verify':
                    command('ls /saved','note')
                    command('cat /saved/empty')
                    command('echo $?','1')
                    command('cat /saved/deleted')
                    command('echo $?','1')
                    command('cat /saved/note; echo','UXFS_PERSISTED_APPENDED')
                    command('cat /saved/moved; echo','UXFS_PERSISTED')
                    command('cat /saved/nested/inside; echo','UXFS_CHILD')
                    command('touch /saved/note')
                    command('cat /saved/note; echo','UXFS_PERSISTED_APPENDED')
                    command('cp /saved/note /saved/moved')
                    command('echo $?','1')
                    command('cat /saved/moved; echo','UXFS_PERSISTED')
                    command('touch /missing/file')
                    command('echo $?','1')
                command('echo USH_QEMU_OK','USH_QEMU_OK')
                start=len(transcript)
                command('uptime')
                assert re.search(rb'\r\n[0-9]+ seconds\r\n',transcript[start:])
                start=len(transcript)
                serial.sendall(b'sleep 2\r')
                entered=receive_until(b'sleep 2\r\n',start)
                end=receive_until(b'ush> ',entered,15)
                assert b'heartbeat #' in transcript[entered:end], 'sleep blocked scheduler'
                start=len(transcript)
                command('clear')
                assert b'\x1b[2J\x1b[H' in transcript[start:]
                command('export VALUE=kernel-owned')
                command('echo "$VALUE"','kernel-owned')
                command('false')
                command('echo $?','1')
                command('false && echo BAD || echo CHAIN','CHAIN')
                command('export X=linked; echo $X','linked')
                command('true || false && echo LEFT','LEFT')
                command("echo SHOULD_NOT_RUN; echo '")
                command('echo $?','2')
                command('echo abxc\x1b[D\x1b[D\x1b[3~','abc',submitted='echo abc')
                command('echo HISTORY','HISTORY')
                command('\x1b[A','HISTORY',submitted='echo HISTORY')
                # Wait for a heartbeat with the cursor in the middle of text.
                start=len(transcript)
                serial.sendall(b'echo ac\x1b[D')
                receive_until(b'\x1b[1D',start)
                start=len(transcript)
                beat=receive_until(b'heartbeat #',start,12)
                receive_until(b'\r\x1b[2Kush> echo ac\x1b[1D',beat)
                start=len(transcript)
                serial.sendall(b'b\x05\r')
                entered=receive_until(b'echo abc\r\n',start)
                receive_until(b'abc\r\n',entered)
                receive_until(b'ush> ',entered)
                start=len(transcript)
                serial.sendall(b'echo CANCELLED\x03')
                cancelled=receive_until(b'^C\r\n',start)
                receive_until(b'ush> ',cancelled)
                command('echo $?','130')
                command("calc 'sqrt(81)+2**3'",'17')
                command("calc -x '0xff << 4'",'ff0')
                command('calc',prompt=b'calc> ')
                command('sci',prompt=b'calc> ')
                command('2**3**2','512',prompt=b'calc> ')
                command('1/0',prompt=b'calc> ')
                command('2+3','5',prompt=b'calc> ')
                command('quit','Bye.')
                command('echo USH_RECOVERED','USH_RECOVERED')
                start=len(transcript)
                serial.sendall(b'exit 0\r')
                receive_until(b'[ush] exited; kernel scheduler continues',start)
                start=len(transcript)
                receive_until(b'heartbeat #',start,12)
                text=bytes(transcript).decode(errors='replace')
                for fatal in ('PANIC','ERROR:','TRIPLE FAULT','Page Fault','[EXCEPTION]'):
                    assert fatal not in text, fatal
                assert not re.search(r'\bFAIL(?:ED)?\b',text),text[-2000:]
                if boot_digest is not None:
                    assert hashlib.sha256((BOOT/'utkarsha.img').read_bytes()).digest()==boot_digest, 'primary boot image changed'
                print(f'Ush QEMU {label}: PASS (kernel boot, editing/history, Ctrl-C, background redraw, chaining, calculator, yield/exit)')
        finally:
            log.write_bytes(transcript)
            if qmp is not None:
                qmp.close()
            if serial is not None:
                serial.close()
            if proc is not None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--firmware',choices=['bios','ovmf'],default='bios')
    parser.add_argument('--smp',type=int,default=1)
    parser.add_argument('--strict-nx',action='store_true')
    parser.add_argument('--storage-test',action='store_true',help='create files, reboot, verify persistence on isolated UXFS image')
    parser.add_argument('--power-test',action='store_true',help='prove guest reboot and shutdown with QMP and a persistent data image')
    parser.add_argument('--native-time-test',action='store_true',help='fixed RTC: real lib/time + lib/cal app wiring')
    parser.add_argument('--uedit-test',action='store_true',help='edit/save/discard and restore after logs, then verify saved text on a second boot')
    options=parser.parse_args()
    if options.strict_nx and options.firmware!='ovmf':
        parser.error('--strict-nx requires --firmware ovmf')
    if sum((options.storage_test,options.power_test,options.uedit_test,options.native_time_test))>1:
        parser.error('choose one of --storage-test, --power-test, --uedit-test and --native-time-test')
    if options.native_time_test:
        test(options.firmware,options.smp,options.strict_nx,native_time=True)
    elif options.uedit_test:
        with tempfile.TemporaryDirectory(prefix='utkarsha-uedit-') as directory:
            disk=Path(directory)/'data.uxfs'
            subprocess.run(['python3',str(ROOT/'storage/uxfs/mkvolume.py'),str(disk)],check=True)
            subprocess.run([str(ROOT/'apps/ush/build/ush'),'--disk',str(disk),'-c',"write /crlf 'line\r\n'"],check=True)
            for phase in ('create','verify'):
                test(options.firmware,options.smp,options.strict_nx,disk,editor_phase=phase)
                raw=subprocess.check_output([str(ROOT/'apps/ush/build/ush'),'--disk',str(disk),'-c','cat /crlf'])
                assert raw==b'line!\r\nnext\r\n',raw
        print('Uedit QEMU editing, save/discard, diagnostic redraw and reboot persistence: PASS')
    elif options.power_test:
        with tempfile.TemporaryDirectory(prefix='utkarsha-power-') as directory:
            disk=Path(directory)/'data.uxfs'
            subprocess.run(['python3',str(ROOT/'storage/uxfs/mkvolume.py'),str(disk)],check=True)
            for action in ('reboot','shutdown'):
                test(options.firmware,options.smp,options.strict_nx,disk,power_action=action)
                content=subprocess.check_output([str(ROOT/'apps/ush/build/ush'),'--disk',str(disk),'-c','cat /power-note'])
                assert content==b'POWER_SURVIVES'
        print('Ush actual guest reboot/shutdown and persistent data: PASS')
    elif options.storage_test:
        with tempfile.TemporaryDirectory(prefix='utkarsha-uxfs-') as directory:
            disk=Path(directory)/'data.uxfs'
            subprocess.run(['python3',str(ROOT/'storage/uxfs/mkvolume.py'),str(disk)],check=True)
            for phase in ('create','verify'):
                test(options.firmware,options.smp,options.strict_nx,disk,phase)
        print('UXFS QEMU persistence across two independent boots: PASS')
    else:
        test(options.firmware,options.smp,options.strict_nx)
