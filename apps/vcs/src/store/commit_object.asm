; Canonical scalable commit validation and immutable dependency ownership.
%include "include/vcs.inc"
%include "include/object_store.inc"
%include "include/ownership.inc"
%define VCS_COMMIT_OBJECT_IMPLEMENTATION
%include "include/commit_object.inc"
bits 64
default rel

extern vcs_object_id

section .rodata
commit_magic: db 'UVCSCOM3'

section .text
global vcs_commit_object_verify,vcs_commit_ownership_edges

; RDI=payload, RSI=length. Validates fields local to one commit object.
vcs_commit_object_verify:
 test rdi,rdi
 jz .verify_usage
 cmp rsi,VCS_COMMIT_HEADER+1
 jb .verify_corrupt
 cmp rsi,VCS_COMMIT_HEADER+VCS_COMMIT_MESSAGE_MAX
 ja .verify_corrupt
 mov rax,[commit_magic]
 cmp [rdi],rax
 jne .verify_corrupt
 mov eax,[rdi+8]
 test eax,~(VCS_COMMIT_MERGE | VCS_COMMIT_SIGNED)
 jnz .verify_corrupt
 mov ecx,[rdi+12]
 cmp ecx,2
 ja .verify_corrupt
 mov edx,[rdi+36]
 test edx,edx
 jz .verify_corrupt
 lea rax,[rdx+VCS_COMMIT_HEADER]
 cmp rax,rsi
 jne .verify_corrupt
 cmp qword [rdi+16],0
 je .verify_corrupt
 mov eax,[rdi+32]
 cmp eax,-1440
 jl .verify_corrupt
 cmp eax,1440
 jg .verify_corrupt
 mov rax,[rdi+40]
 or rax,[rdi+48]
 or rax,[rdi+56]
 or rax,[rdi+64]
 jz .verify_corrupt
 test ecx,ecx
 jz .verify_root
 cmp ecx,1
 je .verify_one_parent
 test dword [rdi+8],VCS_COMMIT_MERGE
 jz .verify_corrupt
 call commit_first_parent_nonzero
 test eax,eax
 jz .verify_corrupt
 call commit_second_parent_nonzero
 test eax,eax
 jz .verify_corrupt
 mov rax,[rdi+72]
 xor rax,[rdi+104]
 mov rdx,[rdi+80]
 xor rdx,[rdi+112]
 or rax,rdx
 mov rdx,[rdi+88]
 xor rdx,[rdi+120]
 or rax,rdx
 mov rdx,[rdi+96]
 xor rdx,[rdi+128]
 or rax,rdx
 test rax,rax
 jz .verify_corrupt
 cmp qword [rdi+16],2
 jb .verify_corrupt
 jmp .verify_reserved
.verify_one_parent:
 test dword [rdi+8],VCS_COMMIT_MERGE
 jnz .verify_corrupt
 call commit_first_parent_nonzero
 test eax,eax
 jz .verify_corrupt
 call commit_second_parent_nonzero
 test eax,eax
 jnz .verify_corrupt
 cmp qword [rdi+16],2
 jb .verify_corrupt
 jmp .verify_reserved
.verify_root:
 test dword [rdi+8],VCS_COMMIT_MERGE
 jnz .verify_corrupt
 call commit_first_parent_nonzero
 test eax,eax
 jnz .verify_corrupt
 call commit_second_parent_nonzero
 test eax,eax
 jnz .verify_corrupt
 cmp qword [rdi+16],1
 jne .verify_corrupt
.verify_reserved:
 xor eax,eax
 mov ecx,5
 lea rdx,[rdi+216]
.verify_reserved_loop:
 or rax,[rdx]
 add rdx,8
 loop .verify_reserved_loop
 test rax,rax
 jnz .verify_corrupt
 mov ecx,[rdi+36]
 lea rdx,[rdi+VCS_COMMIT_HEADER]
.verify_message_loop:
 cmp byte [rdx],0
 je .verify_corrupt
 inc rdx
 dec ecx
 jnz .verify_message_loop
 xor eax,eax
 ret
.verify_usage:
 mov eax,VCS_ERR_USAGE
 ret
.verify_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

; RDI=vcs_commit_ownership. Emits tree then parent dependency edges.
vcs_commit_ownership_edges:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,32
 test rdi,rdi
 jz .ownership_usage
 mov rbx,rdi
 mov qword [rbx+vcs_commit_ownership.result_edges],0
 mov r12,[rbx+vcs_commit_ownership.payload]
 mov r13,[rbx+vcs_commit_ownership.length]
 mov r14,[rbx+vcs_commit_ownership.commit_id]
 test r14,r14
 jz .ownership_usage
 mov rdi,r12
 mov rsi,r13
 call vcs_commit_object_verify
 test eax,eax
 jnz .ownership_done
 mov r15d,[r12+12]
 inc r15
 cmp [rbx+vcs_commit_ownership.edge_capacity],r15
 jb .ownership_space
 test r15,r15
 jz .ownership_space
 cmp qword [rbx+vcs_commit_ownership.edges],0
 je .ownership_usage
 mov edi,VCS_OBJ_COMMIT
 mov rsi,r12
 mov rdx,r13
 mov rcx,rsp
 call vcs_object_id
 test eax,eax
 jnz .ownership_done
 mov rdi,rsp
 mov rsi,r14
 call ids_equal_commit
 test eax,eax
 jz .ownership_corrupt
 mov rdi,[rbx+vcs_commit_ownership.edges]
 mov rsi,r14
 lea rdx,[r12+40]
 mov ecx,VCS_OBJ_TREE
 call emit_commit_edge
 cmp dword [r12+12],0
 je .ownership_publish
 mov rdi,[rbx+vcs_commit_ownership.edges]
 add rdi,vcs_ownership_edge_size
 mov rsi,r14
 lea rdx,[r12+72]
 mov ecx,VCS_OBJ_COMMIT
 call emit_commit_edge
 cmp dword [r12+12],1
 je .ownership_publish
 mov rdi,[rbx+vcs_commit_ownership.edges]
 add rdi,vcs_ownership_edge_size*2
 mov rsi,r14
 lea rdx,[r12+104]
 mov ecx,VCS_OBJ_COMMIT
 call emit_commit_edge
.ownership_publish:
 mov [rbx+vcs_commit_ownership.result_edges],r15
 xor eax,eax
 jmp .ownership_done
.ownership_space:
 mov eax,VCS_ERR_NO_MEM
 jmp .ownership_done
.ownership_usage:
 mov eax,VCS_ERR_USAGE
 jmp .ownership_done
.ownership_corrupt:
 mov eax,VCS_ERR_CORRUPT
.ownership_done:
 add rsp,32
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=edge, RSI=owner commit ID, RDX=child ID, ECX=child type.
emit_commit_edge:
 push rsi
 push rdx
 push rcx
 mov r8,rdi
 xor eax,eax
 mov ecx,vcs_ownership_edge_size/8
 rep stosq
 pop rcx
 pop rdx
 pop rsi
 mov dword [r8+vcs_ownership_edge.owner_kind],VCS_OWNER_IMMUTABLE
 mov [r8+vcs_ownership_edge.child_type],ecx
 mov rax,[rsi]
 mov [r8+vcs_ownership_edge.owner_key],rax
 mov rax,[rsi+8]
 mov [r8+vcs_ownership_edge.owner_key+8],rax
 mov rax,[rsi+16]
 mov [r8+vcs_ownership_edge.owner_key+16],rax
 mov rax,[rsi+24]
 mov [r8+vcs_ownership_edge.owner_key+24],rax
 mov rax,[rdx]
 mov [r8+vcs_ownership_edge.child_id],rax
 mov rax,[rdx+8]
 mov [r8+vcs_ownership_edge.child_id+8],rax
 mov rax,[rdx+16]
 mov [r8+vcs_ownership_edge.child_id+16],rax
 mov rax,[rdx+24]
 mov [r8+vcs_ownership_edge.child_id+24],rax
 ret

commit_first_parent_nonzero:
 mov rax,[rdi+72]
 or rax,[rdi+80]
 or rax,[rdi+88]
 or rax,[rdi+96]
 setnz al
 movzx eax,al
 ret

commit_second_parent_nonzero:
 mov rax,[rdi+104]
 or rax,[rdi+112]
 or rax,[rdi+120]
 or rax,[rdi+128]
 setnz al
 movzx eax,al
 ret

ids_equal_commit:
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
