; Single-session non-blocking Git protocol v2 server over native unet TCP.
%include "include/vcs.inc"
%include "include/wire.inc"
bits 64
default rel

extern bridge_git_serve
extern vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_close
extern vcs_sync_unet_send,vcs_sync_unet_receive

%define GIT_SERVER_ACCEPT       1
%define GIT_SERVER_ADVERTISE    2
%define GIT_SERVER_RECEIVE      3
%define GIT_SERVER_RESPOND      4
%define GIT_SERVER_DONE         5
%define GIT_REQUEST_CAP         4096
%define GIT_RESPONSE_CAP        (VCS_WIRE_MAX_PAYLOAD+128)

section .bss
server_state: resd 1
server_listener: resd 1
server_client: resd 1
server_commit: resq 1
server_offset: resq 1
server_length: resq 1
server_request: resb GIT_REQUEST_CAP
server_response: resb GIT_RESPONSE_CAP

section .text
global git_upload_server_begin,git_upload_server_step,git_upload_server_close

; EDI=local IPv4 (zero selects the stack default), ESI=host-order port,
; RDX=VCS commit ID. EAX=VCS_OK or an error.
git_upload_server_begin:
 test rdx,rdx
 jz .begin_usage
 mov [server_commit],rdx
 mov dword [server_listener],-1
 mov dword [server_client],-1
 mov qword [server_offset],0
 mov qword [server_length],0
 call vcs_sync_listen_begin
 test eax,eax
 js .begin_io
 mov [server_listener],eax
 mov dword [server_state],GIT_SERVER_ACCEPT
 xor eax,eax
 ret
.begin_usage:
 mov eax,VCS_ERR_USAGE
 ret
.begin_io:
 mov eax,VCS_ERR_IO
 ret

; Advance one non-blocking operation. EAX=VCS_XFER_AGAIN, VCS_OK, or error.
git_upload_server_step:
 mov eax,[server_state]
 cmp eax,GIT_SERVER_ACCEPT
 je .accept
 cmp eax,GIT_SERVER_ADVERTISE
 je .send
 cmp eax,GIT_SERVER_RECEIVE
 je .receive
 cmp eax,GIT_SERVER_RESPOND
 je .send
 cmp eax,GIT_SERVER_DONE
 je .complete
 mov eax,VCS_ERR_USAGE
 ret
.accept:
 mov edi,[server_listener]
 call vcs_sync_accept_poll
 test eax,eax
 js .again
 mov [server_client],eax
 xor edi,edi
 xor esi,esi
 xor edx,edx
 lea rcx,[server_response]
 mov r8d,GIT_RESPONSE_CAP
 xor r9d,r9d
 call bridge_git_serve
 test eax,eax
 jnz .return
 mov [server_length],rdx
 mov qword [server_offset],0
 mov dword [server_state],GIT_SERVER_ADVERTISE
 jmp .again
.send:
 mov rax,[server_length]
 sub rax,[server_offset]
 jz .sent
 mov edi,[server_client]
 lea rsi,[server_response]
 add rsi,[server_offset]
 mov rdx,rax
 call vcs_sync_unet_send
 test rax,rax
 js .again
 test rax,rax
 jz .again
 add [server_offset],rax
 jmp .again
.sent:
 cmp dword [server_state],GIT_SERVER_ADVERTISE
 jne .response_done
 mov qword [server_offset],0
 mov qword [server_length],0
 mov dword [server_state],GIT_SERVER_RECEIVE
 jmp .again
.response_done:
 mov dword [server_state],GIT_SERVER_DONE
.complete:
 xor eax,eax
 ret
.receive:
 mov rax,GIT_REQUEST_CAP
 sub rax,[server_length]
 jz .corrupt
 mov edi,[server_client]
 lea rsi,[server_request]
 add rsi,[server_length]
 mov rdx,rax
 call vcs_sync_unet_receive
 test rax,rax
 js .again
 test rax,rax
 jz .again
 add [server_length],rax
 cmp qword [server_length],4
 jb .again
 lea rdi,[server_request]
 add rdi,[server_length]
 cmp dword [rdi-4],'0000'
 jne .again
 mov edi,1
 lea rsi,[server_request]
 mov rdx,[server_length]
 lea rcx,[server_response]
 mov r8d,GIT_RESPONSE_CAP
 mov r9,[server_commit]
 call bridge_git_serve
 test eax,eax
 jnz .return
 mov [server_length],rdx
 mov qword [server_offset],0
 mov dword [server_state],GIT_SERVER_RESPOND
.again:
 mov eax,VCS_XFER_AGAIN
.return:
 ret
.corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

; Close any live client and listener. Safe after partial initialization.
git_upload_server_close:
 mov edi,[server_client]
 test edi,edi
 js .close_listener
 call vcs_sync_close
 mov dword [server_client],-1
.close_listener:
 mov edi,[server_listener]
 test edi,edi
 js .closed
 call vcs_sync_close
 mov dword [server_listener],-1
.closed:
 mov dword [server_state],0
 xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
