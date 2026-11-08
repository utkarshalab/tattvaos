bits 64
default rel
extern bridge_git_export,bridge_git_export_history
global bridge_export_probe,bridge_export_history_probe,bridge_export_status,bridge_export_length
global uxv_nodes,vcs_object_path,vcs_repo_head,vcs_repo_root,vcs_repo_root_size
global mock_export_manifests,mock_export_nodes,mock_export_count
global vcs_load_manifest,vcs_object_name,uxv_find,git_first_parent_plan
global git_history_common,git_history_find_common,git_history_object_sizes,git_history_oid
global git_history_pack_cut,git_history_set_unshallow,git_protocol_v2_acknowledge
global git_protocol_v2_advertise,git_protocol_v2_fetch,git_protocol_v2_haves
global git_protocol_v2_ls_refs,git_protocol_v2_object_info,git_protocol_v2_parse_request
global git_protocol_v2_shallow,uxv_free,uxv_normalize,vcs_checkout,vcs_history
global vcs_history_signed,vcs_repo_discover

section .bss
bridge_export_status: resq 1
bridge_export_length: resq 1
mock_export_count: resq 1
mock_export_manifests: resb 8*4096
mock_export_nodes: resb 8*4352
vcs_object_path: resb 256
uxv_nodes: resb 1
vcs_repo_head: resq 1
vcs_repo_root: resb 1
vcs_repo_root_size: resq 1

section .text
bridge_export_probe:
 call bridge_git_export
 jmp capture
bridge_export_history_probe:
 call bridge_git_export_history
capture:
 mov [bridge_export_status],rax
 mov [bridge_export_length],rdx
 ret

vcs_load_manifest:
 test rdi,rdi
 jz .missing
 cmp rdi,[mock_export_count]
 ja .missing
 dec rdi
 shl rdi,12
 lea rax,[mock_export_manifests]
 add rax,rdi
 ret
.missing:
 xor eax,eax
 ret
vcs_object_name:
 cmp sil,'b'
 jne .name_bad
 test rdi,rdi
 jz .name_bad
 cmp rdi,8
 ja .name_bad
 mov [vcs_object_path],rdi
 xor eax,eax
 ret
.name_bad:
 mov eax,1
 ret
uxv_find:
 mov rax,[rdi]
 test rax,rax
 jz .missing_node
 cmp rax,8
 ja .missing_node
 dec rax
 imul rax,4352
 lea rdx,[mock_export_nodes]
 add rax,rdx
 ret
.missing_node:
 xor eax,eax
 ret
git_first_parent_plan:
 cmp rdi,2
 jne .single
 mov qword [rsi],2
 mov qword [rsi+8],1
 mov edx,2
 xor eax,eax
 ret
.single:
 cmp rdi,1
 jne .plan_bad
 mov qword [rsi],1
 mov edx,1
 xor eax,eax
 ret
.plan_bad:
 mov eax,5
 ret

git_history_common: xor eax,eax
 ret
git_history_find_common: xor eax,eax
 ret
git_history_object_sizes: xor eax,eax
 ret
git_history_oid: xor eax,eax
 ret
git_history_pack_cut: xor eax,eax
 ret
git_history_set_unshallow: xor eax,eax
 ret
git_protocol_v2_acknowledge: xor eax,eax
 ret
git_protocol_v2_advertise: xor eax,eax
 ret
git_protocol_v2_fetch: xor eax,eax
 ret
git_protocol_v2_haves: xor eax,eax
 ret
git_protocol_v2_ls_refs: xor eax,eax
 ret
git_protocol_v2_object_info: xor eax,eax
 ret
git_protocol_v2_parse_request: xor eax,eax
 ret
git_protocol_v2_shallow: xor eax,eax
 ret
uxv_free: xor eax,eax
 ret
uxv_normalize: xor eax,eax
 ret
vcs_checkout: xor eax,eax
 ret
vcs_history: xor eax,eax
 ret
vcs_history_signed: xor eax,eax
 ret
vcs_repo_discover: xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
