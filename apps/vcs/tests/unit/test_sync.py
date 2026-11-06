"""Signed frame engine partial-I/O, authentication, and lifecycle coverage."""
import ctypes,struct,sys
lib=ctypes.CDLL(sys.argv[1]); P=ctypes.POINTER(ctypes.c_ubyte)
lib.sync_send_probe.argtypes=[P,ctypes.c_uint32,P,ctypes.c_uint64,ctypes.c_uint64,ctypes.c_uint64]
lib.sync_receive_probe.argtypes=[P,P,ctypes.c_uint64]
lib.vcs_sync_step.argtypes=[P]; lib.vcs_sync_result.argtypes=[P]
for n in ('sync_send_probe','sync_receive_probe','vcs_sync_step','vcs_sync_result'): getattr(lib,n).restype=ctypes.c_uint64
io=ctypes.c_uint64.in_dll(lib,'mock_io_result'); trust=ctypes.c_uint64.in_dll(lib,'mock_trust_result'); verify=ctypes.c_uint64.in_dll(lib,'mock_verify_result')
AGAIN,IOERR,CORRUPT,PERM,USAGE=1,4,5,7,8; MAGIC=0x31454c444e425655
state=(ctypes.c_ubyte*512)(); payload=(ctypes.c_ubyte*4)(1,2,3,4)
assert lib.sync_send_probe(state,1,payload,4,2,9)==0
io.value=80; assert lib.vcs_sync_step(state)==AGAIN
io.value=88; assert lib.vcs_sync_step(state)==AGAIN
io.value=4; assert lib.vcs_sync_step(state)==0
assert lib.vcs_sync_result(state)==0
assert lib.sync_send_probe(state,0,payload,4,0,0)==USAGE
assert lib.vcs_sync_step(state)==IOERR

def receiver(digest=bytes([0xab])*32,trust_status=0,verify_status=0):
    s=(ctypes.c_ubyte*512)(); store=(ctypes.c_ubyte*4)(1,2,3,4)
    assert lib.sync_receive_probe(s,store,4)==0
    header=bytearray(168); struct.pack_into('<QIIQQQ',header,0,MAGIC,1,1,4,2,9)
    header[40:72]=digest; header[72:104]=bytes([0x11])*32; header[104:168]=bytes([0x22])*64
    s[80:248]=header
    trust.value=trust_status; verify.value=verify_status
    io.value=168; assert lib.vcs_sync_step(s)==AGAIN
    io.value=4
    return s,store
s,store=receiver(); assert lib.vcs_sync_step(s)==0 and lib.vcs_sync_result(s)==0
assert lib.sync_receive_probe(s,store,0)==USAGE and lib.vcs_sync_step(s)==IOERR
s,_=receiver(bytes(32)); assert lib.vcs_sync_step(s)==CORRUPT
s,_=receiver(trust_status=1); assert lib.vcs_sync_step(s)==PERM
s,_=receiver(verify_status=1); assert lib.vcs_sync_step(s)==PERM
assert lib.vcs_sync_step(None)==USAGE
print('VCS sync: PASS (partial I/O, frame bounds, digest, trust, signature, lifecycle)')
