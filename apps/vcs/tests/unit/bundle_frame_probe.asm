bits 64
default rel

extern vcs_bundle_seal,vcs_bundle_open
global bundle_seal_probe,bundle_open_probe
global probe_status,probe_pointer,probe_length,probe_operation
global mock_trust_status,mock_verify_status
global sha256_init,sha256_update,sha256_final
global signing_public_from_seed,signing_sign,signing_verify
global vcs_identity_trust_key
global uxv_ready,uxv_nodes,vcs_repo_head,vcs_repo_last,vcs_repo_format
global vcs_object_path,uxv_find,uxv_commit,vcs_repo_discover
global vcs_load_manifest,vcs_object_name,vcs_signature_policy
global vcs_signature_prepare

section .bss
probe_status: resq 1
probe_pointer: resq 1
probe_length: resq 1
probe_operation: resq 1
mock_trust_status: resq 1
mock_verify_status: resq 1
mock_hash_sum: resq 1
uxv_ready: resq 1
uxv_nodes: resq 1
vcs_repo_head: resq 1
vcs_repo_last: resq 1
vcs_repo_format: resq 1
vcs_signature_policy: resq 1
vcs_object_path: resb 256

section .text
bundle_seal_probe:
 call vcs_bundle_seal
 mov [probe_status],rax
 mov [probe_length],rdx
 ret

bundle_open_probe:
 call vcs_bundle_open
 mov [probe_status],rax
 mov [probe_pointer],rdx
 mov [probe_length],rcx
 mov [probe_operation],r8
 ret

sha256_init:
 mov qword [mock_hash_sum],0
 xor eax,eax
 ret

sha256_update:
 mov rax,[mock_hash_sum]
.hash_loop:
 test rdx,rdx
 jz .hash_done
 movzx ecx,byte [rsi]
 add rax,rcx
 inc rsi
 dec rdx
 jmp .hash_loop
.hash_done:
 mov [mock_hash_sum],rax
 xor eax,eax
 ret

sha256_final:
 mov rdi,rsi
 mov rax,[mock_hash_sum]
 mov ecx,32
 rep stosb
 xor eax,eax
 ret

signing_public_from_seed:
 mov al,0x11
 mov ecx,32
 rep stosb
 xor eax,eax
 ret

signing_sign:
 mov rdi,rdx
 mov al,0x22
 mov ecx,64
 rep stosb
 xor eax,eax
 ret

signing_verify:
 mov rax,[mock_verify_status]
 ret

vcs_identity_trust_key:
 mov rax,[mock_trust_status]
 ret

uxv_find:
 xor eax,eax
 ret
uxv_commit:
 mov eax,-1
 ret
vcs_repo_discover:
 mov eax,-1
 ret
vcs_load_manifest:
 xor eax,eax
 ret
vcs_object_name:
 mov eax,-1
 ret
vcs_signature_prepare:
 mov eax,-1
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
