"""End-to-end protocol-v2 request, history, and PACK bridge validation."""
import ctypes
import hashlib
import struct
import sys
import zlib

lib = ctypes.CDLL(sys.argv[1])
P = ctypes.POINTER(ctypes.c_ubyte)
lib.smart_serve_probe.argtypes = [ctypes.c_uint64, P, ctypes.c_uint64, P, ctypes.c_uint64, ctypes.c_uint64]
lib.smart_serve_probe.restype = ctypes.c_uint64
length = ctypes.c_uint64.in_dll(lib, 'smart_length'); terminal = ctypes.c_uint64.in_dll(lib, 'smart_terminal')
count = ctypes.c_uint64.in_dll(lib, 'mock_smart_count')
manifests = (ctypes.c_ubyte * (8 * 4096)).in_dll(lib, 'mock_smart_manifests')
nodes = (ctypes.c_ubyte * (8 * 4352)).in_dll(lib, 'mock_smart_nodes')
def put64(buf, offset, number): ctypes.c_uint64.from_buffer(buf, offset).value = number
def oid(kind, body): return hashlib.sha256(kind + b' ' + str(len(body)).encode() + b'\0' + body).digest()
def commit(tree, parent, message):
    body = b'tree ' + tree.hex().encode() + b'\n'
    if parent: body += b'parent ' + parent.hex().encode() + b'\n'
    body += (b'author Tattva VCS <vcs@tattva.local> 0 +0000\n'
             b'committer Tattva VCS <vcs@tattva.local> 0 +0000\n\n' + message)
    return body, oid(b'commit', body)
def pkt(payload): return f'{len(payload)+4:04x}'.encode() + payload
def request(command, arguments):
    return (pkt(b'command=' + command + b'\n') + pkt(b'object-format=sha256\n') + b'0001'
            + b''.join(pkt(arg) for arg in arguments) + b'0000')
def packets(raw):
    result=[]; pos=0
    while pos < len(raw):
        prefix=raw[pos:pos+4]
        if prefix in (b'0000', b'0001'): result.append(prefix); pos += 4; continue
        size=int(prefix,16); result.append(raw[pos+4:pos+size]); pos += size
    return result
def pack_objects(raw):
    assert raw[:4] == b'PACK' and struct.unpack('>I',raw[4:8])[0] == 2
    count=struct.unpack('>I',raw[8:12])[0]; pos=12; objects=[]
    for _ in range(count):
        byte=raw[pos]; pos+=1; kind=(byte>>4)&7; size=byte&15; shift=4
        while byte&128: byte=raw[pos]; pos+=1; size|=(byte&127)<<shift; shift+=7
        stream=zlib.decompressobj(); body=stream.decompress(raw[pos:-32]); assert stream.eof and len(body)==size
        pos += len(raw[pos:-32])-len(stream.unused_data); objects.append((kind,body))
    assert pos == len(raw)-32 and raw[-32:] == hashlib.sha256(raw[:-32]).digest()
    return objects

ctypes.memset(manifests,0,len(manifests)); ctypes.memset(nodes,0,len(nodes)); count.value=2
blobs=(b'one',b'two'); messages=(b'root\n',b'tip\n')
for i in range(2):
    base=i*4096; put64(manifests,base+16,i); put64(manifests,base+24,1); put64(manifests,base+32,len(messages[i]))
    manifests[base+40:base+40+len(messages[i])]=messages[i]; manifests[base+256:base+262]=b'a.txt\0'
    put64(manifests,base+496,i+1); put64(manifests,base+504,3)
    node=i*4352; put64(nodes,node+240,1); put64(nodes,node+248,3); nodes[node+256:node+259]=blobs[i]
blob_ids=[oid(b'blob',body) for body in blobs]; trees=[b'100644 a.txt\0'+value for value in blob_ids]
tree_ids=[oid(b'tree',body) for body in trees]; root_body,root_id=commit(tree_ids[0],None,messages[0]); tip_body,tip_id=commit(tree_ids[1],root_id,messages[1])

response=(ctypes.c_ubyte*65519)()
assert lib.smart_serve_probe(0,None,0,response,len(response),0)==0
records=packets(bytes(response[:length.value])); assert records[0]==b'version 2\n' and records[-1]==b'0000' and terminal.value==0

raw=request(b'ls-refs',(b'symrefs\n',)); data=(ctypes.c_ubyte*len(raw)).from_buffer_copy(raw)
assert lib.smart_serve_probe(1,data,len(data),response,len(response),2)==0
records=packets(bytes(response[:length.value])); tip_hex=tip_id.hex().encode()
assert tip_hex+b' HEAD symref-target:refs/heads/main\n' in records and tip_hex+b' refs/heads/main\n' in records and terminal.value==0

raw=request(b'fetch',(b'want '+tip_hex+b'\n',b'done\n')); data=(ctypes.c_ubyte*len(raw)).from_buffer_copy(raw)
assert lib.smart_serve_probe(1,data,len(data),response,len(response),2)==0 and terminal.value==1
records=packets(bytes(response[:length.value])); assert records[0]==b'packfile\n' and records[-1]==b'0000'
pack=b''.join(record[1:] for record in records[1:-1] if record and record[:1]==b'\x01')
assert pack_objects(pack)==[(3,blobs[0]),(2,trees[0]),(1,root_body),(3,blobs[1]),(2,trees[1]),(1,tip_body)]

bad=request(b'fetch',(b'want '+bytes(32).hex().encode()+b'\n',b'done\n')); data=(ctypes.c_ubyte*len(bad)).from_buffer_copy(bad)
assert lib.smart_serve_probe(1,data,len(data),response,len(response),2)==2

print('VCS smart bridge: PASS (real request parser, refs, history OIDs, PACK response, mismatch)')
