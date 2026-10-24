"""Validate bundle relocation and reject corrupt ownership/layout metadata."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import struct
import tempfile

ROOT=Path(__file__).resolve().parents[4]
spec=importlib.util.spec_from_file_location('bundle',ROOT/'apps/ush/scripts/kernel_bundle.py')
bundle=importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
prepared=bundle.OUT
with tempfile.TemporaryDirectory(prefix='ush-bundle-test-') as directory:
    work=Path(directory)
    for name in ('manifest.json','input.o'):
        shutil.copy2(prepared/name,work/name)
    bundle.OUT=work
    sizes=json.loads((work/'manifest.json').read_text())['sizes']
    page=lambda value:(value+4095)&~4095
    text=0x101000
    rx_end=page(text+sizes['text'])
    rodata=rx_end+4096
    marker=page(rodata+sizes['rodata'])-0x100000
    data=0x100000+marker+4096
    bss=page(data+sizes['data'])+4096
    addresses=[text,rodata,data,bss]
    memory_extent=page(bss-0x100000+sizes['bss'])
    raw=bytearray(bss-0x100000)
    struct.pack_into('<IIQQIIQ',raw,0,0x464c55,len(raw),0x100028,0,rx_end-0x100000,2,memory_extent)
    raw[marker:marker+len(bundle.MAGIC)]=bundle.MAGIC
    struct.pack_into('<8Q',raw,marker+len(bundle.MAGIC),*addresses,*[sizes[x] for x in bundle.SECTIONS])
    path=work/'kernel.bin'
    path.write_bytes(raw)
    with contextlib.redirect_stdout(io.StringIO()):
        bundle.patch(path)
    result=path.read_bytes()
    assert result[:40]==raw[:40] and len(result)==len(raw)
    assert result[0x1000:0x1000+sizes['text']]!=bytes(sizes['text'])
    assert result[marker:marker+len(bundle.MAGIC)+64]==raw[marker:marker+len(bundle.MAGIC)+64]
    path.write_bytes(raw[:-3])
    with contextlib.redirect_stdout(io.StringIO()):
        bundle.patch(path)
    assert len(path.read_bytes())==len(raw) and path.read_bytes()[-3:]==bytes(3)
    def rejects(mutated):
        path.write_bytes(mutated)
        try:
            bundle.patch(path)
        except ValueError:
            return
        raise AssertionError('invalid kernel layout accepted')
    bad=raw.copy()
    bad[marker]=0
    rejects(bad)
    bad=raw.copy()
    bad[-4096:-4096+len(bundle.MAGIC)]=bundle.MAGIC
    rejects(bad)
    bad=raw.copy()
    struct.pack_into('<Q',bad,marker+len(bundle.MAGIC),rodata) # instructions outside RX prefix
    rejects(bad)
    bad=raw.copy()
    struct.pack_into('<Q',bad,marker+len(bundle.MAGIC)+8,0x102000) # rodata in RX prefix
    rejects(bad)
    bad=raw.copy()
    struct.pack_into('<Q',bad,marker+len(bundle.MAGIC)+24,0x100000+memory_extent) # BSS outside ownership
    rejects(bad)
print('Ush static bundle: PASS (ELF relocation, RX/data/BSS bounds, corrupt metadata rejection)')
