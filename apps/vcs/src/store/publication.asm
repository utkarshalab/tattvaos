; Recoverable object/ownership/root publication state machine.
%include "include/vcs.inc"
%include "include/object_store.inc"
%include "include/ownership.inc"
%define VCS_PUBLICATION_IMPLEMENTATION
%include "include/publication.inc"
bits 64
default rel

extern vcs_object_id,vcs_ownership_edge_validate

section .text
global vcs_publication_commit

; RDI=vcs_publication. The backend owns durable allocation and root switching.
vcs_publication_commit:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,72
 test rdi,rdi
 jz .usage
 mov rbx,rdi
 mov rbp,[rbx+vcs_publication.backend]
 test rbp,rbp
 jz .usage
 mov rax,[rbx+vcs_publication.root]
 test rax,rax
 jz .usage
 cmp qword [rbx+vcs_publication.root_length],0
 je .corrupt
 mov rdx,[rbx+vcs_publication.root_length]
 add rax,rdx
 jc .space
 cmp qword [rbx+vcs_publication.tx_sequence],0
 je .corrupt
 cmp qword [rbx+vcs_publication.generation],0
 je .corrupt
 cmp qword [rbp+vcs_publish_backend.begin],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.put_object],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.put_edge],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.stage_root],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.flush],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.publish],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.abort],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.poison],0
 je .usage
 mov r12,[rbx+vcs_publication.object_count]
 test r12,r12
 jz .objects_pointer_ok
 cmp qword [rbx+vcs_publication.objects],0
 je .usage
 mov rax,r12
 mov ecx,vcs_publish_object_size
 mul rcx
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_publication.objects]
 jc .space
.objects_pointer_ok:
 mov r13,[rbx+vcs_publication.edge_count]
 test r13,r13
 jz .edges_pointer_ok
 cmp qword [rbx+vcs_publication.edges],0
 je .usage
 mov rax,r13
 mov ecx,vcs_ownership_edge_size
 mul rcx
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_publication.edges]
 jc .space
.edges_pointer_ok:
 mov qword [rsp+32],0
.validate_objects:
 mov r14,[rsp+32]
 cmp r14,r12
 jae .validate_edges_begin
 mov rax,r14
 imul rax,vcs_publish_object_size
 add rax,[rbx+vcs_publication.objects]
 mov [rsp+40],rax
 mov r15d,[rax+vcs_publish_object.type]
 test r15d,r15d
 jz .corrupt
 cmp r15d,10
 ja .corrupt
 cmp dword [rax+vcs_publish_object.flags],0
 jne .corrupt
 mov rcx,[rax+vcs_publish_object.length]
 test rcx,rcx
 jz .object_payload_ok
 cmp qword [rax+vcs_publish_object.payload],0
 je .usage
 mov rdx,[rax+vcs_publish_object.payload]
 add rdx,rcx
 jc .space
.object_payload_ok:
 mov edi,r15d
 mov rsi,[rax+vcs_publish_object.payload]
 mov rdx,rcx
 lea rcx,[rsp]
 call vcs_object_id
 test eax,eax
 jnz .done
 mov rax,[rsp+40]
 lea rdi,[rsp]
 lea rsi,[rax+vcs_publish_object.id]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 inc qword [rsp+32]
 jmp .validate_objects
.validate_edges_begin:
 mov qword [rsp+32],0
.validate_edges:
 mov r14,[rsp+32]
 cmp r14,r13
 jae .begin
 mov rax,r14
 imul rax,vcs_ownership_edge_size
 mov rdi,[rbx+vcs_publication.edges]
 add rdi,rax
 call vcs_ownership_edge_validate
 test eax,eax
 jnz .done
 inc qword [rsp+32]
 jmp .validate_edges
.begin:
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_NONE
 mov rdi,[rbp+vcs_publish_backend.context]
 mov rsi,[rbx+vcs_publication.tx_sequence]
 mov rdx,r12
 mov rcx,r13
 call [rbp+vcs_publish_backend.begin]
 test eax,eax
 jnz .callback_done
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_BEGUN
 mov qword [rsp+32],0
.put_objects:
 mov r14,[rsp+32]
 cmp r14,r12
 jae .objects_done
 mov rax,r14
 imul rax,vcs_publish_object_size
 mov rsi,[rbx+vcs_publication.objects]
 add rsi,rax
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.put_object]
 test eax,eax
 jnz .abort_with_status
 inc qword [rsp+32]
 jmp .put_objects
.objects_done:
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_OBJECTS
 mov qword [rsp+32],0
.put_edges:
 mov r14,[rsp+32]
 cmp r14,r13
 jae .edges_done
 mov rax,r14
 imul rax,vcs_ownership_edge_size
 mov rsi,[rbx+vcs_publication.edges]
 add rsi,rax
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.put_edge]
 test eax,eax
 jnz .abort_with_status
 inc qword [rsp+32]
 jmp .put_edges
.edges_done:
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_OWNERSHIP
 mov rdi,[rbp+vcs_publish_backend.context]
 mov rsi,[rbx+vcs_publication.root]
 mov rdx,[rbx+vcs_publication.root_length]
 mov rcx,[rbx+vcs_publication.generation]
 call [rbp+vcs_publish_backend.stage_root]
 test eax,eax
 jnz .abort_with_status
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_ROOT
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.flush]
 test eax,eax
 jnz .abort_with_status
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_FLUSHED
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.publish]
 test eax,eax
 jnz .publish_ambiguous
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_COMMITTED
 xor eax,eax
 jmp .done
.abort_with_status:
 mov [rsp+48],rax
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.abort]
 test eax,eax
 jnz .abort_failed
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_ABORTED
 mov rax,[rsp+48]
 jmp .callback_done
.abort_failed:
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.poison]
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_POISONED
 mov eax,VCS_ERR_IO
 jmp .done
.publish_ambiguous:
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.poison]
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_POISONED
 mov eax,VCS_ERR_IO
 jmp .done
.callback_done:
 cmp eax,VCS_ERR_UNSUPPORTED
 jbe .done
 mov eax,VCS_ERR_IO
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,72
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

ids_equal_publication:
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
