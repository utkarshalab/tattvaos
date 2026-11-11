; Explicit ownership accounting for scalable immutable file objects.
%include "include/vcs.inc"
%include "include/chunk_pipeline.inc"
%include "include/file_object.inc"
%define VCS_OWNERSHIP_IMPLEMENTATION
%include "include/ownership.inc"
bits 64
default rel

extern vcs_file_object_verify

section .text
global vcs_ownership_edge_validate,vcs_ownership_catalog_validate
global vcs_file_ownership_edges,vcs_ownership_reclaimable

; RDI=one 80-byte edge. RAX=VCS status.
vcs_ownership_edge_validate:
 test rdi,rdi
 jz .edge_usage
 mov eax,[rdi+vcs_ownership_edge.owner_kind]
 test eax,eax
 jz .edge_corrupt
 cmp eax,VCS_OWNER_MIGRATION
 ja .edge_corrupt
 mov eax,[rdi+vcs_ownership_edge.child_type]
 test eax,eax
 jz .edge_corrupt
 cmp eax,10
 ja .edge_corrupt
 cmp qword [rdi+vcs_ownership_edge.flags],0
 jne .edge_corrupt
 mov rax,[rdi+vcs_ownership_edge.owner_key]
 or rax,[rdi+vcs_ownership_edge.owner_key+8]
 or rax,[rdi+vcs_ownership_edge.owner_key+16]
 or rax,[rdi+vcs_ownership_edge.owner_key+24]
 jz .edge_corrupt
 mov rax,[rdi+vcs_ownership_edge.child_id]
 or rax,[rdi+vcs_ownership_edge.child_id+8]
 or rax,[rdi+vcs_ownership_edge.child_id+16]
 or rax,[rdi+vcs_ownership_edge.child_id+24]
 jz .edge_corrupt
 xor eax,eax
 ret
.edge_usage:
 mov eax,VCS_ERR_USAGE
 ret
.edge_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

; RDI=records, RSI=count. Requires strict child/kind/owner canonical order.
vcs_ownership_catalog_validate:
 test rsi,rsi
 jz .catalog_ok
 test rdi,rdi
 jz .catalog_usage
 mov rax,rsi
 mov ecx,vcs_ownership_edge_size
 mul rcx
 test rdx,rdx
 jnz .catalog_corrupt
 add rax,rdi
 jc .catalog_corrupt
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 xor r13d,r13d
.catalog_loop:
 cmp r13,r12
 jae .catalog_valid
 mov rax,r13
 imul rax,vcs_ownership_edge_size
 lea rdi,[rbx+rax]
 call vcs_ownership_edge_validate
 test eax,eax
 jnz .catalog_pop
 test r13,r13
 jz .catalog_next
 mov rax,r13
 dec rax
 imul rax,vcs_ownership_edge_size
 lea rdi,[rbx+rax]
 mov rax,r13
 imul rax,vcs_ownership_edge_size
 lea rsi,[rbx+rax]
 call edge_compare
 cmp eax,-1
 jne .catalog_bad_pop
.catalog_next:
 inc r13
 jmp .catalog_loop
.catalog_valid:
 xor eax,eax
 jmp .catalog_pop
.catalog_bad_pop:
 mov eax,VCS_ERR_CORRUPT
.catalog_pop:
 pop r13
 pop r12
 pop rbx
 ret
.catalog_ok:
 xor eax,eax
 ret
.catalog_usage:
 mov eax,VCS_ERR_USAGE
 ret
.catalog_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

; RDI=vcs_file_ownership. Emits an unsorted insertion batch; the catalog B-tree
; owns canonical ordering. Repeated chunk references in one page emit one edge.
vcs_file_ownership_edges:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,40
 test rdi,rdi
 jz .file_usage
 mov rbx,rdi
 mov rbp,[rbx+vcs_file_ownership.file]
 test rbp,rbp
 jz .file_usage
 mov rdi,rbp
 call vcs_file_object_verify
 test eax,eax
 jnz .file_done
 mov r12,[rbp+vcs_file_read.pages]
 mov r13,[rbp+vcs_file_read.page_count]
 mov r14,[rbp+vcs_file_read.chunk_count]
 mov r15,[rbx+vcs_file_ownership.edges]
 mov qword [rsp],0                  ; output edge count
 mov rax,r13
 add rax,r14
 jc .file_space
 cmp [rbx+vcs_file_ownership.edge_capacity],rax
 jb .file_space
 test rax,rax
 jz .file_success
 test r15,r15
 jz .file_usage
 mov rdx,rax
 mov ecx,vcs_ownership_edge_size
 mov rax,rdx
 mul rcx
 test rdx,rdx
 jnz .file_space
 add rax,r15
 jc .file_space
 mov qword [rsp+8],0                ; page index
 mov qword [rsp+16],0               ; global chunk index
.file_page_loop:
 mov r8,[rsp+8]
 cmp r8,r13
 jae .file_edges_done
 mov rax,r8
 imul rax,vcs_chunk_record_size
 lea r9,[r12+rax]                   ; current page record
 mov rax,[rsp]
 imul rax,vcs_ownership_edge_size
 lea r10,[r15+rax]
 mov rdi,r10
 xor eax,eax
 mov ecx,vcs_ownership_edge_size
 rep stosb
 mov dword [r10+vcs_ownership_edge.owner_kind],VCS_OWNER_IMMUTABLE
 mov dword [r10+vcs_ownership_edge.child_type],9
 test r8,r8
 jnz .file_page_previous
 mov rsi,[rbp+vcs_file_read.root_id]
 jmp .file_page_owner
.file_page_previous:
 mov rax,r8
 dec rax
 imul rax,vcs_chunk_record_size
 lea rsi,[r12+rax+vcs_chunk_record.id]
.file_page_owner:
 lea rdi,[r10+vcs_ownership_edge.owner_key]
 mov ecx,32
 rep movsb
 lea rdi,[r10+vcs_ownership_edge.child_id]
 lea rsi,[r9+vcs_chunk_record.id]
 mov ecx,32
 rep movsb
 inc qword [rsp]
 mov r11,[r9+vcs_chunk_record.data]
 mov eax,[r11+12]
 mov [rsp+24],rax                   ; entries in current page
 mov qword [rsp+32],0
.file_chunk_loop:
 mov r8,[rsp+32]
 cmp r8,[rsp+24]
 jae .file_page_done
 mov rax,r8
 imul rax,VCS_FILE_PAGE_ENTRY
 lea rdx,[r11+VCS_FILE_PAGE_HEADER+rax]
 xor ecx,ecx
.file_chunk_duplicate:
 cmp rcx,r8
 jae .file_chunk_emit
 mov rax,rcx
 imul rax,VCS_FILE_PAGE_ENTRY
 lea rsi,[r11+VCS_FILE_PAGE_HEADER+rax]
 mov rdi,rdx
 mov r10,rcx
 call ids_equal_owner
 mov rcx,r10
 test eax,eax
 jnz .file_chunk_skip
 inc rcx
 jmp .file_chunk_duplicate
.file_chunk_emit:
 mov rax,[rsp]
 imul rax,vcs_ownership_edge_size
 lea r10,[r15+rax]
 mov rdi,r10
 xor eax,eax
 mov ecx,vcs_ownership_edge_size
 rep stosb
 mov dword [r10+vcs_ownership_edge.owner_kind],VCS_OWNER_IMMUTABLE
 mov dword [r10+vcs_ownership_edge.child_type],VCS_OBJ_CHUNK
 lea rdi,[r10+vcs_ownership_edge.owner_key]
 lea rsi,[r9+vcs_chunk_record.id]
 mov ecx,32
 rep movsb
 lea rdi,[r10+vcs_ownership_edge.child_id]
 mov rsi,rdx
 mov ecx,32
 rep movsb
 inc qword [rsp]
.file_chunk_skip:
 inc qword [rsp+16]
 inc qword [rsp+32]
 jmp .file_chunk_loop
.file_page_done:
 inc qword [rsp+8]
 jmp .file_page_loop
.file_edges_done:
 mov rax,[rsp+16]
 cmp rax,r14
 jne .file_corrupt
.file_success:
 mov rax,[rsp]
 mov [rbx+vcs_file_ownership.result_edges],rax
 xor eax,eax
 jmp .file_done
.file_space:
 mov eax,VCS_ERR_NO_MEM
 jmp .file_done
.file_usage:
 mov eax,VCS_ERR_USAGE
 jmp .file_done
.file_corrupt:
 mov eax,VCS_ERR_CORRUPT
.file_done:
 add rsp,40
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=vcs_reclaim_check. Success proves no durable inbound edge and no active
; target reader. Transaction/migration pins are ordinary catalog edges.
vcs_ownership_reclaimable:
 push rbx
 push r12
 push r13
 test rdi,rdi
 jz .reclaim_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_reclaim_check.object_id]
 test r12,r12
 jz .reclaim_usage
 mov rdi,[rbx+vcs_reclaim_check.catalog]
 mov rsi,[rbx+vcs_reclaim_check.catalog_count]
 call vcs_ownership_catalog_validate
 test eax,eax
 jnz .reclaim_done
 cmp qword [rbx+vcs_reclaim_check.active_readers],0
 jne .reclaim_owned
 mov r13,[rbx+vcs_reclaim_check.catalog_count]
 xor ecx,ecx
.reclaim_loop:
 cmp rcx,r13
 jae .reclaim_ok
 mov rax,rcx
 imul rax,vcs_ownership_edge_size
 add rax,[rbx+vcs_reclaim_check.catalog]
 lea rdi,[rax+vcs_ownership_edge.child_id]
 mov rsi,r12
 mov r10,rcx
 call ids_equal_owner
 mov rcx,r10
 test eax,eax
 jnz .reclaim_owned
 inc rcx
 jmp .reclaim_loop
.reclaim_ok:
 xor eax,eax
 jmp .reclaim_done
.reclaim_owned:
 mov eax,VCS_ERR_CONFLICT
 jmp .reclaim_done
.reclaim_usage:
 mov eax,VCS_ERR_USAGE
.reclaim_done:
 pop r13
 pop r12
 pop rbx
 ret

; Compare canonical edge keys: child ID bytes, owner kind integer, owner bytes.
; RDI=left, RSI=right. EAX=-1,0,1.
edge_compare:
 push rbx
 mov rbx,rsi
 lea rsi,[rsi+vcs_ownership_edge.child_id]
 lea rdi,[rdi+vcs_ownership_edge.child_id]
 mov ecx,32
 call bytes_compare
 test eax,eax
 jnz .edge_compare_done
 sub rdi,vcs_ownership_edge.child_id
 sub rbx,0
 mov edx,[rdi+vcs_ownership_edge.owner_kind]
 cmp edx,[rbx+vcs_ownership_edge.owner_kind]
 jb .edge_less
 ja .edge_greater
 lea rdi,[rdi+vcs_ownership_edge.owner_key]
 lea rsi,[rbx+vcs_ownership_edge.owner_key]
 mov ecx,32
 call bytes_compare
 jmp .edge_compare_done
.edge_less:
 mov eax,-1
 jmp .edge_compare_done
.edge_greater:
 mov eax,1
.edge_compare_done:
 pop rbx
 ret

bytes_compare:
 xor edx,edx
.bytes_loop:
 cmp rdx,rcx
 jae .bytes_equal
 mov al,[rdi+rdx]
 cmp al,[rsi+rdx]
 jb .bytes_less
 ja .bytes_greater
 inc rdx
 jmp .bytes_loop
.bytes_equal:
 xor eax,eax
 ret
.bytes_less:
 mov eax,-1
 ret
.bytes_greater:
 mov eax,1
 ret

ids_equal_owner:
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
