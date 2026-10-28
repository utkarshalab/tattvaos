; Single-session non-blocking Git protocol v2 server over native unet TCP.
%include "include/vcs.inc"
%include "include/wire.inc"
bits 64
default rel

extern bridge_git_serve,bridge_pkt_decode,bridge_pkt_encode
extern git_protocol_v2_parse_request
extern vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_connect_poll,vcs_sync_close
extern vcs_sync_unet_send,vcs_sync_unet_receive

%define GIT_SERVER_ACCEPT       1
%define GIT_SERVER_SERVICE      2
%define GIT_SERVER_ADVERTISE    3
%define GIT_SERVER_RECEIVE      4
%define GIT_SERVER_RESPOND      5
%define GIT_SERVER_DONE         6
%define GIT_REQUEST_CAP         4096
%define GIT_RESPONSE_CAP        (VCS_WIRE_MAX_PAYLOAD+128)

section .bss
server_state: resd 1
server_listener: resd 1
server_client: resd 1
server_commit: resq 1
server_operation: resq 1
server_result: resd 1
server_offset: resq 1
server_length: resq 1
server_seen_refs: resb 1
server_request: resb GIT_REQUEST_CAP
server_response: resb GIT_RESPONSE_CAP

section .rodata
upload_service: db 'git-upload-pack /',0
upload_service_len equ $-upload_service-1
version_parameter: db 'version=2',0
version_parameter_len equ $-version_parameter-1
error_payload: db 'ERR tattva-vcs: request rejected',10
error_payload_len equ $-error_payload

section .text
global git_upload_server_begin,git_upload_server_step,git_upload_server_rearm
global git_upload_server_close

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
 mov dword [server_result],VCS_OK
 mov byte [server_seen_refs],0
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
 cmp eax,GIT_SERVER_SERVICE
 je .service
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
 mov qword [server_offset],0
 mov qword [server_length],0
 mov dword [server_state],GIT_SERVER_SERVICE
 jmp .again
.service:
 call .receive_request_bytes
 cmp eax,VCS_XFER_AGAIN
 je .return
 test eax,eax
 jnz .return
 lea rdi,[server_request]
 mov rsi,[server_length]
 call bridge_pkt_decode
 cmp eax,VCS_XFER_AGAIN
 je .again
 test eax,eax
 jnz .protocol_error
 cmp r8,[server_length]
 jne .corrupt
 mov rdi,rdx
 mov rsi,rcx
 call .validate_service_request
 test eax,eax
 jnz .protocol_error
 xor edi,edi
 xor esi,esi
 xor edx,edx
 lea rcx,[server_response]
 mov r8d,GIT_RESPONSE_CAP
 xor r9d,r9d
 call bridge_git_serve
 test eax,eax
 jnz .protocol_error
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
 js .peer_status
 test rax,rax
 jz .peer_status
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
 cmp qword [server_operation],1
 jne .response_terminal
 cmp byte [server_seen_refs],1
 jne .corrupt
 mov qword [server_offset],0
 mov qword [server_length],0
 mov dword [server_state],GIT_SERVER_RECEIVE
 jmp .again
.response_terminal:
 mov dword [server_state],GIT_SERVER_DONE
.complete:
 mov eax,[server_result]
 ret
.receive:
 call .receive_request_bytes
 cmp eax,VCS_XFER_AGAIN
 je .return
 test eax,eax
 jnz .return
 cmp qword [server_length],4
 jb .again
 lea rdi,[server_request]
 add rdi,[server_length]
 cmp dword [rdi-4],'0000'
 jne .again
 lea rdi,[server_request]
 mov rsi,[server_length]
 call git_protocol_v2_parse_request
 test eax,eax
 jnz .protocol_error
 mov [server_operation],rdx
 cmp rdx,1
 jne .dispatch_request
 cmp byte [server_seen_refs],0
 jne .corrupt
 mov byte [server_seen_refs],1
.dispatch_request:
 mov edi,1
 lea rsi,[server_request]
 mov rdx,[server_length]
 lea rcx,[server_response]
 mov r8d,GIT_RESPONSE_CAP
 mov r9,[server_commit]
 call bridge_git_serve
 test eax,eax
 jnz .protocol_error
 mov [server_length],rdx
 mov qword [server_offset],0
 mov dword [server_state],GIT_SERVER_RESPOND
 jmp .again

; Accumulate bytes without assuming TCP segment boundaries.
.receive_request_bytes:
 mov rax,GIT_REQUEST_CAP
 sub rax,[server_length]
 jz .corrupt
 mov edi,[server_client]
 lea rsi,[server_request]
 add rsi,[server_length]
 mov rdx,rax
 call vcs_sync_unet_receive
 test rax,rax
 js .peer_status
 test rax,rax
 jz .peer_status
 add [server_length],rax
 xor eax,eax
 ret

; Native unet reports an empty queue and socket failure with the same negative
; result. Retry only while the accepted TCP socket remains established.
.peer_status:
 mov edi,[server_client]
 call vcs_sync_connect_poll
 test eax,eax
 jz .again
 mov eax,VCS_ERR_IO
 ret

; Require the upload-pack service for the root repository and protocol v2.
; RDI=decoded payload, RSI=payload length.
.validate_service_request:
 cmp rsi,upload_service_len+1+version_parameter_len+1
 jb .bad_service
 lea rdx,[upload_service]
 mov ecx,upload_service_len
.service_prefix:
 mov al,[rdi]
 cmp al,[rdx]
 jne .bad_service
 inc rdi
 inc rdx
 loop .service_prefix
 cmp byte [rdi],0                 ; only the root repository is exported
 jne .bad_service
 inc rdi
 sub rsi,upload_service_len+1
.find_version:
 cmp rsi,version_parameter_len
 jb .bad_service
 lea rdx,[version_parameter]
 mov r8,rdi
 mov ecx,version_parameter_len
.version_bytes:
 mov al,[r8]
 cmp al,[rdx]
 jne .next_parameter_byte
 inc r8
 inc rdx
 loop .version_bytes
 cmp rsi,version_parameter_len
 je .service_ok
 cmp byte [r8],0
 je .service_ok
.next_parameter_byte:
 inc rdi
 dec rsi
 jmp .find_version
.service_ok:
 xor eax,eax
 ret
.bad_service:
 mov eax,VCS_ERR_UNSUPPORTED
 ret
.protocol_error:
 mov [server_result],eax
 mov qword [server_operation],2
 lea rdi,[error_payload]
 mov esi,error_payload_len
 lea rdx,[server_response]
 mov ecx,GIT_RESPONSE_CAP
 call bridge_pkt_encode
 test eax,eax
 jnz .return
 mov [server_length],rdx
 mov qword [server_offset],0
 mov dword [server_state],GIT_SERVER_RESPOND
 jmp .again
.again:
 mov eax,VCS_XFER_AGAIN
.return:
 ret
.corrupt:
 mov eax,VCS_ERR_CORRUPT
 jmp .protocol_error

; Close the completed client and retain the listener for another bounded
; session using the same immutable commit snapshot.
git_upload_server_rearm:
 cmp dword [server_state],GIT_SERVER_DONE
 jne .rearm_usage
 mov edi,[server_client]
 test edi,edi
 js .rearm_state
 call vcs_sync_close
.rearm_state:
 mov dword [server_client],-1
 mov dword [server_result],VCS_OK
 mov qword [server_operation],0
 mov qword [server_offset],0
 mov qword [server_length],0
 mov byte [server_seen_refs],0
 mov dword [server_state],GIT_SERVER_ACCEPT
 xor eax,eax
 ret
.rearm_usage:
 mov eax,VCS_ERR_USAGE
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
