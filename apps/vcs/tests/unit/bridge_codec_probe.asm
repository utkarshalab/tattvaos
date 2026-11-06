bits 64
default rel
extern bridge_pkt_encode,bridge_pkt_decode
global bridge_encode_probe,bridge_decode_probe
global probe_status,probe_pointer,probe_length,probe_consumed,probe_kind
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
probe_status: resq 1
probe_pointer: resq 1
probe_length: resq 1
probe_consumed: resq 1
probe_kind: resq 1
uxv_nodes: resb 1
vcs_object_path: resb 1
vcs_repo_head: resq 1
vcs_repo_root: resb 1
vcs_repo_root_size: resq 1

section .text
bridge_encode_probe:
 call bridge_pkt_encode
 mov [probe_status],rax
 mov [probe_length],rdx
 ret
bridge_decode_probe:
 call bridge_pkt_decode
 mov [probe_status],rax
 mov [probe_pointer],rdx
 mov [probe_length],rcx
 mov [probe_consumed],r8
 mov [probe_kind],r9
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
