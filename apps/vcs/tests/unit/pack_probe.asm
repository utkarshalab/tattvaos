bits 64
default rel
extern git_pack_finish
global pack_finish_probe,probe_status,probe_length

section .bss
probe_status: resq 1
probe_length: resq 1

section .text
pack_finish_probe:
 call git_pack_finish
 mov [probe_status],rax
 mov [probe_length],rdx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
