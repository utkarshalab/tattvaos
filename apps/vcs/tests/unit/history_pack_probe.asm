%define UV_TYPE 240
%define UV_SIZE 248
%define UV_DATA 256
bits 64
default rel
extern git_history_pack,git_history_pack_cut,git_history_oid,git_history_find_common
global history_pack_probe,history_pack_cut_probe,history_oid_probe,history_common_probe
global history_pack_status,history_pack_value
global vcs_load_manifest,vcs_object_name,uxv_find
global mock_history_manifests,mock_history_manifest_count,mock_history_nodes,vcs_object_path

section .bss
history_pack_status: resq 1
history_pack_value: resq 1
mock_history_manifest_count: resq 1
mock_history_manifests: resb 8*4096
mock_history_nodes: resb 8*4352
vcs_object_path: resb 256

section .text
history_pack_probe:
 call git_history_pack
 jmp capture
history_pack_cut_probe:
 call git_history_pack_cut
 jmp capture
history_oid_probe:
 call git_history_oid
 jmp capture
history_common_probe:
 call git_history_find_common
capture:
 mov [history_pack_status],rax
 mov [history_pack_value],rdx
 ret

vcs_load_manifest:
 test rdi,rdi
 jz .missing
 cmp rdi,[mock_history_manifest_count]
 ja .missing
 dec rdi
 shl rdi,12
 lea rax,[mock_history_manifests]
 add rax,rdi
 ret
.missing:
 xor eax,eax
 ret

vcs_object_name:
 cmp sil,'b'
 jne .bad_name
 test rdi,rdi
 jz .bad_name
 cmp rdi,8
 ja .bad_name
 mov [vcs_object_path],rdi
 xor eax,eax
 ret
.bad_name:
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
 lea rdx,[mock_history_nodes]
 add rax,rdx
 ret
.missing_node:
 xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
