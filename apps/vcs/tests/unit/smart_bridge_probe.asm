bits 64
default rel
extern bridge_git_serve,bridge_git_serve_terminal
global smart_serve_probe,smart_status,smart_length,smart_terminal
global vcs_load_manifest,vcs_object_name,uxv_find
global mock_smart_manifests,mock_smart_count,mock_smart_nodes,vcs_object_path
global uxv_nodes,vcs_repo_head,vcs_repo_root,vcs_repo_root_size
global uxv_free,uxv_normalize,vcs_checkout,vcs_history,vcs_history_signed,vcs_repo_discover

section .bss
smart_status: resq 1
smart_length: resq 1
smart_terminal: resq 1
mock_smart_count: resq 1
mock_smart_manifests: resb 8*4096
mock_smart_nodes: resb 8*4352
vcs_object_path: resb 256
uxv_nodes: resb 1
vcs_repo_head: resq 1
vcs_repo_root: resb 1
vcs_repo_root_size: resq 1

section .text
smart_serve_probe:
 call bridge_git_serve
 mov [smart_status],rax
 mov [smart_length],rdx
 call bridge_git_serve_terminal
 mov [smart_terminal],rax
 mov rax,[smart_status]
 ret

vcs_load_manifest:
 test rdi,rdi
 jz .missing
 cmp rdi,[mock_smart_count]
 ja .missing
 dec rdi
 shl rdi,12
 lea rax,[mock_smart_manifests]
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
 lea rdx,[mock_smart_nodes]
 add rax,rdx
 ret
.missing_node:
 xor eax,eax
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
