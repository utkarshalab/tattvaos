%include "include/vcs.inc"
%include "include/wire.inc"
%include "include/client.inc"
bits 64
default rel

extern vcs_sync_client_begin,vcs_sync_client_step,vcs_sync_client_close
global client_begin_probe
global mock_encode_status,mock_connect_fd,mock_poll_status,mock_send_begin_status
global mock_receive_begin_status,mock_step_status,mock_decode_status
global mock_remote_status,mock_bundle_count,mock_head,mock_close_fd
global mock_encode_calls,mock_send_calls,mock_receive_calls,mock_step_calls
global vcs_sync_request_encode,vcs_sync_response_decode
global vcs_sync_connect_begin,vcs_sync_connect_poll,vcs_sync_close
global vcs_sync_send_begin,vcs_sync_receive_begin,vcs_sync_step
global vcs_sync_unet_send,vcs_sync_unet_receive,vcs_identity_trust_key

section .bss
mock_encode_status: resq 1
mock_connect_fd: resq 1
mock_poll_status: resq 1
mock_send_begin_status: resq 1
mock_receive_begin_status: resq 1
mock_step_status: resq 1
mock_decode_status: resq 1
mock_remote_status: resq 1
mock_bundle_count: resq 1
mock_head: resb 32
mock_close_fd: resq 1
mock_encode_calls: resq 1
mock_send_calls: resq 1
mock_receive_calls: resq 1
mock_step_calls: resq 1
mock_seed: resb 32

section .text
; Same six register arguments as client begin; supplies deterministic stack args.
client_begin_probe:
 sub rsp,8
 push qword 5
 lea rax,[mock_seed]
 push rax
 call vcs_sync_client_begin
 add rsp,24
 ret

vcs_sync_request_encode:
 inc qword [mock_encode_calls]
 mov rax,[mock_encode_status]
 ret
vcs_sync_connect_begin:
 mov rax,[mock_connect_fd]
 ret
vcs_sync_connect_poll:
 mov rax,[mock_poll_status]
 ret
vcs_sync_send_begin:
 inc qword [mock_send_calls]
 mov rax,[mock_send_begin_status]
 ret
vcs_sync_receive_begin:
 inc qword [mock_receive_calls]
 mov rax,[mock_receive_begin_status]
 ret
vcs_sync_step:
 inc qword [mock_step_calls]
 mov rax,[mock_step_status]
 ret
vcs_sync_response_decode:
 mov rax,[mock_decode_status]
 mov rdx,[mock_remote_status]
 mov rcx,[mock_bundle_count]
 lea r8,[mock_head]
 ret
vcs_sync_close:
 mov [mock_close_fd],rdi
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
