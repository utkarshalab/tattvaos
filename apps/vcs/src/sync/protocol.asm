; Bounded request/response payloads transported inside authenticated wire frames.
%include "include/vcs.inc"
%include "include/sync_protocol.inc"
bits 64
default rel

section .text
global vcs_sync_request_encode,vcs_sync_request_decode
global vcs_sync_response_encode,vcs_sync_response_decode

; RDI=output96, ESI=operation, RDX=have-digest32 or zero, RCX=ref or zero,
; R8=bundle count (push only, 1..64; zero for fetch/clone).
vcs_sync_request_encode:
 test rdi,rdi
 jz .request_usage
 cmp esi,VS_OP_FETCH
 jb .request_usage
 cmp esi,VS_OP_CLONE
 ja .request_usage
 push rbx
 push r12
 mov rbx,rdi
 mov r12,rcx
 mov r11,r8
 cmp esi,VS_OP_PUSH
 je .request_push_count
 test r11,r11
 jnz .request_bad_pop
 jmp .request_count_ok
.request_push_count:
 cmp r11,64
 ja .request_bad_pop
.request_count_ok:
 push rsi
 xor eax,eax
 mov ecx,VS_MESSAGE/8
 rep stosq
 pop rsi
 mov rax,VS_REQ_MAGIC
 mov [rbx+VS_MAGIC],rax
 mov dword [rbx+VS_VERSION_O],VS_VERSION
 mov [rbx+VS_OPERATION],esi
 mov qword [rbx+VS_FLAGS],VS_CAP_V1
 mov [rbx+VS_COUNT],r11
 test rdx,rdx
 jz .request_ref
 lea rdi,[rbx+VS_DIGEST]
 mov rsi,rdx
 mov ecx,32
 rep movsb
.request_ref:
 test r12,r12
 jz .request_ok
 mov rdi,r12
 call valid_ref
 test eax,eax
 jz .request_bad_pop
 lea rdi,[rbx+VS_REF]
 mov rsi,r12
 mov ecx,VS_REF_BYTES
.request_ref_copy:
 lodsb
 stosb
 test al,al
 jz .request_ok
 loop .request_ref_copy
 jmp .request_bad_pop
.request_ok:
 xor eax,eax
 pop r12
 pop rbx
 ret
.request_bad_pop:
 pop r12
 pop rbx
.request_usage:
 mov eax,VCS_ERR_USAGE
 ret

; RDI=payload, RSI=length. RAX=status; EDX=operation, RCX=flags,
; R8=have-digest pointer, R9=ref pointer (zero when absent), R11=count.
vcs_sync_request_decode:
 test rdi,rdi
 jz .decode_usage
 cmp rsi,VS_MESSAGE
 jne .decode_corrupt
 mov rax,VS_REQ_MAGIC
 cmp [rdi+VS_MAGIC],rax
 jne .decode_corrupt
 cmp dword [rdi+VS_VERSION_O],VS_VERSION
 jne .decode_corrupt
 mov edx,[rdi+VS_OPERATION]
 cmp edx,VS_OP_FETCH
 jb .decode_corrupt
 cmp edx,VS_OP_CLONE
 ja .decode_corrupt
 mov r10d,edx
 mov rcx,[rdi+VS_FLAGS]
 test rcx,~VS_CAP_V1
 jnz .decode_corrupt
 test rcx,VS_CAP_SIGNED
 jz .decode_corrupt
 mov r11,[rdi+VS_COUNT]
 cmp edx,VS_OP_PUSH
 je .decode_push_count
 test r11,r11
 jnz .decode_corrupt
 jmp .decode_count_ok
.decode_push_count:
 cmp r11,64
 ja .decode_corrupt
.decode_count_ok:
 lea r8,[rdi+VS_DIGEST]
 xor r9d,r9d
 cmp byte [rdi+VS_REF],0
 je .decode_ok
 push rdi
 lea rdi,[rdi+VS_REF]
 call valid_ref
 test eax,eax
 jz .decode_ref_bad
 lea r11,[rdi+VS_REF]
 lea eax,[edx+1]
.decode_ref_zero:
 cmp eax,VS_REF_BYTES
 jae .decode_ref_valid
 cmp byte [r11+rax],0
 jne .decode_ref_bad
 inc eax
 jmp .decode_ref_zero
.decode_ref_valid:
 pop rdi
 lea r9,[rdi+VS_REF]
.decode_ok:
 mov edx,r10d
 xor eax,eax
 ret
.decode_ref_bad:
 pop rdi
 jmp .decode_corrupt
.decode_usage: mov eax,VCS_ERR_USAGE
 ret
.decode_corrupt: mov eax,VCS_ERR_CORRUPT
 ret

; RDI=output96, ESI=status, RDX=head digest32 or zero, RCX=object count.
vcs_sync_response_encode:
 test rdi,rdi
 jz .response_usage
 cmp esi,VCS_ERR_UNSUPPORTED
 ja .response_usage
 push rbx
 mov rbx,rdi
 push rsi
 push rcx
 xor eax,eax
 mov ecx,VS_MESSAGE/8
 rep stosq
 pop rcx
 pop rsi
 mov rax,VS_RES_MAGIC
 mov [rbx+VS_MAGIC],rax
 mov dword [rbx+VS_VERSION_O],VS_VERSION
 mov [rbx+VS_OPERATION],esi       ; response status
 mov qword [rbx+VS_FLAGS],VS_CAP_V1
 mov [rbx+VS_COUNT],rcx
 test rdx,rdx
 jz .response_ok
 lea rdi,[rbx+VS_DIGEST]
 mov rsi,rdx
 mov ecx,32
 rep movsb
.response_ok:
 xor eax,eax
 pop rbx
 ret
.response_usage:
 mov eax,VCS_ERR_USAGE
 ret

; RDI=payload, RSI=length. RAX=codec status; EDX=remote VCS status,
; RCX=object count, R8=head digest pointer.
vcs_sync_response_decode:
 test rdi,rdi
 jz .response_decode_usage
 cmp rsi,VS_MESSAGE
 jne .response_decode_corrupt
 mov rax,VS_RES_MAGIC
 cmp [rdi+VS_MAGIC],rax
 jne .response_decode_corrupt
 cmp dword [rdi+VS_VERSION_O],VS_VERSION
 jne .response_decode_corrupt
 mov edx,[rdi+VS_OPERATION]
 cmp edx,VCS_ERR_UNSUPPORTED
 ja .response_decode_corrupt
 cmp qword [rdi+VS_FLAGS],VS_CAP_V1
 jne .response_decode_corrupt
 mov rax,[rdi+VS_REF]
 or rax,[rdi+VS_REF+8]
 or rax,[rdi+VS_REF+16]
 or rax,[rdi+VS_REF+24]
 jnz .response_decode_corrupt
 mov rcx,[rdi+VS_COUNT]
 cmp rcx,64
 ja .response_decode_corrupt
 lea r8,[rdi+VS_DIGEST]
 xor eax,eax
 ret
.response_decode_usage: mov eax,VCS_ERR_USAGE
 ret
.response_decode_corrupt: mov eax,VCS_ERR_CORRUPT
 ret

valid_ref:
 xor edx,edx
.ref_char:
 movzx eax,byte [rdi+rdx]
 test al,al
 jz .ref_end
 cmp edx,VS_REF_BYTES-1
 jae .ref_bad
 cmp al,'-'
 je .ref_good
 cmp al,'.'
 je .ref_good
 cmp al,'_'
 je .ref_good
 cmp al,'0'
 jb .ref_bad
 cmp al,'9'
 jbe .ref_good
 or al,32
 cmp al,'a'
 jb .ref_bad
 cmp al,'z'
 ja .ref_bad
.ref_good:
 inc edx
 jmp .ref_char
.ref_end:
 test edx,edx
 jz .ref_bad
 cmp byte [rdi],'.'
 je .ref_bad
 mov eax,1
 ret
.ref_bad:
 xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
