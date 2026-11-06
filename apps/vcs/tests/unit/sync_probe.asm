bits 64
default rel
extern vcs_sync_send_begin,vcs_sync_receive_begin
global sync_send_probe,sync_receive_probe,mock_io,mock_trust
global mock_io_result,mock_trust_result,mock_verify_result
global sha256_init,sha256_update,sha256_final
global signing_public_from_seed,signing_sign,signing_verify
global unet_socket,unet_bind,unet_listen,unet_accept,unet_connect,unet_get_state
global unet_close,unet_send,unet_recv
section .bss
mock_io_result: resq 1
mock_trust_result: resq 1
mock_verify_result: resq 1
mock_seed: resb 32
section .text
sync_send_probe:
 push qword 0
 lea rax,[mock_io]
 push rax
 lea rax,[mock_seed]
 push rax
 call vcs_sync_send_begin
 add rsp,24
 ret
sync_receive_probe:
 lea rcx,[mock_io]
 xor r8d,r8d
 lea r9,[mock_trust]
 jmp vcs_sync_receive_begin
mock_io:
 mov rax,[mock_io_result]
 ret
mock_trust:
 mov rax,[mock_trust_result]
 ret
sha256_init:
 xor eax,eax
 ret
sha256_update:
 xor eax,eax
 ret
sha256_final:
 mov rdi,rsi
 mov al,0xab
 mov ecx,32
 rep stosb
 xor eax,eax
 ret
signing_public_from_seed:
 mov al,0x11
 mov ecx,32
 rep stosb
 xor eax,eax
 ret
signing_sign:
 mov rdi,rdx
 mov al,0x22
 mov ecx,64
 rep stosb
 xor eax,eax
 ret
signing_verify:
 mov rax,[mock_verify_result]
 ret
unet_socket: mov rax,-1
 ret
unet_bind: mov rax,-1
 ret
unet_listen: mov rax,-1
 ret
unet_accept: mov rax,-1
 ret
unet_connect: mov rax,-1
 ret
unet_get_state: mov rax,-1
 ret
unet_close: xor eax,eax
 ret
unet_send: mov rax,-1
 ret
unet_recv: mov rax,-1
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
