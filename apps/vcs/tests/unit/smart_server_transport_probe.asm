bits 64
default rel
global mock_net_input,mock_net_length,mock_net_offset,mock_net_output
global mock_net_output_length,mock_net_chunk,mock_net_close
global vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_connect_poll,vcs_sync_close
global vcs_sync_unet_send,vcs_sync_unet_receive

section .bss
mock_net_input: resq 1
mock_net_length: resq 1
mock_net_offset: resq 1
mock_net_output: resb 131072
mock_net_output_length: resq 1
mock_net_chunk: resq 1
mock_net_close: resq 1

section .text
vcs_sync_listen_begin:
 mov eax,3
 ret
vcs_sync_accept_poll:
 mov eax,7
 ret
vcs_sync_connect_poll:
 xor eax,eax
 ret
vcs_sync_close:
 inc qword [mock_net_close]
 xor eax,eax
 ret
vcs_sync_unet_receive:
 mov r8,[mock_net_length]
 sub r8,[mock_net_offset]
 jz .empty
 cmp r8,rdx
 jbe .receive_capacity
 mov r8,rdx
.receive_capacity:
 mov rax,[mock_net_chunk]
 test rax,rax
 jz .receive_copy
 cmp r8,rax
 jbe .receive_copy
 mov r8,rax
.receive_copy:
 mov rax,[mock_net_input]
 add rax,[mock_net_offset]
 mov rdi,rsi
 mov rsi,rax
 mov rcx,r8
 rep movsb
 add [mock_net_offset],r8
 mov rax,r8
 ret
.empty:
 mov rax,-1
 ret
vcs_sync_unet_send:
 mov r8,rdx
 mov rax,[mock_net_chunk]
 test rax,rax
 jz .send_copy
 cmp r8,rax
 jbe .send_copy
 mov r8,rax
.send_copy:
 lea rdi,[mock_net_output]
 add rdi,[mock_net_output_length]
 mov rcx,r8
 rep movsb
 add [mock_net_output_length],r8
 mov rax,r8
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
