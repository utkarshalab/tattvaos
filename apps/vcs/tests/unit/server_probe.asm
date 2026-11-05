%include "include/vcs.inc"
%include "include/wire.inc"
bits 64
default rel
extern vcs_sync_server_begin
global server_begin_probe,mock_handler
global mock_listener_fd,mock_accept_fd,mock_poll,mock_receive_begin,mock_send_begin
global mock_step,mock_frame_op,mock_decode_status,mock_decode_op,mock_decode_count
global mock_handler_status,mock_handler_count,mock_response_encode,mock_close_count
global mock_head,mock_digest,mock_ref
global vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_connect_poll,vcs_sync_close
global vcs_sync_receive_begin,vcs_sync_send_begin,vcs_sync_step
global vcs_sync_request_decode,vcs_sync_response_encode
global vcs_sync_unet_send,vcs_sync_unet_receive,vcs_identity_trust_key
section .bss
mock_listener_fd: resq 1
mock_accept_fd: resq 1
mock_poll: resq 1
mock_receive_begin: resq 1
mock_send_begin: resq 1
mock_step: resq 1
mock_frame_op: resq 1
mock_decode_status: resq 1
mock_decode_op: resq 1
mock_decode_count: resq 1
mock_handler_status: resq 1
mock_handler_count: resq 1
mock_response_encode: resq 1
mock_close_count: resq 1
mock_head: resb 32
mock_digest: resb 32
mock_ref: resb 32
mock_seed: resb 32
section .text
server_begin_probe:
 lea rcx,[mock_seed]
 lea r8,[mock_handler]
 jmp vcs_sync_server_begin
mock_handler:
 mov rax,[mock_handler_status]
 mov rcx,[mock_handler_count]
 lea rdx,[mock_head]
 ret
vcs_sync_listen_begin:
 mov rax,[mock_listener_fd]
 ret
vcs_sync_accept_poll:
 mov rax,[mock_accept_fd]
 ret
vcs_sync_connect_poll:
 mov rax,[mock_poll]
 ret
vcs_sync_receive_begin:
 mov rax,[mock_receive_begin]
 ret
vcs_sync_send_begin:
 mov rax,[mock_send_begin]
 ret
vcs_sync_step:
 mov rax,[mock_step]
 mov rdx,[mock_frame_op]
 ret
vcs_sync_request_decode:
 mov rax,[mock_decode_status]
 mov rdx,[mock_decode_op]
 mov r11,[mock_decode_count]
 lea r8,[mock_digest]
 lea r9,[mock_ref]
 ret
vcs_sync_response_encode:
 mov rax,[mock_response_encode]
 ret
vcs_sync_close:
 inc qword [mock_close_count]
 xor eax,eax
 ret
vcs_sync_unet_send:
 mov rax,-1
 ret
vcs_sync_unet_receive:
 mov rax,-1
 ret
vcs_identity_trust_key:
 mov eax,1
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
