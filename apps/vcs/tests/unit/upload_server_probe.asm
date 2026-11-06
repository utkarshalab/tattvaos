bits 64
default rel
global mock_listen,mock_accept,mock_connect,mock_receive,mock_send
global mock_decode,mock_parse,mock_operation,mock_flags,mock_serve,mock_response_length
global mock_terminal,mock_session,mock_retain,mock_close_calls,mock_clear_calls
global vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_connect_poll,vcs_sync_close
global vcs_sync_unet_send,vcs_sync_unet_receive,bridge_pkt_decode,bridge_pkt_encode
global bridge_git_serve,bridge_git_serve_terminal,git_protocol_v2_parse_request
global git_protocol_v2_clear_haves,git_protocol_v2_retain_haves
global git_protocol_v2_set_session_id

section .bss
mock_listen: resq 1
mock_accept: resq 1
mock_connect: resq 1
mock_receive: resq 1
mock_send: resq 1
mock_decode: resq 1
mock_parse: resq 1
mock_operation: resq 1
mock_flags: resq 1
mock_serve: resq 1
mock_response_length: resq 1
mock_terminal: resq 1
mock_session: resq 1
mock_retain: resq 1
mock_close_calls: resq 1
mock_clear_calls: resq 1

section .rodata
service: db 'git-upload-pack /',0,0,'version=2',0
service_len equ $-service

section .text
vcs_sync_listen_begin: mov rax,[mock_listen]
 ret
vcs_sync_accept_poll: mov rax,[mock_accept]
 ret
vcs_sync_connect_poll: mov rax,[mock_connect]
 ret
vcs_sync_close: inc qword [mock_close_calls]
 xor eax,eax
 ret
vcs_sync_unet_send: mov rax,[mock_send]
 ret
vcs_sync_unet_receive:
 mov rax,[mock_receive]
 test rax,rax
 jle .receive_done
 cmp rax,4
 jb .receive_done
 mov dword [rsi+rax-4],'0000'
.receive_done:
 ret
bridge_pkt_decode:
 mov rax,[mock_decode]
 test rax,rax
 jnz .decode_done
 lea rdx,[service]
 mov ecx,service_len
 mov r8,rsi
 xor r9d,r9d
.decode_done:
 ret
bridge_pkt_encode:
 mov byte [rdx],'E'
 mov edx,1
 xor eax,eax
 ret
bridge_git_serve:
 mov rax,[mock_serve]
 mov rdx,[mock_response_length]
 ret
bridge_git_serve_terminal: mov rax,[mock_terminal]
 ret
git_protocol_v2_parse_request:
 mov rax,[mock_parse]
 mov rdx,[mock_operation]
 mov r8,[mock_flags]
 ret
git_protocol_v2_clear_haves: inc qword [mock_clear_calls]
 xor eax,eax
 ret
git_protocol_v2_retain_haves: mov rax,[mock_retain]
 ret
git_protocol_v2_set_session_id: mov rax,[mock_session]
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
