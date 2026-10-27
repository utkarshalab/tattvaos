; Cooperative client negotiation over signed native unet frames.
%include "include/vcs.inc"
%include "include/wire.inc"
%include "include/sync_protocol.inc"
%include "include/client.inc"
bits 64
default rel

extern vcs_sync_request_encode,vcs_sync_response_decode
extern vcs_sync_connect_begin,vcs_sync_connect_poll,vcs_sync_close
extern vcs_sync_send_begin,vcs_sync_receive_begin,vcs_sync_step
extern vcs_sync_unet_send,vcs_sync_unet_receive
extern vcs_identity_trust_key

section .text
global vcs_sync_client_begin,vcs_sync_client_step,vcs_sync_client_close

; RDI=client state, ESI=operation, EDX=network-order IPv4, ECX=port,
; R8=have digest32 or zero, R9=ref or zero; stack args: seed32, send count.
vcs_sync_client_begin:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12d,edx
 mov r13d,ecx
 test rbx,rbx
 jz .begin_usage
 mov rax,[rsp+32]
 test rax,rax
 jz .begin_usage
 mov [rbx+vcs_client.seed],rax
 mov rax,[rsp+40]
 mov [rbx+vcs_client.send_count],rax
 mov [rbx+vcs_client.operation],esi
 lea rdi,[rbx+vcs_client.request]
 mov rdx,r8
 mov rcx,r9
 mov r8,[rbx+vcs_client.send_count]
 call vcs_sync_request_encode
 test eax,eax
 jnz .begin_done
 mov edi,r12d
 mov esi,r13d
 call vcs_sync_connect_begin
 test eax,eax
 js .begin_io
 mov [rbx+vcs_client.fd],eax
 mov dword [rbx+vcs_client.phase],VC_CONNECTING
 xor eax,eax
 jmp .begin_done
.begin_usage: mov eax,VCS_ERR_USAGE
 jmp .begin_done
.begin_io: mov eax,VCS_ERR_IO
.begin_done:
 pop r13
 pop r12
 pop rbx
 ret

; Advance at most one socket operation. 0=negotiated, 1=yield/retry, else error.
vcs_sync_client_step:
 push rbx
 mov rbx,rdi
 test rbx,rbx
 jz .step_usage
 mov eax,[rbx+vcs_client.phase]
 cmp eax,VC_CONNECTING
 je .connect
 cmp eax,VC_SEND_REQUEST
 je .send
 cmp eax,VC_RECV_RESPONSE
 je .receive
 cmp eax,VC_READY
 je .ready
 jmp .step_io
.connect:
 mov edi,[rbx+vcs_client.fd]
 call vcs_sync_connect_poll
 cmp eax,VCS_XFER_AGAIN
 je .again
 test eax,eax
 jnz .fail
 ; Initialize the signed request sender. Stack arguments are seed, callback, fd.
 mov eax,[rbx+vcs_client.fd]
 sub rsp,8
 push rax
 lea rax,[vcs_sync_unet_send]
 push rax
 push qword [rbx+vcs_client.seed]
 lea rdi,[rbx+vcs_client.transfer]
 mov esi,[rbx+vcs_client.operation]
 lea rdx,[rbx+vcs_client.request]
 mov ecx,VS_MESSAGE
 xor r8d,r8d
 xor r9d,r9d
 call vcs_sync_send_begin
 add rsp,32
 test eax,eax
 jnz .fail
 mov dword [rbx+vcs_client.phase],VC_SEND_REQUEST
 jmp .again
.send:
 mov edi,[rbx+vcs_client.fd]
 call vcs_sync_connect_poll
 test eax,eax
 jnz .fail
 lea rdi,[rbx+vcs_client.transfer]
 call vcs_sync_step
 cmp eax,VCS_XFER_AGAIN
 je .again
 test eax,eax
 jnz .fail
 lea rdi,[rbx+vcs_client.transfer]
 lea rsi,[rbx+vcs_client.response]
 mov edx,VS_MESSAGE
 lea rcx,[vcs_sync_unet_receive]
 mov r8d,[rbx+vcs_client.fd]
 lea r9,[vcs_identity_trust_key]
 call vcs_sync_receive_begin
 test eax,eax
 jnz .fail
 mov dword [rbx+vcs_client.phase],VC_RECV_RESPONSE
 jmp .again
.receive:
 mov edi,[rbx+vcs_client.fd]
 call vcs_sync_connect_poll
 test eax,eax
 jnz .fail
 lea rdi,[rbx+vcs_client.transfer]
 call vcs_sync_step
 cmp eax,VCS_XFER_AGAIN
 je .again
 test eax,eax
 jnz .fail
 lea rdi,[rbx+vcs_client.response]
 mov esi,VS_MESSAGE
 call vcs_sync_response_decode
 test eax,eax
 jnz .fail
 test edx,edx
 jnz .remote_error
 mov [rbx+vcs_client.bundle_count],rcx
 mov rsi,r8
 lea rdi,[rbx+vcs_client.head_digest]
 mov ecx,32
 rep movsb
 mov dword [rbx+vcs_client.phase],VC_READY
.ready:
 xor eax,eax
 jmp .step_done
.remote_error:
 mov eax,edx
 jmp .fail
.again:
 mov eax,VCS_XFER_AGAIN
 jmp .step_done
.step_usage: mov eax,VCS_ERR_USAGE
 jmp .step_done
.step_io: mov eax,VCS_ERR_IO
.fail:
 mov dword [rbx+vcs_client.phase],VC_FAILED
.step_done:
 pop rbx
 ret

vcs_sync_client_close:
 test rdi,rdi
 jz .close_usage
 mov edi,[rdi+vcs_client.fd]
 jmp vcs_sync_close
.close_usage:
 mov eax,VCS_ERR_USAGE
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
