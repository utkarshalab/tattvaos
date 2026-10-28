; Complete bounded first-parent Git SHA-256 PACK construction.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/git_pack.inc"
%include "include/git_tree.inc"
%include "include/git_commit.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern vcs_load_manifest,vcs_object_name,vcs_object_path
extern uxv_find
extern git_first_parent_plan,git_object_hash
extern git_pack_begin_unique,git_pack_add,git_pack_finish
extern git_tree_plan,git_tree_file_parents,git_tree_emit_plan
extern git_commit_encode

section .bss
hp_ids: resq UV_NODES
hp_count: resq 1
hp_objects: resq 1
hp_manifest: resq 1
hp_node: resq 1
hp_plan: resb GIT_TREE_MAX*GIT_TREE_RECORD
hp_plan_count: resq 1
hp_file_parents: resb VR_FILES
hp_blob_hashes: resb VR_FILES*GIT_HASH_SIZE
hp_tree_hashes: resb GIT_TREE_MAX*GIT_TREE_HASH_SIZE
hp_entries: resb (VR_FILES+GIT_TREE_MAX)*GIT_TREE_ENTRY
hp_emit_request: resb GIT_TREE_EMIT_PLAN_REQUEST
hp_tree_buffer: resb 32768
hp_commit_request: resb git_commit_request_size
hp_commit: resb 512
hp_commit_size: resq 1
hp_commit_hash: resb GIT_HASH_SIZE
hp_parent_hash: resb GIT_HASH_SIZE
hp_tip_output: resq 1

section .rodata
blob_type: db 'blob'

section .text
global git_history_pack

; RDI=VCS tip, RSI=PACK output, RDX=capacity, RCX=32-byte Git tip OID output.
git_history_pack:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .usage
 test rsi,rsi
 jz .usage
 test rcx,rcx
 jz .usage
 mov r12,rsi
 mov r13,rdx
 mov [hp_tip_output],rcx
 lea rsi,[hp_ids]
 mov edx,UV_NODES
 call git_first_parent_plan
 test eax,eax
 jnz .done
 mov [hp_count],rdx
 mov qword [hp_objects],0
 xor ebx,ebx
.preflight:
 cmp rbx,[hp_count]
 jae .begin_pack
 lea rax,[hp_ids]
 mov rdi,[rax+rbx*8]
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rbp,rax
 mov rdi,rbp
 lea rsi,[hp_plan]
 mov edx,GIT_TREE_MAX
 call git_tree_plan
 test eax,eax
 jnz .done
 mov rax,[rbp+24]
 add rax,rdx
 inc rax
 add [hp_objects],rax
 jc .space
 cmp qword [hp_objects],0xffffffff
 ja .space
 inc rbx
 jmp .preflight
.begin_pack:
 mov rdi,r12
 mov rsi,r13
 mov rdx,[hp_objects]
 call git_pack_begin_unique
 test eax,eax
 jnz .done
 lea rdi,[hp_parent_hash]
 xor eax,eax
 mov ecx,GIT_HASH_SIZE/8
 rep stosq
 mov r14,[hp_count]
.snapshot:
 test r14,r14
 jz .finish_pack
 dec r14
 lea rax,[hp_ids]
 mov rdi,[rax+r14*8]
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rbp,rax
 mov [hp_manifest],rax
 mov rdi,rbp
 lea rsi,[hp_plan]
 mov edx,GIT_TREE_MAX
 call git_tree_plan
 test eax,eax
 jnz .done
 mov [hp_plan_count],rdx
 xor ebx,ebx
.hash_blob:
 cmp rbx,[rbp+24]
 jae .map_files
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov [hp_node],rax
 mov rdx,rbx
 shl rdx,8
 add rdx,rbp
 add rdx,VR_HEADER
 mov rcx,[rdx+VR_SIZE]
 cmp [rax+UV_SIZE],rcx
 jne .corrupt
 mov rax,rbx
 imul rax,GIT_HASH_SIZE
 lea r8,[hp_blob_hashes]
 add r8,rax
 lea rdi,[blob_type]
 mov esi,4
 mov rax,[hp_node]
 lea rdx,[rax+UV_DATA]
 call git_object_hash
 test eax,eax
 jnz .done
 inc rbx
 jmp .hash_blob
.map_files:
 mov rdi,rbp
 lea rsi,[hp_plan]
 mov rdx,[hp_plan_count]
 lea rcx,[hp_file_parents]
 call git_tree_file_parents
 test eax,eax
 jnz .done
 xor ebx,ebx
.emit_blob:
 cmp rbx,[rbp+24]
 jae .emit_trees
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov r15,rax
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov edi,GIT_PACK_BLOB
 lea rsi,[rax+UV_DATA]
 mov rdx,[r15+VR_SIZE]
 call git_pack_add
 test eax,eax
 jnz .done
 inc rbx
 jmp .emit_blob
.emit_trees:
 lea rdi,[hp_emit_request]
 xor eax,eax
 mov ecx,GIT_TREE_EMIT_PLAN_REQUEST/8
 rep stosq
 mov [hp_emit_request+GTEP_MANIFEST],rbp
 lea rax,[hp_plan]
 mov [hp_emit_request+GTEP_PLAN],rax
 mov rax,[hp_plan_count]
 mov [hp_emit_request+GTEP_PLAN_COUNT],rax
 lea rax,[hp_file_parents]
 mov [hp_emit_request+GTEP_FILE_PARENTS],rax
 lea rax,[hp_blob_hashes]
 mov [hp_emit_request+GTEP_BLOB_HASHES],rax
 lea rax,[hp_tree_hashes]
 mov [hp_emit_request+GTEP_TREE_HASHES],rax
 lea rax,[hp_entries]
 mov [hp_emit_request+GTEP_ENTRIES],rax
 mov qword [hp_emit_request+GTEP_ENTRY_CAPACITY],VR_FILES+GIT_TREE_MAX
 lea rax,[hp_tree_buffer]
 mov [hp_emit_request+GTEP_BUFFER],rax
 mov qword [hp_emit_request+GTEP_BUFFER_CAPACITY],32768
 lea rdi,[hp_emit_request]
 call git_tree_emit_plan
 test eax,eax
 jnz .done
 lea rdi,[hp_commit_request]
 xor eax,eax
 mov ecx,git_commit_request_size/8
 rep stosq
 lea rax,[hp_tree_hashes]
 mov [hp_commit_request+git_commit_request.tree],rax
 mov rax,[hp_count]
 dec rax
 cmp r14,rax
 je .root_commit
 lea rax,[hp_parent_hash]
 mov [hp_commit_request+git_commit_request.parent],rax
.root_commit:
 lea rax,[rbp+VR_MESSAGE]
 mov [hp_commit_request+git_commit_request.message],rax
 mov rax,[rbp+32]
 btr rax,63
 mov [hp_commit_request+git_commit_request.message_len],rax
 lea rax,[hp_commit]
 mov [hp_commit_request+git_commit_request.output],rax
 mov qword [hp_commit_request+git_commit_request.capacity],512
 lea rax,[hp_commit_hash]
 mov [hp_commit_request+git_commit_request.hash],rax
 lea rdi,[hp_commit_request]
 call git_commit_encode
 test eax,eax
 jnz .done
 mov [hp_commit_size],rdx
 mov edi,GIT_PACK_COMMIT
 lea rsi,[hp_commit]
 mov rdx,[hp_commit_size]
 call git_pack_add
 test eax,eax
 jnz .done
 lea rsi,[hp_commit_hash]
 lea rdi,[hp_parent_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 test r14,r14
 jnz .snapshot
 lea rsi,[hp_commit_hash]
 mov rdi,[hp_tip_output]
 mov ecx,GIT_HASH_SIZE
 rep movsb
.finish_pack:
 call git_pack_finish
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
