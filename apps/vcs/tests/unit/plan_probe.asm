%define UV_NODE 4352
%define UV_TYPE 240
%define UV_SIZE 248
%define UV_DATA 256
%define VB_MAP_MAGIC 0x3150414d53435655
bits 64
default rel

extern vcs_sync_plan
global plan_probe,plan_probe_reset
global probe_status,probe_count,probe_target,probe_digest
global uxv_ready,vcs_repo_head,vcs_repo_last,vcs_object_path
global mock_discover_status,mock_ref_status,mock_ref_target,mock_manifest_count
global mock_map_mask,mock_manifests,mock_hash_nodes,mock_map_nodes
global uxv_find,vcs_repo_discover,vcs_load_manifest,vcs_object_name,vcs_ref

section .bss
probe_status: resq 1
probe_count: resq 1
probe_target: resq 1
probe_digest: resq 1
mock_discover_status: resq 1
mock_ref_status: resq 1
mock_ref_target: resq 1
mock_manifest_count: resq 1
mock_map_mask: resq 1
mock_last_id: resq 1
mock_last_kind: resq 1
uxv_ready: resq 1
vcs_repo_head: resq 1
vcs_repo_last: resq 1
vcs_object_path: resb 256
mock_manifests: resb 768
mock_hash_nodes: resb (3*UV_NODE)
mock_map_nodes: resb (3*UV_NODE)

section .text
plan_probe:
 call vcs_sync_plan
 mov [probe_status],rax
 mov [probe_count],rdx
 mov [probe_target],r8
 mov [probe_digest],r9
 ret

plan_probe_reset:
 mov qword [uxv_ready],1
 mov qword [vcs_repo_head],3
 mov qword [vcs_repo_last],3
 mov qword [mock_manifest_count],3
 mov qword [mock_discover_status],0
 mov qword [mock_ref_status],0
 mov qword [mock_ref_target],2
 mov qword [mock_map_mask],0
 xor eax,eax
 ret

vcs_repo_discover:
 mov rax,[mock_discover_status]
 ret

vcs_load_manifest:
 test rdi,rdi
 jz .manifest_missing
 cmp rdi,[mock_manifest_count]
 ja .manifest_missing
 dec rdi
 shl rdi,8
 lea rax,[mock_manifests]
 add rax,rdi
 ret
.manifest_missing:
 xor eax,eax
 ret

vcs_object_name:
 test rdi,rdi
 jz .name_bad
 cmp rdi,3
 ja .name_bad
 cmp sil,'h'
 je .name_ok
 cmp sil,'m'
 jne .name_bad
.name_ok:
 mov [mock_last_id],rdi
 movzx eax,sil
 mov [mock_last_kind],rax
 xor eax,eax
 ret
.name_bad:
 mov eax,1
 ret

uxv_find:
 mov rax,[mock_last_id]
 test rax,rax
 jz .find_missing
 dec rax
 imul rax,UV_NODE
 cmp qword [mock_last_kind],'h'
 jne .find_map
 lea rdx,[mock_hash_nodes]
 add rax,rdx
 ret
.find_map:
 mov rcx,[mock_last_id]
 dec rcx
 bt [mock_map_mask],rcx
 jnc .find_missing
 lea rdx,[mock_map_nodes]
 add rax,rdx
 ret
.find_missing:
 xor eax,eax
 ret

vcs_ref:
 mov rax,[mock_ref_status]
 test rax,rax
 jnz .ref_done
 mov rdx,[mock_ref_target]
.ref_done:
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
