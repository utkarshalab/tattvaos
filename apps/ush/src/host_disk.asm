; Linux development backend for an explicitly supplied UXFS image only.
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_read,uxv_write,uxv_flush
section .data
disk_fd: dq -1
section .bss
stat: resb 144
section .text
global host_disk_open
host_disk_open:
 push rbx
 mov eax,2
 mov esi,0x20002                ; O_RDWR | O_NOFOLLOW, never create or truncate
 xor edx,edx
 syscall
 test rax,rax
 js .bad
 mov rbx,rax
 mov rdi,rax
 mov esi,6                     ; exclusive, nonblocking flock
 mov eax,73
 syscall
 test rax,rax
 js .close
 mov rdi,rbx
 lea rsi,[stat]
 mov eax,5
 syscall
 test rax,rax
 js .close
 mov eax,[stat+24]
 and eax,0xf000
 cmp eax,0x8000
 jne .close
 cmp qword [stat+48],UV_BANK*2*512
 jb .close
 mov [disk_fd],rbx
 lea rax,[read]
 mov [uxv_read],rax
 lea rax,[write]
 mov [uxv_write],rax
 lea rax,[flush]
 mov [uxv_flush],rax
 xor eax,eax
 pop rbx
 ret
.close:
 mov rdi,rbx
 mov eax,3
 syscall
.bad:
 mov eax,1
 pop rbx
 ret
read: mov r8d,17
 jmp transfer
write: mov r8d,18
transfer:
 lea rax,[rdi+rsi]
 cmp rax,UV_BANK*2
 ja error
 mov r10,rdi
 shl r10,9
 mov rdi,[disk_fd]
 mov rax,rsi
 mov rsi,rdx
 mov rdx,rax
 shl rdx,9
.loop:
 mov eax,r8d
 syscall
 cmp rax,-4
 je .loop
 test rax,rax
 jle error
 add rsi,rax
 add r10,rax
 sub rdx,rax
 jnz .loop
 xor eax,eax
 ret
flush:
 mov rdi,[disk_fd]
.retry:
 mov eax,74
 syscall
 cmp rax,-4
 je .retry
 ret
error: mov rax,-5
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
