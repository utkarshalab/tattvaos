; Recursive Git tree directory planner for bounded VCS manifests.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/git_tree.inc"
bits 64
default rel

section .bss
plan_manifest: resq 1
plan_output: resq 1
plan_capacity: resq 1
plan_count: resq 1
prefix: resb VR_PATH

section .text
global git_tree_plan
; RDI=validated manifest, RSI=record buffer, RDX=record capacity.
; Returns RAX=status, RDX=record count. Record zero is the root directory.
git_tree_plan:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .usage
 test rsi,rsi
 jz .usage
 test rdx,rdx
 jz .usage
 cmp rdx,GIT_TREE_MAX
 ja .usage
 mov [plan_manifest],rdi
 mov [plan_output],rsi
 mov [plan_capacity],rdx
 mov qword [plan_count],1
 mov rbp,rdi
 mov rdi,rsi
 xor eax,eax
 mov ecx,GIT_TREE_RECORD/8
 rep stosq
 mov qword [rsi+GT_PARENT],-1
 mov r15,[rbp+24]
 cmp r15,VR_FILES
 ja .corrupt
 xor r12d,r12d
.file:
 cmp r12,r15
 jae .parents
 mov r13,r12
 shl r13,8
 add r13,rbp
 add r13,VR_HEADER
 lea rdi,[prefix]
 xor eax,eax
 mov ecx,VR_PATH/8
 rep stosq
 xor r14d,r14d                 ; path offset
 xor ebx,ebx                   ; directory depth
.component:
 mov rcx,r14
.scan:
 cmp rcx,VR_PATH
 jae .corrupt
 mov al,[r13+rcx]
 test al,al
 jz .file_name
 cmp al,'/'
 je .directory
 cmp al,32
 jb .corrupt
 cmp al,127
 je .corrupt
 inc rcx
 jmp .scan
.directory:
 cmp rcx,r14
 je .corrupt
 mov rax,rcx
 sub rax,r14
 cmp rax,1
 jne .not_dotdot
 cmp byte [r13+r14],'.'
 je .corrupt
.not_dotdot:
 cmp rax,2
 jne .copy_prefix
 cmp byte [r13+r14],'.'
 jne .copy_prefix
 cmp byte [r13+r14+1],'.'
 je .corrupt
.copy_prefix:
 cmp rax,4
 jne .prefix_ready
 cmp dword [r13+r14],0x7363762e
 je .corrupt
.prefix_ready:
 inc rbx
 mov rdx,rcx
 inc rdx                       ; prefix includes separator
 cmp rdx,VR_PATH
 jae .corrupt
 lea rsi,[r13]
 lea rdi,[prefix]
 mov rcx,rdx
 rep movsb
 mov byte [prefix+rdx],0
 mov r14,rdx
 mov rdi,rbx
 call add_directory
 test eax,eax
 jnz .done
 jmp .component
.file_name:
 cmp rcx,r14
 je .corrupt
 ; Metadata components can never enter a Git tree.
 mov rax,rcx
 sub rax,r14
 cmp rax,1
 jne .file_dotdot
 cmp byte [r13+r14],'.'
 je .corrupt
.file_dotdot:
 cmp rax,2
 jne .file_metadata
 cmp byte [r13+r14],'.'
 jne .file_metadata
 cmp byte [r13+r14+1],'.'
 je .corrupt
.file_metadata:
 cmp rax,4
 jne .next_file
 cmp dword [r13+r14],0x7363762e
 je .corrupt
.next_file:
 inc r12
 jmp .file

.parents:
 mov r12d,1
.parent_record:
 cmp r12,[plan_count]
 jae .ok
 mov rax,r12
 shl rax,8
 add rax,[plan_output]
 mov r13,rax
 mov r14,[r13+GT_DEPTH]
 dec r14
 test r14,r14
 jz .parent_root
 ; Trim the last component and resolve its directory record.
 lea rsi,[r13+GT_PATH]
 xor ecx,ecx
.length:
 cmp byte [rsi+rcx],0
 je .length_ready
 inc rcx
 jmp .length
.length_ready:
 dec rcx                       ; skip trailing slash
.trim:
 test rcx,rcx
 jz .parent_root
 dec rcx
 cmp byte [rsi+rcx],'/'
 jne .trim
 inc rcx
 lea rdi,[prefix]
 push rcx
 rep movsb
 pop rcx
 mov byte [prefix+rcx],0
 lea rdi,[prefix]
 call find_directory
 test rax,rax
 jz .corrupt
 mov [r13+GT_PARENT],rax
 jmp .parent_next
.parent_root:
 mov qword [r13+GT_PARENT],0
.parent_next:
 inc r12
 jmp .parent_record
.ok:
 xor eax,eax
 mov rdx,[plan_count]
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=depth, prefix global. RDX remains next source offset on return.
add_directory:
 push rbx
 push r12
 sub rsp,8
 mov r12,rdi
 lea rdi,[prefix]
 call find_directory
 test rax,rax
 jnz .ok
 mov rax,[plan_count]
 cmp rax,[plan_capacity]
 jae .full
 mov rbx,rax
 shl rbx,8
 add rbx,[plan_output]
 mov rdi,rbx
 lea rsi,[prefix]
 mov ecx,VR_PATH
 rep movsb
 mov [rbx+GT_DEPTH],r12
 mov qword [rbx+GT_PARENT],-1
 inc qword [plan_count]
.ok: xor eax,eax
 jmp .done
.full: mov eax,VCS_ERR_NO_MEM
.done:
 add rsp,8
 pop r12
 pop rbx
 ret

; RDI=NUL path -> RAX=record index, zero only for missing/non-root lookup.
find_directory:
 push rbx
 mov rbx,rdi
 mov r8d,1
.record:
 cmp r8,[plan_count]
 jae .missing
 mov rax,r8
 shl rax,8
 add rax,[plan_output]
 xor ecx,ecx
.compare:
 mov dl,[rbx+rcx]
 cmp dl,[rax+rcx]
 jne .next
 test dl,dl
 jz .found
 inc rcx
 cmp rcx,VR_PATH
 jb .compare
.next:
 inc r8
 jmp .record
.found: mov rax,r8
 pop rbx
 ret
.missing: xor eax,eax
 pop rbx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
