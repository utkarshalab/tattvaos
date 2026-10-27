; Single-peer bounded bundle stream over the resumable signed frame engine.
%include "include/vcs.inc"
%include "include/wire.inc"
bits 64
default rel

extern vcs_bundle_export,vcs_bundle_publish
extern vcs_sync_send_begin,vcs_sync_receive_begin,vcs_sync_step,vcs_sync_result
extern vcs_sync_unet_send,vcs_sync_unet_receive
extern vcs_identity_trust_key

%define STREAM_SEND 1
%define STREAM_RECEIVE 2

section .bss
stream_mode: resq 1
stream_expected: resq 1
stream_seed: resq 1
stream_transfer: resb 512
stream_payload: resb VCS_WIRE_MAX_PAYLOAD

section .text
global vcs_stream_send_begin,vcs_stream_receive_begin,vcs_stream_step

; EDI=fd, RSI=commit ID, EDX=wire operation, RCX=seed32.
vcs_stream_send_begin:
 push rbx
 push r12
 push r13
 mov ebx,edi
 mov r12d,edx
 mov r13,rcx
 test r13,r13
 jz .send_usage
 mov rdi,rsi
 lea rsi,[stream_payload]
 mov edx,VCS_WIRE_MAX_PAYLOAD
 call vcs_bundle_export
 test eax,eax
 jnz .send_done
 mov r10,rdx
 mov r11,rcx
 sub rsp,8
 push rbx
 lea rax,[vcs_sync_unet_send]
 push rax
 push r13
 lea rdi,[stream_transfer]
 mov esi,r12d
 lea rdx,[stream_payload]
 mov rcx,r10
 mov r8,r11
 xor r9d,r9d
 call vcs_sync_send_begin
 add rsp,32
 test eax,eax
 jnz .send_done
 mov qword [stream_mode],STREAM_SEND
 mov [stream_expected],r12
 xor eax,eax
 jmp .send_done
.send_usage: mov eax,VCS_ERR_USAGE
.send_done:
 pop r13
 pop r12
 pop rbx
 ret

; EDI=fd, ESI=expected wire operation, RDX=optional local signing seed.
vcs_stream_receive_begin:
 push rbx
 mov ebx,edi
 mov [stream_expected],rsi
 mov [stream_seed],rdx
 lea rdi,[stream_transfer]
 lea rsi,[stream_payload]
 mov edx,VCS_WIRE_MAX_PAYLOAD
 lea rcx,[vcs_sync_unet_receive]
 mov r8d,ebx
 lea r9,[vcs_identity_trust_key]
 call vcs_sync_receive_begin
 test eax,eax
 jnz .receive_done
 mov qword [stream_mode],STREAM_RECEIVE
.receive_done:
 pop rbx
 ret

; Advance one frame. Receive success returns imported local ID in RDX.
vcs_stream_step:
 lea rdi,[stream_transfer]
 call vcs_sync_step
 cmp eax,VCS_XFER_AGAIN
 je .step_done
 test eax,eax
 jnz .step_done
 cmp qword [stream_mode],STREAM_SEND
 je .step_done
 cmp qword [stream_mode],STREAM_RECEIVE
 jne .step_corrupt
 lea rdi,[stream_transfer]
 call vcs_sync_result
 test eax,eax
 jnz .step_done
 cmp r8,[stream_expected]
 jne .step_corrupt
 mov rdi,rdx
 mov rsi,rcx
 mov rdx,[stream_seed]
 call vcs_bundle_publish
 jmp .step_done
.step_corrupt:
 mov eax,VCS_ERR_CORRUPT
.step_done:
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
