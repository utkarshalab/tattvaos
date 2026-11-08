bits 64
default rel
global vcs_load_manifest,history_plan_probe
global history_probe_status,history_probe_count,mock_history_count,mock_history_manifests
extern git_first_parent_plan

section .bss
history_probe_status: resq 1
history_probe_count: resq 1
mock_history_count: resq 1
mock_history_manifests: resb 8*256

section .text
vcs_load_manifest:
 test rdi,rdi
 jz .missing
 cmp rdi,[mock_history_count]
 ja .missing
 dec rdi
 shl rdi,8
 lea rax,[mock_history_manifests]
 add rax,rdi
 ret
.missing:
 xor eax,eax
 ret

history_plan_probe:
 call git_first_parent_plan
 mov [history_probe_status],rax
 mov [history_probe_count],rdx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
