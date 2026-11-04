"""Cooperative native client state-machine coverage with deterministic I/O."""
import ctypes
import struct
import sys

lib = ctypes.CDLL(sys.argv[1])
byte_pointer = ctypes.POINTER(ctypes.c_ubyte)
lib.client_begin_probe.argtypes = [byte_pointer, ctypes.c_uint32,
                                   ctypes.c_uint32, ctypes.c_uint32,
                                   byte_pointer, ctypes.c_char_p]
lib.client_begin_probe.restype = ctypes.c_uint64
lib.vcs_sync_client_step.argtypes = [byte_pointer]
lib.vcs_sync_client_step.restype = ctypes.c_uint64
lib.vcs_sync_client_close.argtypes = [byte_pointer]
lib.vcs_sync_client_close.restype = ctypes.c_uint64

names = ('mock_encode_status', 'mock_connect_fd', 'mock_poll_status',
         'mock_send_begin_status', 'mock_receive_begin_status',
         'mock_step_status', 'mock_decode_status', 'mock_remote_status',
         'mock_bundle_count', 'mock_close_fd', 'mock_encode_calls',
         'mock_send_calls', 'mock_receive_calls', 'mock_step_calls')
control = {name: ctypes.c_uint64.in_dll(lib, name) for name in names}
mock_head = (ctypes.c_ubyte * 32).in_dll(lib, 'mock_head')

STATE_SIZE = 776
VC_CONNECTING, VC_SEND, VC_RECEIVE, VC_READY, VC_FAILED = range(5)
VCS_AGAIN, VCS_IO, VCS_CORRUPT, VCS_USAGE = 1, 4, 5, 8

def reset():
    for value in control.values():
        value.value = 0
    control['mock_connect_fd'].value = 7
    for index in range(32):
        mock_head[index] = 0x40 + index

def state():
    return (ctypes.c_ubyte * STATE_SIZE)()

def phase(client):
    return struct.unpack_from('<I', client, 0)[0]

def begin(client):
    digest = (ctypes.c_ubyte * 32)(*range(32))
    status = lib.client_begin_probe(client, 1, 0x0100007F, 9418,
                                    digest, b'main')
    return status

reset()
client = state()
assert begin(client) == 0
assert phase(client) == VC_CONNECTING
assert struct.unpack_from('<I', client, 8)[0] == 7
assert struct.unpack_from('<Q', client, 32)[0] == 5
assert control['mock_encode_calls'].value == 1

control['mock_poll_status'].value = VCS_AGAIN
assert lib.vcs_sync_client_step(client) == VCS_AGAIN
assert phase(client) == VC_CONNECTING
control['mock_poll_status'].value = 0
assert lib.vcs_sync_client_step(client) == VCS_AGAIN
assert phase(client) == VC_SEND and control['mock_send_calls'].value == 1
control['mock_step_status'].value = VCS_AGAIN
assert lib.vcs_sync_client_step(client) == VCS_AGAIN
assert phase(client) == VC_SEND
control['mock_step_status'].value = 0
assert lib.vcs_sync_client_step(client) == VCS_AGAIN
assert phase(client) == VC_RECEIVE and control['mock_receive_calls'].value == 1
control['mock_step_status'].value = VCS_AGAIN
assert lib.vcs_sync_client_step(client) == VCS_AGAIN
control['mock_step_status'].value = 0
control['mock_bundle_count'].value = 3
assert lib.vcs_sync_client_step(client) == 0
assert phase(client) == VC_READY
assert struct.unpack_from('<Q', client, 24)[0] == 3
assert bytes(client[232:264]) == bytes(range(0x40, 0x60))
assert lib.vcs_sync_client_step(client) == 0
assert lib.vcs_sync_client_close(client) == 0
assert control['mock_close_fd'].value == 7

def drive_to_receive():
    reset()
    current = state()
    assert begin(current) == 0
    assert lib.vcs_sync_client_step(current) == VCS_AGAIN
    assert lib.vcs_sync_client_step(current) == VCS_AGAIN
    assert phase(current) == VC_RECEIVE
    return current

client = drive_to_receive()
control['mock_remote_status'].value = 6
assert lib.vcs_sync_client_step(client) == 6 and phase(client) == VC_FAILED

client = drive_to_receive()
control['mock_decode_status'].value = VCS_CORRUPT
assert lib.vcs_sync_client_step(client) == VCS_CORRUPT
assert phase(client) == VC_FAILED

for failing_control, expected in (('mock_poll_status', VCS_IO),
                                  ('mock_send_begin_status', VCS_CORRUPT)):
    reset()
    client = state()
    assert begin(client) == 0
    control[failing_control].value = expected
    assert lib.vcs_sync_client_step(client) == expected
    assert phase(client) == VC_FAILED

reset()
client = state()
control['mock_encode_status'].value = VCS_USAGE
struct.pack_into('<I', client, 0, VC_READY)
struct.pack_into('<Q', client, 24, 99)
client[232:264] = bytes([0xCC] * 32)
assert begin(client) == VCS_USAGE
assert phase(client) == VC_FAILED
assert struct.unpack_from('<i', client, 8)[0] == -1
assert struct.unpack_from('<Q', client, 24)[0] == 0
assert bytes(client[232:264]) == bytes(32)
assert control['mock_connect_fd'].value == 7
reset()
client = state()
control['mock_connect_fd'].value = ctypes.c_uint64(-1).value
assert begin(client) == VCS_IO
assert phase(client) == VC_FAILED and struct.unpack_from('<i', client, 8)[0] == -1
assert lib.vcs_sync_client_step(None) == VCS_USAGE
assert lib.vcs_sync_client_close(None) == VCS_USAGE

print('VCS client: PASS (connect, retry, send/receive, remote errors, close, failures)')
