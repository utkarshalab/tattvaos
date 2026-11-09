"""Native upload-server transport through the real smart Git bridge."""
import ctypes
import hashlib
import sys

lib=ctypes.CDLL(sys.argv[1]); P=ctypes.POINTER(ctypes.c_ubyte)
for name in ('git_upload_server_begin','git_upload_server_step','git_upload_server_rearm','git_upload_server_has_client'):
    getattr(lib,name).restype=ctypes.c_uint64
lib.git_upload_server_begin.argtypes=[ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint64]
def q(name): return ctypes.c_uint64.in_dll(lib,name)
net_input,net_length,net_offset,out_length,net_chunk,net_close=[q(name) for name in (
    'mock_net_input','mock_net_length','mock_net_offset','mock_net_output_length','mock_net_chunk','mock_net_close')]
net_output=(ctypes.c_ubyte*131072).in_dll(lib,'mock_net_output')
count=q('mock_smart_count'); manifests=(ctypes.c_ubyte*(8*4096)).in_dll(lib,'mock_smart_manifests'); nodes=(ctypes.c_ubyte*(8*4352)).in_dll(lib,'mock_smart_nodes')
def put64(buf,off,n): ctypes.c_uint64.from_buffer(buf,off).value=n
def oid(kind,body): return hashlib.sha256(kind+b' '+str(len(body)).encode()+b'\0'+body).digest()
def commit(tree,parent,msg):
    body=b'tree '+tree.hex().encode()+b'\n'+(b'' if parent is None else b'parent '+parent.hex().encode()+b'\n')
    body+=(b'author Tattva VCS <vcs@tattva.local> 0 +0000\ncommitter Tattva VCS <vcs@tattva.local> 0 +0000\n\n'+msg)
    return oid(b'commit',body)
def pkt(payload): return f'{len(payload)+4:04x}'.encode()+payload
def request(cmd,args): return pkt(b'command='+cmd+b'\n')+pkt(b'object-format=sha256\n')+b'0001'+b''.join(pkt(x) for x in args)+b'0000'
def feed(raw,chunk=0):
    data=(ctypes.c_ubyte*len(raw)).from_buffer_copy(raw); keep.append(data)
    net_input.value=ctypes.addressof(data); net_length.value=len(raw); net_offset.value=0; net_chunk.value=chunk
def take():
    raw=bytes(net_output[:out_length.value]); out_length.value=0; return raw
def packets(raw):
    result=[]; p=0
    while p<len(raw):
        prefix=raw[p:p+4]
        if prefix in (b'0000',b'0001'): result.append(prefix); p+=4; continue
        size=int(prefix,16); result.append(raw[p+4:p+size]); p+=size
    return result
def send_cycle():
    while True:
        before=out_length.value; result=lib.git_upload_server_step()
        if result != 1 or out_length.value == before: return result

ctypes.memset(manifests,0,len(manifests)); ctypes.memset(nodes,0,len(nodes)); count.value=2
blobs=(b'one',b'two'); messages=(b'root\n',b'tip\n')
for i in range(2):
    b=i*4096; put64(manifests,b+16,i); put64(manifests,b+24,1); put64(manifests,b+32,len(messages[i])); manifests[b+40:b+40+len(messages[i])]=messages[i]
    manifests[b+256:b+262]=b'a.txt\0'; put64(manifests,b+496,i+1); put64(manifests,b+504,3)
    n=i*4352; put64(nodes,n+240,1); put64(nodes,n+248,3); nodes[n+256:n+259]=blobs[i]
blob_ids=[oid(b'blob',x) for x in blobs]; tree_ids=[oid(b'tree',b'100644 a.txt\0'+x) for x in blob_ids]
root=commit(tree_ids[0],None,messages[0]); tip=commit(tree_ids[1],root,messages[1]); tiphex=tip.hex().encode()

keep=[]; out_length.value=net_close.value=0
assert lib.git_upload_server_begin(0,9418,2)==0
assert lib.git_upload_server_step()==1 and lib.git_upload_server_has_client()==1
service=pkt(b'git-upload-pack /\0\0version=2\0'); feed(service,7)
while net_offset.value<net_length.value: assert lib.git_upload_server_step()==1
assert lib.git_upload_server_step()==1
net_chunk.value=31
while True:
    r=lib.git_upload_server_step()
    if r==1 and out_length.value and bytes(net_output[max(0,out_length.value-4):out_length.value])==b'0000':
        if lib.git_upload_server_step()==1: break
advert=take(); assert packets(advert)[0]==b'version 2\n'

ls=request(b'ls-refs',(b'symrefs\n',)); feed(ls,11)
while net_offset.value<net_length.value: assert lib.git_upload_server_step()==1
assert lib.git_upload_server_step()==1
net_chunk.value=29
while True:
    assert lib.git_upload_server_step()==1
    if out_length.value and bytes(net_output[max(0,out_length.value-4):out_length.value])==b'0000':
        assert lib.git_upload_server_step()==1; break
refs=packets(take()); assert tiphex+b' HEAD symref-target:refs/heads/main\n' in refs

fetch=request(b'fetch',(b'want '+tiphex+b'\n',b'done\n')); feed(fetch,13)
while net_offset.value<net_length.value: assert lib.git_upload_server_step()==1
assert lib.git_upload_server_step()==1
net_chunk.value=97
while lib.git_upload_server_step()==1: pass
records=packets(take()); assert records[0]==b'packfile\n' and records[-1]==b'0000'
pack=b''.join(x[1:] for x in records[1:-1] if x[:1]==b'\x01'); assert pack[:4]==b'PACK' and pack[-32:]==hashlib.sha256(pack[:-32]).digest()
assert lib.git_upload_server_rearm()==0 and net_close.value==1

print('VCS smart server: PASS (daemon handshake, partial I/O, advertise, refs, fetch PACK, rearm)')
