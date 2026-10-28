; Persistent native remote endpoints stored in repository metadata.
%include "include/vcs.inc"
%include "lib/storage/uxfs/volume.inc"
bits 64
default rel

%define VR_REMOTE_MAGIC 0x31544f4d45524356 ; VCREMOT1
%define VR_REMOTE_SIZE  16

extern uxv_ready,uxv_nodes,uxv_find,uxv_free,uxv_commit
extern vcs_repo_discover,vcs_repo_root,vcs_repo_root_size

section .bss
remote_path: resb 240
remote_ip: resd 1
remote_port: resw 1
remote_number: resb 16
remote_writer: resq 1

section .rodata
remote_suffix: db '/.vcs/remote.',0
space: db ' '
colon: db ':'
dot: db '.'
newline: db 10

section .text
global vcs_remote
; op: 0 list, 1 add, 2 remove, 3 resolve.
; RSI=name, RDX=IPv4 text, RCX=port text, R8=writer for list.
; Resolve returns EDX=network-order IPv4 and ECX=host-order port.
vcs_remote:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 mov [remote_writer],r8
 cmp rbp,3
 ja .usage
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 test rbp,rbp
 jz .list
 test r12,r12
 jz .usage
 mov rdi,r12
 call valid_name
 test eax,eax
 jz .usage
 call make_path
 test eax,eax
 jnz .usage
 lea rdi,[remote_path]
 call uxv_find
 mov rbx,rax
 cmp rbp,1
 je .add
 test rbx,rbx
 jz .missing
 call validate_node
 test eax,eax
 jnz .corrupt
 cmp rbp,3
 je .resolve
 mov rdi,rbx
 call clear_node
 call uxv_commit
 test rax,rax
 js .io
 xor eax,eax
 jmp .done
.resolve:
 mov edx,[rbx+UV_DATA+8]
 movzx ecx,word [rbx+UV_DATA+12]
 xor eax,eax
 jmp .done
.add:
 test rbx,rbx
 jnz .conflict
 test r13,r13
 jz .usage
 test r14,r14
 jz .usage
 mov rdi,r13
 call parse_ipv4
 test eax,eax
 jnz .usage
 mov [remote_ip],edx
 mov rdi,r14
 call parse_port
 test eax,eax
 jnz .usage
 mov [remote_port],dx
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
 mov rdi,rbx
 call clear_node
 mov rdi,rbx
 lea rsi,[remote_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],VR_REMOTE_SIZE
 mov rax,VR_REMOTE_MAGIC
 mov [rbx+UV_DATA],rax
 mov eax,[remote_ip]
 mov [rbx+UV_DATA+8],eax
 mov ax,[remote_port]
 mov [rbx+UV_DATA+12],ax
 call uxv_commit
 test rax,rax
 js .io
 xor eax,eax
 jmp .done
.list:
 cmp qword [remote_writer],0
 je .usage
 lea r15,[uxv_nodes+UV_NODE]
.list_loop:
 cmp qword [r15+UV_TYPE],1
 jne .list_next
 mov rdi,r15
 call path_name
 test rax,rax
 jz .list_next
 mov r14,rax
 mov rdi,r14
 call valid_name
 test eax,eax
 jz .corrupt
 mov rbx,r15
 call validate_node
 test eax,eax
 jnz .corrupt
 mov rdi,r14
 call emit_string
 lea rdi,[space]
 mov esi,1
 call emit
 mov eax,[r15+UV_DATA+8]
 call emit_ipv4
 lea rdi,[colon]
 mov esi,1
 call emit
 movzx edi,word [r15+UV_DATA+12]
 call emit_decimal
 lea rdi,[newline]
 mov esi,1
 call emit
.list_next:
 add r15,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp r15,rax
 jb .list_loop
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .done
.io: mov eax,VCS_ERR_IO
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

validate_node:
 cmp qword [rbx+UV_TYPE],1
 jne .invalid
 cmp qword [rbx+UV_SIZE],VR_REMOTE_SIZE
 jne .invalid
 mov rax,VR_REMOTE_MAGIC
 cmp [rbx+UV_DATA],rax
 jne .invalid
 cmp word [rbx+UV_DATA+12],0
 je .invalid
 cmp word [rbx+UV_DATA+14],0
 jne .invalid
 xor eax,eax
 ret
.invalid: mov eax,1
 ret

valid_name:
 xor ecx,ecx
.name_loop:
 movzx eax,byte [rdi+rcx]
 test al,al
 jz .name_end
 cmp ecx,32
 jae .name_bad
 cmp al,'-'
 je .name_good
 cmp al,'.'
 je .name_good
 cmp al,'_'
 je .name_good
 cmp al,'0'
 jb .name_bad
 cmp al,'9'
 jbe .name_good
 or al,32
 cmp al,'a'
 jb .name_bad
 cmp al,'z'
 ja .name_bad
.name_good:
 inc ecx
 jmp .name_loop
.name_end:
 test ecx,ecx
 jz .name_bad
 cmp byte [rdi],'.'
 je .name_bad
 mov eax,1
 ret
.name_bad:
 xor eax,eax
 ret

make_path:
 lea rdi,[remote_path]
 xor eax,eax
 mov ecx,240/8
 rep stosq
 mov rcx,[vcs_repo_root_size]
 cmp rcx,194
 ja .path_bad
 cmp rcx,1
 jne .path_copy
 xor ecx,ecx
.path_copy:
 lea rsi,[vcs_repo_root]
 lea rdi,[remote_path]
 rep movsb
 lea rsi,[remote_suffix]
 mov ecx,14
 rep movsb
 dec rdi
 mov rsi,r12
.path_name_copy:
 lodsb
 stosb
 test al,al
 jnz .path_name_copy
 xor eax,eax
 ret
.path_bad: mov eax,VCS_ERR_USAGE
 ret

; Return pointer to suffix name only if this node belongs to current repo.
path_name:
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .path_root
 xor ecx,ecx
.path_root:
 lea rdi,[vcs_repo_root]
 mov rsi,r15
 repe cmpsb
 jne .path_none
 lea rdi,[remote_suffix]
 mov ecx,13
 repe cmpsb
 jne .path_none
 cmp byte [rsi],0
 je .path_none
 mov rax,rsi
 ret
.path_none:
 xor eax,eax
 ret

parse_ipv4:
 xor edx,edx
 xor r8d,r8d
.octet:
 cmp r8d,4
 jae .ip_bad
 xor eax,eax
 xor ecx,ecx
.digit:
 movzx r9d,byte [rdi]
 cmp r9b,'0'
 jb .octet_end
 cmp r9b,'9'
 ja .octet_end
 imul eax,eax,10
 sub r9b,'0'
 movzx r9d,r9b
 add eax,r9d
 cmp eax,255
 ja .ip_bad
 inc rdi
 inc ecx
 cmp ecx,3
 jbe .digit
 jmp .ip_bad
.octet_end:
 test ecx,ecx
 jz .ip_bad
 mov [remote_number+r8],al
 inc r8d
 cmp r8d,4
 je .ip_finish
 cmp byte [rdi],'.'
 jne .ip_bad
 inc rdi
 jmp .octet
.ip_finish:
 cmp byte [rdi],0
 jne .ip_bad
 mov edx,[remote_number]
 xor eax,eax
 ret
.ip_bad: mov eax,1
 ret

parse_port:
 xor edx,edx
 xor ecx,ecx
.port_digit:
 movzx eax,byte [rdi]
 test al,al
 jz .port_end
 cmp al,'0'
 jb .port_bad
 cmp al,'9'
 ja .port_bad
 imul edx,edx,10
 sub al,'0'
 movzx eax,al
 add edx,eax
 cmp edx,65535
 ja .port_bad
 inc rdi
 inc ecx
 cmp ecx,5
 jbe .port_digit
.port_bad: mov eax,1
 ret
.port_end:
 test ecx,ecx
 jz .port_bad
 test edx,edx
 jz .port_bad
 xor eax,eax
 ret

emit_ipv4:
 mov [remote_ip],eax
 xor ebx,ebx
.ip_print:
 movzx edi,byte [remote_ip+rbx]
 call emit_decimal
 inc ebx
 cmp ebx,4
 jae .ip_print_done
 lea rdi,[dot]
 mov esi,1
 call emit
 jmp .ip_print
.ip_print_done: ret

emit_decimal:
 lea r8,[remote_number+15]
 xor ecx,ecx
 mov eax,edi
 mov r9d,10
.decimal_loop:
 xor edx,edx
 div r9d
 add dl,'0'
 dec r8
 mov [r8],dl
 inc ecx
 test eax,eax
 jnz .decimal_loop
 mov rdi,r8
 mov rsi,rcx
 jmp emit

emit_string:
 mov rdx,rdi
 xor esi,esi
.string_len:
 cmp byte [rdx+rsi],0
 je emit
 inc esi
 jmp .string_len

emit:
 jmp [remote_writer]

clear_node:
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
