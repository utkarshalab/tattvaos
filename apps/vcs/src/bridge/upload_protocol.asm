; Git protocol v2 advertisement, ls-refs, and packfile response encoding.
%include "include/vcs.inc"
bits 64
default rel

extern bridge_pkt_encode

section .bss
proto_start: resq 1
proto_cursor: resq 1
proto_left: resq 1
proto_oid_line: resb 96
proto_sideband: resb 65515

section .rodata
version: db 'version 2',10
version_len equ $-version
agent: db 'agent=tattva-vcs/1',10
agent_len equ $-agent
ls_refs_cap: db 'ls-refs=unborn',10
ls_refs_cap_len equ $-ls_refs_cap
fetch_cap: db 'fetch',10
fetch_cap_len equ $-fetch_cap
object_format: db 'object-format=sha256',10
object_format_len equ $-object_format
ref_suffix: db ' refs/heads/main',10
ref_suffix_len equ $-ref_suffix
packfile: db 'packfile',10
packfile_len equ $-packfile
flush: db '0000'
hex: db '0123456789abcdef'

section .text
global git_protocol_v2_advertise,git_protocol_v2_ls_refs,git_protocol_v2_fetch

; RDI=output, RSI=capacity -> RAX=status, RDX=length.
git_protocol_v2_advertise:
 push rbx
 call proto_begin
 test eax,eax
 jnz .done
 lea rdi,[version]
 mov esi,version_len
 call proto_packet
 test eax,eax
 jnz .done
 lea rdi,[agent]
 mov esi,agent_len
 call proto_packet
 test eax,eax
 jnz .done
 lea rdi,[ls_refs_cap]
 mov esi,ls_refs_cap_len
 call proto_packet
 test eax,eax
 jnz .done
 lea rdi,[fetch_cap]
 mov esi,fetch_cap_len
 call proto_packet
 test eax,eax
 jnz .done
 lea rdi,[object_format]
 mov esi,object_format_len
 call proto_packet
 test eax,eax
 jnz .done
 call proto_flush
 test eax,eax
 jnz .done
 call proto_finish
.done:
 pop rbx
 ret

; RDI=32-byte commit OID, RSI=output, RDX=capacity.
git_protocol_v2_ls_refs:
 push rbx
 push r12
 sub rsp,8
 test rdi,rdi
 jz .usage
 mov r12,rdi
 mov rdi,rsi
 mov rsi,rdx
 call proto_begin
 test eax,eax
 jnz .done
 lea rdi,[proto_oid_line]
 lea r8,[hex]
 mov ecx,32
.oid:
 movzx eax,byte [r12]
 inc r12
 mov edx,eax
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+1],al
 add rdi,2
 loop .oid
 lea rsi,[ref_suffix]
 mov ecx,ref_suffix_len
 rep movsb
 lea rdi,[proto_oid_line]
 mov esi,64+ref_suffix_len
 call proto_packet
 test eax,eax
 jnz .done
 call proto_flush
 test eax,eax
 jnz .done
 call proto_finish
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
.done:
 add rsp,8
 pop r12
 pop rbx
 ret

; RDI=pack, RSI=pack length, RDX=output, RCX=capacity.
git_protocol_v2_fetch:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .usage
 mov r12,rdi
 mov r13,rsi
 mov rdi,rdx
 mov rsi,rcx
 call proto_begin
 test eax,eax
 jnz .done
 lea rdi,[packfile]
 mov esi,packfile_len
 call proto_packet
 test eax,eax
 jnz .done
.chunk:
 test r13,r13
 jz .fetch_flush
 mov r14,r13
 cmp r14,65514
 jbe .chunk_size
 mov r14,65514
.chunk_size:
 mov byte [proto_sideband],1
 lea rdi,[proto_sideband+1]
 mov rsi,r12
 mov rcx,r14
 rep movsb
 lea rdi,[proto_sideband]
 lea rsi,[r14+1]
 call proto_packet
 test eax,eax
 jnz .done
 add r12,r14
 sub r13,r14
 jmp .chunk
.fetch_flush:
 call proto_flush
 test eax,eax
 jnz .done
 call proto_finish
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

proto_begin:
 test rdi,rdi
 jz .bad
 mov [proto_start],rdi
 mov [proto_cursor],rdi
 mov [proto_left],rsi
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_USAGE
 ret

proto_packet:
 sub rsp,8
 mov rdx,[proto_cursor]
 mov rcx,[proto_left]
 call bridge_pkt_encode
 test eax,eax
 jnz .done
 add [proto_cursor],rdx
 sub [proto_left],rdx
.done:
 add rsp,8
 ret

proto_flush:
 cmp qword [proto_left],4
 jb .space
 mov rdi,[proto_cursor]
 mov eax,[flush]
 mov [rdi],eax
 add qword [proto_cursor],4
 sub qword [proto_left],4
 xor eax,eax
 ret
.space: mov eax,VCS_ERR_NO_MEM
 ret

proto_finish:
 mov rdx,[proto_cursor]
 sub rdx,[proto_start]
 xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
