%define UV_NODES 64
%define UV_NODE 4352
%define UV_BYTES (UV_NODES*UV_NODE)
%define UV_TYPE 240
bits 64
default rel
extern bridge_git_import
global bridge_import_probe,bridge_import_status
global uxv_nodes,vcs_object_path,vcs_repo_head,vcs_repo_root,vcs_repo_root_size
global mock_import_calls,mock_import_signed,mock_import_fail_at,mock_import_checkout,mock_import_discover
global mock_import_messages
global vcs_repo_discover,uxv_normalize,uxv_find,uxv_free,vcs_history
global vcs_history_signed,vcs_checkout
global vcs_load_manifest,vcs_object_name,git_first_parent_plan
global git_history_common,git_history_find_common,git_history_object_sizes,git_history_oid
global git_history_pack_cut,git_history_set_unshallow,git_protocol_v2_acknowledge
global git_protocol_v2_advertise,git_protocol_v2_fetch,git_protocol_v2_haves
global git_protocol_v2_ls_refs,git_protocol_v2_object_info,git_protocol_v2_parse_request
global git_protocol_v2_shallow

section .bss
bridge_import_status: resq 1
mock_import_calls: resq 1
mock_import_signed: resq 1
mock_import_fail_at: resq 1
mock_import_checkout: resq 1
mock_import_discover: resq 1
mock_import_messages: resb 4*216
uxv_nodes: resb UV_BYTES
vcs_object_path: resb 256
vcs_repo_head: resq 1
vcs_repo_root: resb 240
vcs_repo_root_size: resq 1

section .text
bridge_import_probe:
 call bridge_git_import
 mov [bridge_import_status],rax
 ret

vcs_repo_discover:
 inc qword [mock_import_discover]
 xor eax,eax
 ret
uxv_normalize:
 xchg rdi,rsi
 mov rcx,240
 rep movsb
 xor eax,eax
 ret
uxv_find:
 lea rdx,[uxv_nodes+UV_NODE]
.find:
 cmp qword [rdx+UV_TYPE],0
 je .find_next
 push rdi
 push rdx
 mov rsi,rdx
 mov ecx,240
 repe cmpsb
 pop rdx
 pop rdi
 je .found
.find_next:
 add rdx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rdx,rax
 jb .find
 xor eax,eax
 ret
.found:
 mov rax,rdx
 ret
uxv_free:
 lea rax,[uxv_nodes+UV_NODE]
.free_scan:
 cmp qword [rax+UV_TYPE],0
 je .free_found
 add rax,UV_NODE
 lea rdx,[uxv_nodes+UV_BYTES]
 cmp rax,rdx
 jb .free_scan
 xor eax,eax
.free_found:
 ret

vcs_history:
 mov rdi,rsi
 xor esi,esi
 jmp record_history
vcs_history_signed:
 inc qword [mock_import_signed]
 xor esi,esi
record_history:
 inc qword [mock_import_calls]
 mov rax,[mock_import_calls]
 cmp rax,[mock_import_fail_at]
 je .history_fail
 dec rax
 imul rax,216
 lea rdx,[mock_import_messages]
 add rdx,rax
 xor ecx,ecx
.copy_message:
 mov al,[rdi+rcx]
 mov [rdx+rcx],al
 inc rcx
 test al,al
 jnz .copy_message
 mov rax,[mock_import_calls]
 mov [vcs_repo_head],rax
 xor eax,eax
 ret
.history_fail:
 mov eax,6
 ret
vcs_checkout:
 mov [mock_import_checkout],rdi
 xor eax,eax
 ret

vcs_load_manifest: xor eax,eax
 ret
vcs_object_name: xor eax,eax
 ret
git_first_parent_plan: xor eax,eax
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

section .note.GNU-stack noalloc noexec nowrite progbits
