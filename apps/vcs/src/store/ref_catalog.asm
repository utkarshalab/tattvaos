; Canonical scalable ref records and authenticated mutable generations.
%include "include/vcs.inc"
%define VCS_REF_CATALOG_IMPLEMENTATION
%include "include/ref_catalog.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

extern sha256_init,sha256_update,sha256_final

section .rodata
ref_root_frame:
 db 'UVCSROT1'
 dw 1,1
 dd 0
ref_root_frame_size equ $-ref_root_frame

section .text
global vcs_ref_catalog_validate,vcs_ref_root_hash,vcs_ref_root_verify

; RDI=canonical variable records, RSI=total bytes. RAX=VCS status.
vcs_ref_catalog_validate:
 push rbx
 push r12
 push r13
 push r14
 push r15
 test rsi,rsi
 jz .catalog_ok
 test rdi,rdi
 jz .catalog_usage
 mov rbx,rdi
 lea r12,[rdi+rsi]
 jc .catalog_corrupt
 xor r13d,r13d
.catalog_loop:
 cmp rbx,r12
 jae .catalog_end
 mov rax,r12
 sub rax,rbx
 cmp rax,VCS_REF_HEADER
 jb .catalog_corrupt
 movzx r14d,byte [rbx+1]
 test r14d,r14d
 jz .catalog_corrupt
 cmp r14d,VCS_REF_NAME_MAX
 ja .catalog_corrupt
 lea r15,[r14+7]
 and r15,-8
 add r15,VCS_REF_HEADER
 jc .catalog_corrupt
 lea rax,[rbx+r15]
 jc .catalog_corrupt
 cmp rax,r12
 ja .catalog_corrupt
 movzx eax,byte [rbx]
 test eax,eax
 jz .catalog_corrupt
 cmp eax,VCS_REF_WORKSPACE
 ja .catalog_corrupt
 movzx eax,word [rbx+2]
 test eax,~(VCS_REF_PROTECTED | VCS_REF_SYMBOLIC)
 jnz .catalog_corrupt
 cmp dword [rbx+4],0
 jne .catalog_corrupt
 cmp qword [rbx+8],0
 je .catalog_corrupt
 mov rax,[rbx+16]
 or rax,[rbx+24]
 or rax,[rbx+32]
 or rax,[rbx+40]
 jz .catalog_corrupt
 mov rdi,rbx
 call ref_name_validate
 test eax,eax
 jz .catalog_corrupt
 test r13,r13
 jz .catalog_padding
 mov rdi,r13
 mov rsi,rbx
 call ref_compare
 cmp eax,-1
 jne .catalog_corrupt
.catalog_padding:
 lea rdi,[rbx+VCS_REF_HEADER+r14]
 mov rcx,r15
 sub rcx,VCS_REF_HEADER
 sub rcx,r14
 xor eax,eax
.padding_loop:
 test rcx,rcx
 jz .catalog_next
 cmp byte [rdi],al
 jne .catalog_corrupt
 inc rdi
 dec rcx
 jmp .padding_loop
.catalog_next:
 mov r13,rbx
 add rbx,r15
 jmp .catalog_loop
.catalog_end:
 cmp rbx,r12
 jne .catalog_corrupt
.catalog_ok:
 xor eax,eax
 jmp .catalog_done
.catalog_usage:
 mov eax,VCS_ERR_USAGE
 jmp .catalog_done
.catalog_corrupt:
 mov eax,VCS_ERR_CORRUPT
.catalog_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=vcs_ref_root. Hashes one validated canonical generation.
vcs_ref_root_hash:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,120
 test rdi,rdi
 jz .root_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_ref_root.records]
 mov r13,[rbx+vcs_ref_root.record_bytes]
 mov r14,[rbx+vcs_ref_root.root_hash]
 test r14,r14
 jz .root_usage
 cmp qword [rbx+vcs_ref_root.generation],0
 je .root_corrupt
 mov rdi,r12
 mov rsi,r13
 call vcs_ref_catalog_validate
 test eax,eax
 jnz .root_done
 mov [rsp+112],r13
 mov rdi,rsp
 call sha256_init
 mov rdi,rsp
 lea rsi,[ref_root_frame]
 mov edx,ref_root_frame_size
 call sha256_update
 mov rdi,rsp
 lea rsi,[rbx+vcs_ref_root.generation]
 mov edx,8
 call sha256_update
 mov rdi,rsp
 lea rsi,[rsp+112]
 mov edx,8
 call sha256_update
 test r13,r13
 jz .root_records_done
 mov rdi,rsp
 mov rsi,r12
 mov rdx,r13
 call sha256_update
.root_records_done:
 mov rdi,rsp
 mov rsi,r14
 call sha256_final
 xor eax,eax
 jmp .root_done
.root_usage:
 mov eax,VCS_ERR_USAGE
 jmp .root_done
.root_corrupt:
 mov eax,VCS_ERR_CORRUPT
.root_done:
 add rsp,120
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=vcs_ref_root. Recomputes and constant-time compares root_hash.
vcs_ref_root_verify:
 push rbx
 sub rsp,64
 test rdi,rdi
 jz .verify_usage
 mov rbx,rdi
 cmp qword [rbx+vcs_ref_root.root_hash],0
 je .verify_usage
 mov rax,[rbx+vcs_ref_root.records]
 mov [rsp+vcs_ref_root.records],rax
 mov rax,[rbx+vcs_ref_root.record_bytes]
 mov [rsp+vcs_ref_root.record_bytes],rax
 mov rax,[rbx+vcs_ref_root.generation]
 mov [rsp+vcs_ref_root.generation],rax
 lea rax,[rsp+32]
 mov [rsp+vcs_ref_root.root_hash],rax
 mov rdi,rsp
 call vcs_ref_root_hash
 test eax,eax
 jnz .verify_done
 lea rdi,[rsp+32]
 mov rsi,[rbx+vcs_ref_root.root_hash]
 call ids_equal_ref
 test eax,eax
 jz .verify_corrupt
 xor eax,eax
 jmp .verify_done
.verify_usage:
 mov eax,VCS_ERR_USAGE
 jmp .verify_done
.verify_corrupt:
 mov eax,VCS_ERR_CORRUPT
.verify_done:
 add rsp,64
 pop rbx
 ret

; RDI=record. EAX=1 valid, 0 invalid.
ref_name_validate:
 movzx ecx,byte [rdi+1]
 lea rsi,[rdi+VCS_REF_HEADER]
 cmp byte [rsi],'.'
 je .name_bad
 cmp byte [rsi],'/'
 je .name_bad
 xor edx,edx
.name_loop:
 cmp rdx,rcx
 jae .name_ok
 mov al,[rsi+rdx]
 cmp al,'/'
 je .name_slash
 cmp al,'-'
 je .name_next
 cmp al,'.'
 je .name_dot
 cmp al,'_'
 je .name_next
 cmp al,'0'
 jb .name_bad
 cmp al,'9'
 jbe .name_next
 cmp al,'A'
 jb .name_bad
 cmp al,'Z'
 jbe .name_next
 cmp al,'a'
 jb .name_bad
 cmp al,'z'
 ja .name_bad
.name_next:
 inc rdx
 jmp .name_loop
.name_dot:
 mov r8,rcx
 sub r8,rdx
 cmp r8,4
 jb .name_next
 cmp dword [rsi+rdx],0x7363762e ; ASCII '.vcs'
 je .name_bad
 jmp .name_next
.name_slash:
 test rdx,rdx
 jz .name_bad
 lea rax,[rdx+1]
 cmp rax,rcx
 jae .name_bad
 cmp byte [rsi+rax],'.'
 je .name_bad
 cmp byte [rsi+rax],'/'
 je .name_bad
 inc rdx
 jmp .name_loop
.name_ok:
 mov eax,1
 ret
.name_bad:
 xor eax,eax
 ret

; RDI=left record, RSI=right record. EAX=-1,0,1 by kind then name.
ref_compare:
 movzx eax,byte [rdi]
 cmp al,[rsi]
 jb .compare_less
 ja .compare_greater
 movzx r8d,byte [rdi+1]
 movzx r9d,byte [rsi+1]
 lea r10,[rdi+VCS_REF_HEADER]
 lea r11,[rsi+VCS_REF_HEADER]
 xor ecx,ecx
.compare_loop:
 cmp rcx,r8
 jae .left_end
 cmp rcx,r9
 jae .compare_greater
 mov al,[r10+rcx]
 cmp al,[r11+rcx]
 jb .compare_less
 ja .compare_greater
 inc rcx
 jmp .compare_loop
.left_end:
 cmp r8,r9
 jb .compare_less
 ja .compare_greater
 xor eax,eax
 ret
.compare_less:
 mov eax,-1
 ret
.compare_greater:
 mov eax,1
 ret

ids_equal_ref:
 mov rax,[rdi]
 xor rax,[rsi]
 mov rcx,[rdi+8]
 xor rcx,[rsi+8]
 or rax,rcx
 mov rcx,[rdi+16]
 xor rcx,[rsi+16]
 or rax,rcx
 mov rcx,[rdi+24]
 xor rcx,[rsi+24]
 or rax,rcx
 setz al
 movzx eax,al
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
