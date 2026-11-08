bits 64
default rel
extern git_commit_encode
global commit_encode_probe,commit_probe_status,commit_probe_length

section .bss
commit_probe_status: resq 1
commit_probe_length: resq 1

section .text
commit_encode_probe:
 call git_commit_encode
 mov [commit_probe_status],rax
 mov [commit_probe_length],rdx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
