"""Cooperative authenticated server state-machine coverage."""
import ctypes
import struct
import sys
lib=ctypes.CDLL(sys.argv[1])
ptr=ctypes.POINTER(ctypes.c_ubyte)
for name in ('server_begin_probe','vcs_sync_server_step','vcs_sync_server_rearm','vcs_sync_server_close'):
    getattr(lib,name).restype=ctypes.c_uint64
lib.server_begin_probe.argtypes=[ptr,ctypes.c_uint32,ctypes.c_uint32]
lib.vcs_sync_server_step.argtypes=[ptr]
lib.vcs_sync_server_rearm.argtypes=[ptr]
lib.vcs_sync_server_close.argtypes=[ptr]
names=('mock_listener_fd','mock_accept_fd','mock_poll','mock_receive_begin','mock_send_begin',
       'mock_step','mock_frame_op','mock_decode_status','mock_decode_op','mock_decode_count',
       'mock_handler_status','mock_handler_count','mock_response_encode','mock_close_count')
c={name:ctypes.c_uint64.in_dll(lib,name) for name in names}
ACCEPT,RECEIVE,SEND,READY,FAILED=range(5)
AGAIN,IO,CORRUPT,USAGE=1,4,5,8
def reset():
    for value in c.values(): value.value=0
    c['mock_listener_fd'].value=10
    c['mock_accept_fd'].value=ctypes.c_uint64(-1).value
    c['mock_frame_op'].value=1
    c['mock_decode_op'].value=1
def phase(s): return struct.unpack_from('<I',s,0)[0]
def begin(s): return lib.server_begin_probe(s,0,9418)
reset(); s=(ctypes.c_ubyte*760)()
assert begin(s)==0 and phase(s)==ACCEPT
assert struct.unpack_from('<ii',s,8)==(10,-1)
assert lib.vcs_sync_server_step(s)==AGAIN
c['mock_accept_fd'].value=7
assert lib.vcs_sync_server_step(s)==AGAIN and phase(s)==RECEIVE
c['mock_step'].value=AGAIN
assert lib.vcs_sync_server_step(s)==AGAIN and phase(s)==RECEIVE
c['mock_step'].value=0; c['mock_decode_count'].value=2; c['mock_handler_count'].value=3
assert lib.vcs_sync_server_step(s)==AGAIN and phase(s)==SEND
assert struct.unpack_from('<QQQ',s,32)==(2,3,0)
assert lib.vcs_sync_server_step(s)==0 and phase(s)==READY
assert lib.vcs_sync_server_rearm(s)==0 and phase(s)==ACCEPT
assert struct.unpack_from('<i',s,12)[0]==-1 and c['mock_close_count'].value==1
c['mock_accept_fd'].value=8
assert lib.vcs_sync_server_step(s)==AGAIN
c['mock_handler_status'].value=6
assert lib.vcs_sync_server_step(s)==AGAIN and phase(s)==SEND
assert struct.unpack_from('<QQ',s,40)==(0,6)
assert lib.vcs_sync_server_step(s)==6 and phase(s)==READY
assert lib.vcs_sync_server_close(s)==0 and c['mock_close_count'].value==3

reset(); s=(ctypes.c_ubyte*760)(); assert begin(s)==0
c['mock_accept_fd'].value=7; assert lib.vcs_sync_server_step(s)==AGAIN
c['mock_decode_op'].value=2
assert lib.vcs_sync_server_step(s)==CORRUPT and phase(s)==FAILED
reset(); s=(ctypes.c_ubyte*760)(); assert begin(s)==0
c['mock_accept_fd'].value=7; assert lib.vcs_sync_server_step(s)==AGAIN
c['mock_handler_status'].value=10
assert lib.vcs_sync_server_step(s)==CORRUPT and phase(s)==FAILED
reset(); s=(ctypes.c_ubyte*760)(); struct.pack_into('<I',s,0,READY)
c['mock_listener_fd'].value=ctypes.c_uint64(-1).value
assert begin(s)==IO and phase(s)==FAILED
assert struct.unpack_from('<ii',s,8)==(-1,-1)
assert lib.vcs_sync_server_step(None)==USAGE
assert lib.vcs_sync_server_rearm(None)==USAGE
assert lib.vcs_sync_server_close(None)==USAGE
print('VCS server: PASS (accept, receive, policy, response, rearm, close, failures)')
