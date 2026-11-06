"""Cooperative Git upload server state-machine coverage."""
import ctypes
import sys

lib = ctypes.CDLL(sys.argv[1])
lib.git_upload_server_begin.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint64]
for name in ('git_upload_server_begin', 'git_upload_server_step',
             'git_upload_server_rearm', 'git_upload_server_close',
             'git_upload_server_has_client', 'git_upload_server_progress'):
    getattr(lib, name).restype = ctypes.c_uint64

def q(name):
    return ctypes.c_uint64.in_dll(lib, name)

names = ('mock_listen mock_accept mock_connect mock_receive mock_send mock_decode '
         'mock_parse mock_operation mock_flags mock_serve mock_response_length '
         'mock_terminal mock_session mock_retain mock_close_calls mock_clear_calls').split()
m = {name: q(name) for name in names}
AGAIN, IO, CORRUPT, USAGE = 1, 4, 5, 8

def reset():
    for value in m.values(): value.value = 0
    m['mock_listen'].value = 3
    m['mock_accept'].value = 7
    m['mock_receive'].value = 32
    m['mock_send'].value = 8
    m['mock_response_length'].value = 8
    m['mock_operation'].value = 2

reset()
assert lib.git_upload_server_begin(0, 9418, 9) == 0
assert m['mock_clear_calls'].value == 1 and lib.git_upload_server_has_client() == 0
assert lib.git_upload_server_step() == AGAIN and lib.git_upload_server_has_client() == 1
assert lib.git_upload_server_step() == AGAIN                    # service -> advertise
m['mock_send'].value = 4
assert lib.git_upload_server_step() == AGAIN                    # partial advertisement
assert lib.git_upload_server_step() == AGAIN
assert lib.git_upload_server_step() == AGAIN                    # advertise -> receive
m['mock_receive'].value = 8
assert lib.git_upload_server_step() == AGAIN                    # parse -> respond
m['mock_send'].value = 8
assert lib.git_upload_server_step() == AGAIN
assert lib.git_upload_server_step() == 0                        # terminal response
assert lib.git_upload_server_progress() >= 5
assert lib.git_upload_server_rearm() == 0 and m['mock_close_calls'].value == 1
assert lib.git_upload_server_has_client() == 0

reset()
assert lib.git_upload_server_begin(0, 9418, 9) == 0
assert lib.git_upload_server_step() == AGAIN
assert lib.git_upload_server_step() == AGAIN
m['mock_send'].value = 8
assert lib.git_upload_server_step() == AGAIN
assert lib.git_upload_server_step() == AGAIN
m['mock_receive'].value = 8; m['mock_parse'].value = CORRUPT
assert lib.git_upload_server_step() == AGAIN                    # queues ERR packet
m['mock_send'].value = 1
assert lib.git_upload_server_step() == AGAIN
assert lib.git_upload_server_step() == CORRUPT
assert lib.git_upload_server_begin(0, 9418, 0) == USAGE
assert lib.git_upload_server_step() == USAGE                    # invalid begin cleared stale DONE

reset(); m['mock_listen'].value = 0xffffffffffffffff
assert lib.git_upload_server_begin(0, 9418, 9) == IO
reset(); assert lib.git_upload_server_begin(0, 9418, 9) == 0
assert lib.git_upload_server_step() == AGAIN
m['mock_receive'].value = 0xffffffffffffffff; m['mock_connect'].value = 0
assert lib.git_upload_server_step() == AGAIN
m['mock_connect'].value = 1
assert lib.git_upload_server_step() == IO
assert lib.git_upload_server_close() == 0 and m['mock_close_calls'].value == 2
assert lib.git_upload_server_step() == USAGE

print('VCS upload server: PASS (accept, service, partial I/O, respond, error, rearm, close)')
