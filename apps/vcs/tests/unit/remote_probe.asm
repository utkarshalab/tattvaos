bits 64
default rel
extern vcs_remote
global remote_resolve_probe,probe_ip,probe_port

section .bss
probe_ip: resd 1
probe_port: resd 1

section .text
remote_resolve_probe:
 mov rsi,rdi
 mov edi,3
 xor edx,edx
 xor ecx,ecx
 xor r8d,r8d
 call vcs_remote
 mov [probe_ip],edx
 mov [probe_port],ecx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
