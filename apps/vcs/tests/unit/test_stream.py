"""One-shot signed bundle stream lifecycle coverage."""
import ctypes
import sys
lib=ctypes.CDLL(sys.argv[1])
ptr=ctypes.POINTER(ctypes.c_ubyte)
lib.vcs_stream_send_begin.argtypes=[ctypes.c_uint32,ctypes.c_uint64,ctypes.c_uint32,ptr]
lib.vcs_stream_receive_begin.argtypes=[ctypes.c_uint32,ctypes.c_uint32,ptr]
for name in ('vcs_stream_send_begin','vcs_stream_receive_begin','vcs_stream_step'):
    getattr(lib,name).restype=ctypes.c_uint64
names=('mock_export_status','mock_send_begin','mock_receive_begin','mock_step','mock_result',
       'mock_result_operation','mock_publish_status','mock_publish_id','mock_export_calls',
       'mock_send_calls','mock_receive_calls','mock_publish_calls')
c={name:ctypes.c_uint64.in_dll(lib,name) for name in names}
AGAIN,CORRUPT,USAGE=1,5,8
seed=(ctypes.c_ubyte*32)(*range(32))
def reset():
    for value in c.values(): value.value=0
    c['mock_result_operation'].value=1
    c['mock_publish_id'].value=42
reset()
assert lib.vcs_stream_send_begin(7,9,1,seed)==0
assert c['mock_export_calls'].value==1 and c['mock_send_calls'].value==1
c['mock_step'].value=AGAIN
assert lib.vcs_stream_step()==AGAIN
c['mock_step'].value=0
assert lib.vcs_stream_step()==0 and c['mock_publish_calls'].value==0
assert lib.vcs_stream_step()==CORRUPT

reset()
assert lib.vcs_stream_receive_begin(7,1,seed)==0
c['mock_step'].value=AGAIN
assert lib.vcs_stream_step()==AGAIN
c['mock_step'].value=0
assert lib.vcs_stream_step()==0
assert c['mock_publish_calls'].value==1
assert lib.vcs_stream_step()==CORRUPT
assert c['mock_publish_calls'].value==1

reset(); c['mock_result_operation'].value=2
assert lib.vcs_stream_receive_begin(7,1,None)==0
assert lib.vcs_stream_step()==CORRUPT and c['mock_publish_calls'].value==0
reset(); c['mock_publish_status'].value=6
assert lib.vcs_stream_receive_begin(7,1,None)==0
assert lib.vcs_stream_step()==6 and c['mock_publish_calls'].value==1

reset(); assert lib.vcs_stream_receive_begin(7,0,None)==USAGE
assert c['mock_receive_calls'].value==0 and lib.vcs_stream_step()==CORRUPT
reset(); c['mock_receive_begin'].value=CORRUPT
assert lib.vcs_stream_receive_begin(7,1,None)==CORRUPT
assert lib.vcs_stream_step()==CORRUPT
reset(); c['mock_export_status'].value=CORRUPT
assert lib.vcs_stream_send_begin(7,9,1,seed)==CORRUPT
assert lib.vcs_stream_step()==CORRUPT
print('VCS stream: PASS (send, receive, retry, publish-once, mismatch, failures)')
