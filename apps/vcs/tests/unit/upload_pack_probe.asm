%define UV_TYPE 240
%define UV_SIZE 248
%define UV_DATA 256
bits 64
default rel
extern git_snapshot_pack
global snapshot_pack_probe
global probe_status,probe_length,mock_manifest,mock_blob_node,vcs_object_path
global mock_load_status,mock_tree_status,mock_pack_status,mock_finish_status
global mock_begin_objects,mock_add_calls,mock_add_types
global vcs_load_manifest,vcs_object_name,uxv_find,git_object_hash
global git_pack_begin,git_pack_add,git_pack_finish,git_tree_plan
global git_tree_file_parents,git_tree_emit_plan,git_commit_encode

section .bss
probe_status: resq 1
probe_length: resq 1
mock_load_status: resq 1
mock_tree_status: resq 1
mock_pack_status: resq 1
mock_finish_status: resq 1
mock_begin_objects: resq 1
mock_add_calls: resq 1
mock_add_types: resq 8
mock_manifest: resb 512
mock_blob_node: resb 4352
vcs_object_path: resb 256

section .text
snapshot_pack_probe:
 call git_snapshot_pack
 mov [probe_status],rax
 mov [probe_length],rdx
 ret

vcs_load_manifest:
 cmp qword [mock_load_status],0
 jne .load_missing
 cmp rdi,1
 jne .load_missing
 lea rax,[mock_manifest]
 ret
.load_missing:
 xor eax,eax
 ret

vcs_object_name:
 cmp rdi,7
 jne .name_bad
 cmp sil,'b'
 jne .name_bad
 xor eax,eax
 ret
.name_bad:
 mov eax,1
 ret

uxv_find:
 lea rax,[mock_blob_node]
 ret

git_object_hash:
 mov rdi,r8
 mov al,0x11
 mov ecx,32
 rep stosb
 xor eax,eax
 ret

git_pack_begin:
 mov [mock_begin_objects],rdx
 mov rax,[mock_pack_status]
 ret

git_pack_add:
 mov rcx,[mock_add_calls]
 lea rax,[mock_add_types]
 mov [rax+rcx*8],rdi
 inc qword [mock_add_calls]
 mov rax,[mock_pack_status]
 ret

git_pack_finish:
 mov rax,[mock_finish_status]
 mov edx,123
 ret

git_tree_plan:
 mov rax,[mock_tree_status]
 mov edx,1
 ret

git_tree_file_parents:
 mov rax,[mock_tree_status]
 ret

git_tree_emit_plan:
 mov rax,[mock_tree_status]
 test rax,rax
 jnz .tree_done
 mov rdi,[rdi+40]
 mov al,0x22
 mov ecx,32
 rep stosb
 xor eax,eax
.tree_done:
 ret

git_commit_encode:
 mov rdx,10
 mov rax,[rdi+32]
 mov byte [rax],'c'
 mov rdi,[rdi+48]
 mov al,0x33
 mov ecx,32
 rep stosb
 xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
