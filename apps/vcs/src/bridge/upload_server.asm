; Single-session non-blocking Git protocol v2 server over native unet TCP.
%include "include/vcs.inc"
%include "include/wire.inc"
bits 64
default rel

extern bridge_git_serve,bridge_git_serve_terminal
extern bridge_pkt_decode,bridge_pkt_encode
extern git_protocol_v2_parse_request
extern vcs_sync_listen_begin,vcs_sync_accept_poll,vcs_sync_connect_poll,vcs_sync_close
extern vcs_sync_unet_send,vcs_sync_unet_receive

%define GIT_SERVER_ACCEPT       1
%define GIT_SERVER_SERVICE      2
%define GIT_SERVER_ADVERTISE    3
%define GIT_SERVER_RECEIVE      4
%define GIT_SERVER_RESPOND      5
%define GIT_SERVER_DONE         6
; Holds command headers, one want, 64 SHA-256 haves, done, and pkt framing.
%define GIT_REQUEST_CAP         8192
%define GIT_RESPONSE_CAP        (VCS_WIRE_MAX_PAYLOAD+128)

section .bss
server_state: resd 1
server_listener: resd 1
server_client: resd 1
server_commit: resq 1
server_operation: resq 1
server_result: resd 1
server_progress: resq 1
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
host_parameter: db 'host='
host_parameter_len equ $-host_parameter
error_payload: db 'ERR tattva-vcs: request rejected',10
error_payload_len equ $-error_payload

section .text
global git_upload_server_begin,git_upload_server_step,git_upload_server_rearm
global git_upload_server_progress,git_upload_server_has_client
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
 mov qword [server_progress],0
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
 inc qword [server_progress]
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
 inc qword [server_progress]
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
 je .response_refs_done
 cmp qword [server_operation],3
 je .response_continue
 jmp .response_terminal
.response_refs_done:
 cmp byte [server_seen_refs],1
 jne .corrupt
.response_continue:
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
 test r8,8192
 jz .request_operation_ready
 mov qword [server_operation],3
.request_operation_ready:
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
 cmp qword [server_operation],3
 jne .response_operation_ready
 call bridge_git_serve_terminal
 test eax,eax
 jz .response_operation_ready
 mov qword [server_operation],2
.response_operation_ready:
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
 inc qword [server_progress]
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

; Require the root upload-pack service and exact NUL-delimited protocol-v2
; parameters. One printable bounded host value precedes the required empty
; separator; unknown bounded extra parameters are ignored as Git requires.
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
 xor r8d,r8d                    ; exact version=2 seen
 ; The optional host parameter is the only token before the empty separator.
 cmp rsi,host_parameter_len
 jb .bad_service
 cmp dword [rdi],0x74736f68    ; "host"
 jne .parameter_separator
 cmp byte [rdi+4],'='
 jne .parameter_separator
 xor r11d,r11d
.host_end:
 cmp r11,rsi
 jae .bad_service
 cmp byte [rdi+r11],0
 je .host_ready
 inc r11
 jmp .host_end
.host_ready:
 cmp r11,host_parameter_len+1
 jb .bad_service
 cmp r11,host_parameter_len+255
 ja .bad_service
 mov eax,host_parameter_len
.host_byte:
 cmp rax,r11
 jae .host_done
 mov cl,[rdi+rax]
 cmp cl,33
 jb .bad_service
 cmp cl,126
 ja .bad_service
 inc rax
 jmp .host_byte
.host_done:
 lea rax,[r11+1]
 add rdi,rax
 sub rsi,rax
.parameter_separator:
 test rsi,rsi
 jz .bad_service
 cmp byte [rdi],0
 jne .bad_service
 inc rdi
 dec rsi
 test rsi,rsi
 jz .bad_service
.extra_parameter:
 xor r11d,r11d
.extra_end:
 cmp r11,rsi
 jae .bad_service
 cmp byte [rdi+r11],0
 je .extra_ready
 inc r11
 jmp .extra_end
.extra_ready:
 test r11,r11
 jz .bad_service
 cmp r11,255
 ja .bad_service
 cmp r11,version_parameter_len
 jne .next_extra
 xor eax,eax
 lea rdx,[version_parameter]
.version_byte:
 cmp rax,r11
 jae .version_ok
 mov cl,[rdi+rax]
 cmp cl,[rdx+rax]
 jne .next_extra
 inc rax
 jmp .version_byte
.version_ok:
 test r8b,r8b
 jnz .bad_service
 mov r8b,1
.next_extra:
 lea rax,[r11+1]
 add rdi,rax
 sub rsi,rax
 jnz .extra_parameter
 cmp r8b,1
 jne .bad_service
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

; Close a completed or failed accepted client and retain the listener for
; another bounded session using the same immutable commit snapshot.
git_upload_server_rearm:
 mov eax,[server_state]
 cmp eax,GIT_SERVER_SERVICE
 jb .rearm_usage
 cmp eax,GIT_SERVER_DONE
 ja .rearm_usage
 cmp dword [server_listener],0
 jl .rearm_usage
 cmp dword [server_client],0
 jl .rearm_usage
 mov edi,[server_client]
 call vcs_sync_close
 mov dword [server_client],-1
 mov dword [server_result],VCS_OK
 mov qword [server_operation],0
 mov qword [server_offset],0
 mov qword [server_length],0
 mov byte [server_seen_refs],0
 mov dword [server_state],GIT_SERVER_ACCEPT
 inc qword [server_progress]
 xor eax,eax
 ret
.rearm_usage:
 mov eax,VCS_ERR_USAGE
 ret

git_upload_server_progress:
 mov rax,[server_progress]
 ret

git_upload_server_has_client:
 xor eax,eax
 cmp dword [server_client],0
 setge al
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
