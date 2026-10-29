; Git protocol v2 advertisement, ls-refs, and packfile response encoding.
%include "include/vcs.inc"
bits 64
default rel

extern bridge_pkt_encode
extern git_history_shallow,git_history_unshallow

section .bss
proto_start: resq 1
proto_cursor: resq 1
proto_left: resq 1
proto_oid_line: resb 128
proto_sideband: resb 65515

section .rodata
version: db 'version 2',10
version_len equ $-version
agent: db 'agent=tattva-vcs/1',10
agent_len equ $-agent
ls_refs_cap: db 'ls-refs=unborn',10
ls_refs_cap_len equ $-ls_refs_cap
fetch_cap: db 'fetch=wait-for-done ref-in-want sideband-all filter shallow',10
fetch_cap_len equ $-fetch_cap
object_format: db 'object-format=sha256',10
object_format_len equ $-object_format
server_option_cap: db 'server-option',10
server_option_cap_len equ $-server_option_cap
ref_suffix: db ' refs/heads/main',10
ref_suffix_len equ $-ref_suffix
head_suffix: db ' HEAD',10
head_suffix_len equ $-head_suffix
head_symref_suffix: db ' HEAD symref-target:refs/heads/main',10
head_symref_suffix_len equ $-head_symref_suffix
packfile: db 'packfile',10
packfile_len equ $-packfile
wanted_refs: db 'wanted-refs',10
wanted_refs_len equ $-wanted_refs
shallow_info: db 'shallow-info',10
shallow_info_len equ $-shallow_info
acknowledgments: db 'acknowledgments',10
acknowledgments_len equ $-acknowledgments
ack_prefix: db 'ACK '
ack_prefix_len equ $-ack_prefix
nak_line: db 'NAK',10
nak_line_len equ $-nak_line
ready_line: db 'ready',10
ready_line_len equ $-ready_line
shallow_prefix: db 'shallow '
shallow_prefix_len equ $-shallow_prefix
unshallow_prefix: db 'unshallow '
unshallow_prefix_len equ $-unshallow_prefix
flush: db '0000'
delim: db '0001'
hex: db '0123456789abcdef'

section .text
global git_protocol_v2_advertise,git_protocol_v2_ls_refs,git_protocol_v2_fetch
global git_protocol_v2_acknowledge

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
 lea rdi,[server_option_cap]
 mov esi,server_option_cap_len
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

; RDI=32-byte commit OID, RSI=flags, RDX=output, RCX=capacity.
; Flags: bit 0 symrefs, bit 1 HEAD, bit 2 main, bit 3 prefix filter active.
git_protocol_v2_ls_refs:
 push rbx
 push r12
 push r13
 test rdi,rdi
 jz .usage
 mov r12,rdi
 mov r13,rsi
 mov rdi,rdx
 mov rsi,rcx
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
 test r13b,8
 jz .emit_head
 test r13b,2
 jz .maybe_main
.emit_head:
 test r13b,1
 jz .plain_head
 lea rsi,[head_symref_suffix]
 mov ecx,head_symref_suffix_len
 mov ebx,head_symref_suffix_len
 jmp .append_head
.plain_head:
 lea rsi,[head_suffix]
 mov ecx,head_suffix_len
 mov ebx,head_suffix_len
.append_head:
 rep movsb
 lea rdi,[proto_oid_line]
 lea rsi,[rbx+64]
 call proto_packet
 test eax,eax
 jnz .done
.maybe_main:
 test r13b,8
 jz .emit_main
 test r13b,4
 jz .flush_refs
.emit_main:
 lea rdi,[proto_oid_line+64]
 lea rsi,[ref_suffix]
 mov ecx,ref_suffix_len
 rep movsb
 lea rdi,[proto_oid_line]
 mov esi,64+ref_suffix_len
 call proto_packet
 test eax,eax
 jnz .done
.flush_refs:
 call proto_flush
 test eax,eax
 jnz .done
 call proto_finish
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
.done:
 pop r13
 pop r12
 pop rbx
 ret

; RDI=pack, RSI=length, RDX=output, RCX=capacity, R8=flags, R9=tip OID.
; Bit 4 emits wanted refs, bit 5 side-bands every response record, bit 11
; selects HEAD, and bit 12 selects refs/heads/main.
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
 mov r15,r8
 mov rbp,r9
 mov rdi,rdx
 mov rsi,rcx
 call proto_begin
 test eax,eax
 jnz .done
 test r15,8192
 jz .fetch_shallow
 lea rdi,[acknowledgments]
 mov esi,acknowledgments_len
 call fetch_packet
 test eax,eax
 jnz .done
 lea rdi,[ready_line]
 mov esi,ready_line_len
 call fetch_packet
 test eax,eax
 jnz .done
 call proto_delim
 test eax,eax
 jnz .done
.fetch_shallow:
 test r15,256
 jz .wanted_section
 call git_history_shallow
 mov rbx,rax
 call git_history_unshallow
 mov r14,rax
 test rbx,rbx
 jnz .shallow_section
 test r14,r14
 jz .wanted_section
.shallow_section:
 lea rdi,[shallow_info]
 mov esi,shallow_info_len
 call fetch_packet
 test eax,eax
 jnz .done
 test r14,r14
 jz .emit_new_shallow
 lea rdi,[unshallow_prefix]
 mov esi,unshallow_prefix_len
 mov rdx,r14
 call fetch_boundary
 test eax,eax
 jnz .done
.emit_new_shallow:
 test rbx,rbx
 jz .finish_shallow_section
 lea rdi,[shallow_prefix]
 mov esi,shallow_prefix_len
 mov rdx,rbx
 call fetch_boundary
 test eax,eax
 jnz .done
.finish_shallow_section:
 call proto_delim
 test eax,eax
 jnz .done
.wanted_section:
 test r15b,16
 jz .packfile_section
 test rbp,rbp
 jz .usage
 lea rdi,[wanted_refs]
 mov esi,wanted_refs_len
 call fetch_packet
 test eax,eax
 jnz .done
 lea rdi,[proto_oid_line]
 lea r8,[hex]
 mov rsi,rbp
 mov ecx,32
.wanted_oid:
 movzx eax,byte [rsi]
 inc rsi
 mov edx,eax
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+1],al
 add rdi,2
 loop .wanted_oid
 test r15,2048
 jz .wanted_main
 lea rsi,[head_suffix]
 mov ecx,head_suffix_len
 mov ebx,head_suffix_len
 rep movsb
 lea rdi,[proto_oid_line]
 lea rsi,[rbx+64]
 call fetch_packet
 test eax,eax
 jnz .done
.wanted_main:
 test r15,4096
 jz .wanted_done
 lea rdi,[proto_oid_line+64]
 lea rsi,[ref_suffix]
 mov ecx,ref_suffix_len
 rep movsb
 lea rdi,[proto_oid_line]
 mov esi,64+ref_suffix_len
 call fetch_packet
 test eax,eax
 jnz .done
.wanted_done:
 call proto_delim
 test eax,eax
 jnz .done
.packfile_section:
 lea rdi,[packfile]
 mov esi,packfile_len
 call fetch_packet
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

; Negotiation-only response. RDI=packed common OIDs, RSI=count,
; RDX=output, RCX=capacity, R8=fetch flags. No ready or pack is emitted.
git_protocol_v2_acknowledge:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 mov r12,rsi
 mov r15,r8
 mov rdi,rdx
 mov rsi,rcx
 call proto_begin
 test eax,eax
 jnz .ack_done
 lea rdi,[acknowledgments]
 mov esi,acknowledgments_len
 call fetch_packet
 test eax,eax
 jnz .ack_done
 test r12,r12
 jz .ack_nak
.ack_common:
 lea rdi,[proto_oid_line]
 lea rsi,[ack_prefix]
 mov ecx,ack_prefix_len
 rep movsb
 lea r8,[hex]
 mov rsi,rbx
 mov ecx,32
.ack_oid:
 movzx eax,byte [rsi]
 inc rsi
 mov edx,eax
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+1],al
 add rdi,2
 loop .ack_oid
 mov byte [rdi],10
 lea rdi,[proto_oid_line]
 mov esi,ack_prefix_len+64+1
 call fetch_packet
 test eax,eax
 jnz .ack_done
 add rbx,32
 dec r12
 jnz .ack_common
 jmp .ack_record_done
.ack_nak:
 lea rdi,[nak_line]
 mov esi,nak_line_len
 call fetch_packet
.ack_record_done:
 test eax,eax
 jnz .ack_done
 call proto_flush
 test eax,eax
 jnz .ack_done
 call proto_finish
.ack_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=record prefix, RSI=prefix length, RDX=32-byte OID.
fetch_boundary:
 push rbx
 push r12
 push r13
 push r14
 mov r12,rdi
 mov r13,rsi
 mov rbx,rdx
 lea rdi,[proto_oid_line]
 mov rsi,r12
 mov rcx,r13
 rep movsb
 lea r8,[hex]
 mov rsi,rbx
 mov ecx,32
.boundary_oid:
 movzx eax,byte [rsi]
 inc rsi
 mov edx,eax
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+1],al
 add rdi,2
 loop .boundary_oid
 mov byte [rdi],10
 lea rdi,[proto_oid_line]
 lea rsi,[r13+64+1]
 call fetch_packet
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; Apply protocol-v2 sideband-all channel 1 to a non-special fetch record.
; RDI=payload, RSI=length. R15 carries fetch flags.
fetch_packet:
 test r15b,32
 jz proto_packet
 mov r14,rsi
 mov rsi,rdi
 lea rdi,[proto_sideband+1]
 mov rcx,r14
 rep movsb
 mov byte [proto_sideband],1
 lea rdi,[proto_sideband]
 lea rsi,[r14+1]
 jmp proto_packet

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

proto_delim:
 cmp qword [proto_left],4
 jb .space
 mov rdi,[proto_cursor]
 mov eax,[delim]
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
