; Cooperative authenticated server negotiation. Bundle streaming follows READY.
%include "include/vcs.inc"
%include "include/wire.inc"
%include "include/sync_protocol.inc"
%include "include/server.inc"
bits 64
default rel

extern vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_connect_poll
extern vcs_sync_close,vcs_sync_receive_begin,vcs_sync_send_begin,vcs_sync_step
extern vcs_sync_unet_send,vcs_sync_unet_receive
extern vcs_sync_request_decode,vcs_sync_response_encode
extern vcs_identity_trust_key

section .text
global vcs_sync_server_begin,vcs_sync_server_step,vcs_sync_server_rearm
global vcs_sync_server_close

; RDI=state, ESI=local network-order IPv4, EDX=port, RCX=seed32,
; R8=policy handler(operation,digest,ref,count).
vcs_sync_server_begin:
 push rbx
 push r12
 mov rbx,rdi
 mov r12d,edx
 test rbx,rbx
 jz .begin_usage
 test rcx,rcx
 jz .begin_usage
 test r8,r8
 jz .begin_usage
 mov [rbx+vcs_server.seed],rcx
 mov [rbx+vcs_server.handler],r8
 mov edi,esi
 mov esi,r12d
 call vcs_sync_listen_begin
 test eax,eax
 js .begin_io
 mov [rbx+vcs_server.listener],eax
 mov dword [rbx+vcs_server.client],-1
 mov dword [rbx+vcs_server.phase],VS_ACCEPTING
 xor eax,eax
 jmp .begin_done
.begin_usage: mov eax,VCS_ERR_USAGE
 jmp .begin_done
.begin_io: mov eax,VCS_ERR_IO
.begin_done:
 pop r12
 pop rbx
 ret

; One cooperative server step. 0=negotiated/READY, 1=yield, else error.
vcs_sync_server_step:
 push rbx
 push r12
 mov rbx,rdi
 test rbx,rbx
 jz .step_usage
 mov eax,[rbx+vcs_server.phase]
 cmp eax,VS_ACCEPTING
 je .accept
 cmp eax,VS_RECV_REQUEST
 je .receive
 cmp eax,VS_SEND_RESPONSE
 je .send
 cmp eax,VS_READY
 je .ready
 jmp .step_io
.accept:
 mov edi,[rbx+vcs_server.listener]
 call vcs_sync_accept_poll
 test eax,eax
 js .again
 mov [rbx+vcs_server.client],eax
 lea rdi,[rbx+vcs_server.transfer]
 lea rsi,[rbx+vcs_server.request]
 mov edx,VS_MESSAGE
 lea rcx,[vcs_sync_unet_receive]
 mov r8d,eax
 lea r9,[vcs_identity_trust_key]
 call vcs_sync_receive_begin
 test eax,eax
 jnz .fail
 mov dword [rbx+vcs_server.phase],VS_RECV_REQUEST
 jmp .again
.receive:
 mov edi,[rbx+vcs_server.client]
 call vcs_sync_connect_poll
 test eax,eax
 jnz .fail
 lea rdi,[rbx+vcs_server.transfer]
 call vcs_sync_step
 cmp eax,VCS_XFER_AGAIN
 je .again
 test eax,eax
 jnz .fail
 mov r12d,edx                    ; signed frame operation
 lea rdi,[rbx+vcs_server.request]
 mov esi,VS_MESSAGE
 call vcs_sync_request_decode
 test eax,eax
 jnz .fail
 cmp edx,r12d
 jne .corrupt
 mov [rbx+vcs_server.operation],edx
 mov [rbx+vcs_server.incoming_count],r11
 mov edi,edx
 mov rsi,r8
 mov rdx,r9
 mov rcx,r11
 call [rbx+vcs_server.handler]
 cmp eax,VCS_ERR_UNSUPPORTED
 ja .corrupt
 mov [rbx+vcs_server.status],rax
 test eax,eax
 jz .handler_response
 xor edx,edx
 xor ecx,ecx
.handler_response:
 mov [rbx+vcs_server.outgoing_count],rcx
 lea rdi,[rbx+vcs_server.response]
 mov esi,eax
 ; RDX=head digest from handler, RCX=outgoing bundle count.
 call vcs_sync_response_encode
 test eax,eax
 jnz .fail
 mov eax,[rbx+vcs_server.client]
 push rax
 lea rax,[vcs_sync_unet_send]
 push rax
 push qword [rbx+vcs_server.seed]
 lea rdi,[rbx+vcs_server.transfer]
 mov esi,[rbx+vcs_server.operation]
 lea rdx,[rbx+vcs_server.response]
 mov ecx,VS_MESSAGE
 xor r8d,r8d
 xor r9d,r9d
 call vcs_sync_send_begin
 add rsp,24
 test eax,eax
 jnz .fail
 mov dword [rbx+vcs_server.phase],VS_SEND_RESPONSE
 jmp .again
.send:
 mov edi,[rbx+vcs_server.client]
 call vcs_sync_connect_poll
 test eax,eax
 jnz .fail
 lea rdi,[rbx+vcs_server.transfer]
 call vcs_sync_step
 cmp eax,VCS_XFER_AGAIN
 je .again
 test eax,eax
 jnz .fail
 mov dword [rbx+vcs_server.phase],VS_READY
.ready:
 mov rax,[rbx+vcs_server.status]
 jmp .step_done
.again:
 mov eax,VCS_XFER_AGAIN
 jmp .step_done
.corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .fail
.step_usage: mov eax,VCS_ERR_USAGE
 jmp .step_done
.step_io: mov eax,VCS_ERR_IO
.fail:
 mov dword [rbx+vcs_server.phase],VS_FAILED
.step_done:
 pop r12
 pop rbx
 ret

vcs_sync_server_close:
 push rbx
 mov rbx,rdi
 test rbx,rbx
 jz .close_usage
 mov edi,[rbx+vcs_server.client]
 test edi,edi
 js .close_listener
 call vcs_sync_close
.close_listener:
 mov edi,[rbx+vcs_server.listener]
 call vcs_sync_close
 xor eax,eax
 pop rbx
 ret
.close_usage:
 mov eax,VCS_ERR_USAGE
 pop rbx
 ret

; Close the completed peer but retain the listener for the next negotiation.
vcs_sync_server_rearm:
 push rbx
 mov rbx,rdi
 test rbx,rbx
 jz .rearm_usage
 mov edi,[rbx+vcs_server.client]
 test edi,edi
 js .rearm_state
 call vcs_sync_close
.rearm_state:
 mov dword [rbx+vcs_server.client],-1
 mov dword [rbx+vcs_server.phase],VS_ACCEPTING
 mov qword [rbx+vcs_server.incoming_count],0
 mov qword [rbx+vcs_server.outgoing_count],0
 mov qword [rbx+vcs_server.status],0
 xor eax,eax
 pop rbx
 ret
.rearm_usage:
 mov eax,VCS_ERR_USAGE
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
