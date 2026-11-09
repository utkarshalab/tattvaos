bits 64
default rel
extern bridge_git_serve
global bridge_serve_probe
global mock_operation,mock_wanted,mock_flags,mock_parse_status,mock_common_index
global mock_shallow_count,mock_shallow_oid,mock_haves_count,mock_calls,mock_pack_cut
global mock_seen_flags,mock_seen_cut,mock_unshallow,mock_haves,mock_oid
global uxv_nodes,vcs_object_path,vcs_repo_head,vcs_repo_root,vcs_repo_root_size
global git_first_parent_plan,git_history_common,git_history_find_common
global git_history_object_sizes,git_history_oid,git_history_pack_cut
global git_history_set_unshallow,git_protocol_v2_acknowledge
global git_protocol_v2_advertise,git_protocol_v2_fetch,git_protocol_v2_haves
global git_protocol_v2_ls_refs,git_protocol_v2_object_info
global git_protocol_v2_parse_request,git_protocol_v2_shallow
global uxv_find,uxv_free,uxv_normalize,vcs_checkout,vcs_history
global vcs_history_signed,vcs_load_manifest,vcs_object_name,vcs_repo_discover

section .bss
mock_operation: resq 1
mock_wanted: resq 1
mock_flags: resq 1
mock_parse_status: resq 1
mock_common_index: resq 1
mock_shallow_count: resq 1
mock_shallow_oid: resq 1
mock_haves_count: resq 1
mock_calls: resq 8
mock_pack_cut: resq 1
mock_seen_flags: resq 1
mock_seen_cut: resq 1
mock_unshallow: resq 1
mock_haves: resb 64*32
mock_oid: resb 32
uxv_nodes: resb 1
vcs_object_path: resb 1
vcs_repo_head: resq 1
vcs_repo_root: resb 1
vcs_repo_root_size: resq 1

section .text
bridge_serve_probe:
 jmp bridge_git_serve wrt ..plt

git_protocol_v2_parse_request:
 inc qword [mock_calls]
 mov rax,[mock_parse_status]
 mov rdx,[mock_operation]
 mov rcx,[mock_wanted]
 mov r8,[mock_flags]
 ret
git_history_oid:
 inc qword [mock_calls+8]
 mov al,0xaa
 mov rdi,rsi
 mov ecx,32
 rep stosb
 xor eax,eax
 mov edx,32
 ret
git_protocol_v2_ls_refs:
 inc qword [mock_calls+16]
 mov byte [rdx],'R'
 xor eax,eax
 mov edx,1
 ret
git_history_object_sizes:
 inc qword [mock_calls+24]
 mov rax,rdx
 xor edx,edx
.sizes:
 cmp rdx,rax
 jae .sizes_done
 mov qword [rcx+rdx*8],9
 mov byte [r8+rdx],1
 inc rdx
 jmp .sizes
.sizes_done:
 xor eax,eax
 ret
git_protocol_v2_object_info:
 inc qword [mock_calls+32]
 mov byte [rcx],'I'
 xor eax,eax
 mov edx,1
 ret
git_protocol_v2_haves:
 lea rax,[mock_haves]
 mov rdx,[mock_haves_count]
 ret
git_history_find_common:
 inc qword [mock_calls+40]
 xor eax,eax
 mov rdx,[mock_common_index]
 ret
git_protocol_v2_shallow:
 mov rax,[mock_shallow_oid]
 mov rdx,[mock_shallow_count]
 ret
git_history_set_unshallow:
 mov [mock_unshallow],rdi
 xor eax,eax
 ret
git_history_pack_cut:
 inc qword [mock_pack_cut]
 mov [mock_seen_cut],r8
 mov [mock_seen_flags],r9
 mov al,0xaa
 mov rdi,rcx
 mov ecx,32
 rep stosb
 mov dword [rsi],'PACK'
 xor eax,eax
 mov edx,4
 ret
git_protocol_v2_fetch:
 inc qword [mock_calls+48]
 mov byte [rdx],'F'
 xor eax,eax
 mov edx,1
 ret
git_history_common:
 lea rax,[mock_haves]
 mov rdx,[mock_haves_count]
 ret
git_protocol_v2_acknowledge:
 inc qword [mock_calls+56]
 mov byte [rdx],'A'
 xor eax,eax
 mov edx,1
 ret
git_protocol_v2_advertise:
 mov byte [rdi],'V'
 xor eax,eax
 mov edx,1
 ret

git_first_parent_plan: xor eax,eax
 ret
uxv_find: xor eax,eax
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
vcs_load_manifest: xor eax,eax
 ret
vcs_object_name: xor eax,eax
 ret
vcs_repo_discover: xor eax,eax
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
