; Persistent selective staging index. One transaction per CLI invocation.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_find,uxv_free,uxv_commit,uxv_normalize
extern vcs_repo_discover,vcs_load_manifest,vcs_path_ignored
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head
section .bss
stage_writer: resq 1
stage_op: resq 1
index_node: resq 1
index_path: resb 240
canonical: resb 240
index_data: resb 4096
section .rodata
index_suffix: db '/.vcs/index',0
index_magic: db 'UVCSIDX1'
staged_text: db 'Staged '
staged_text_len equ $-staged_text
unstaged_text: db 'Unstaged '
unstaged_text_len equ $-unstaged_text
cleared_text: db 'Cleared staging index',10
cleared_text_len equ $-cleared_text
updated_text: db 'Staging index updated',10
updated_text_len equ $-updated_text
empty_text: db 'No staged paths',10
empty_text_len equ $-empty_text
newline: db 10
section .text
global vcs_stage
; op 0 add paths, 1 reset paths, 2 list, 3 reset all, 4 add all.
; rsi=count, rdx=array of NUL path pointers, rcx=write callback.
vcs_stage:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,4
 ja .usage
 test rcx,rcx
 jz .usage
 mov [stage_op],rdi
 mov [stage_writer],rcx
 mov r12,rsi
 mov r13,rdx
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_index_path
 lea rdi,[index_path]
 call uxv_find
 mov [index_node],rax
 call load_index
 test eax,eax
 jnz .done
 cmp qword [stage_op],2
 je .list
 cmp qword [stage_op],3
 je .reset_all
 cmp qword [stage_op],4
 je .add_all
 test r12,r12
 jz .usage
 xor r14d,r14d
.argument:
 cmp r14,r12
 jae .publish
 mov rdi,[r13+r14*8]
 lea rsi,[canonical]
 call uxv_normalize
 test rax,rax
 js .usage
 lea rdi,[canonical]
 call relative_path
 test rax,rax
 jz .usage
 mov r15,rax
 cmp qword [stage_op],1
 je .remove
 mov rdi,r15
 call eligible
 test eax,eax
 jz .usage
 mov rdi,r15
 call add_path
 test eax,eax
 jnz .done
 jmp .next_argument
.remove:
 mov rdi,r15
 call remove_path
.next_argument:
 inc r14
 jmp .argument
.add_all:
 ; Add every current regular path, respecting .vcsignore.
 lea rbx,[uxv_nodes+UV_NODE]
.all_node:
 cmp qword [rbx+UV_TYPE],1
 jne .all_next
 mov rdi,rbx
 call working_relative
 test rax,rax
 jz .all_next
 mov r15,rax
 mov rdi,rax
 call vcs_path_ignored
 test eax,eax
 jnz .all_next
 mov rdi,r15
 call add_path
 test eax,eax
 jnz .done
.all_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .all_node
 ; Add old paths too, so deleted tracked files are staged.
 mov rdi,[vcs_repo_head]
 test rdi,rdi
 jz .publish
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r14,[rax+24]
 add rax,VR_HEADER
.all_old:
 test r14,r14
 jz .publish
 mov rdi,rax
 push rax
 call add_path
 pop rax
 test eax,eax
 jnz .done
 add rax,VR_ENTRY
 dec r14
 jmp .all_old
.reset_all:
 mov qword [index_data+8],0
 jmp .publish
.list:
 mov r14,[index_data+8]
 test r14,r14
 jnz .list_rows
 lea rdi,[empty_text]
 mov esi,empty_text_len
 call emit
 jmp .ok
.list_rows:
 lea r15,[index_data+16]
.list_row:
 mov rdi,r15
 call print_string
 call print_newline
 add r15,240
 dec r14
 jnz .list_row
 jmp .ok
.publish:
 mov rax,[index_data+8]
 test rax,rax
 jnz .write_index
 mov rbx,[index_node]
 test rbx,rbx
 jz .ok
 call clear_node
 jmp .commit
.write_index:
 mov rbx,[index_node]
 test rbx,rbx
 jnz .have_node
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
.have_node:
 call clear_node
 mov rdi,rbx
 lea rsi,[index_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,[index_data+8]
 imul rcx,240
 add rcx,16
 mov [rbx+UV_SIZE],rcx
 lea rsi,[index_data]
 lea rdi,[rbx+UV_DATA]
 rep movsb
.commit:
 call uxv_commit
 test rax,rax
 js .io
 cmp qword [stage_op],3
 jne .updated
 lea rdi,[cleared_text]
 mov esi,cleared_text_len
 call emit
 jmp .ok
.updated:
 lea rdi,[updated_text]
 mov esi,updated_text_len
 call emit
.ok: xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
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

make_index_path:
 lea rdi,[index_path]
 xor eax,eax
 mov ecx,30
 rep stosq
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[vcs_repo_root]
 lea rdi,[index_path]
 rep movsb
 lea rsi,[index_suffix]
 mov ecx,12
 rep movsb
 ret
load_index:
 lea rdi,[index_data]
 xor eax,eax
 mov ecx,512
 rep stosq
 lea rdi,[index_data]
 lea rsi,[index_magic]
 mov ecx,8
 rep movsb
 mov rax,[index_node]
 test rax,rax
 jz .ok
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 cmp rcx,16
 jb .bad
 cmp rcx,3616
 ja .bad
 mov rax,rcx
 sub rax,16
 xor edx,edx
 mov r8,240
 div r8
 test rdx,rdx
 jnz .bad
 cmp rax,VR_FILES
 ja .bad
 mov rbx,[index_node]
 mov r9,[rbx+UV_DATA+8]
 cmp r9,rax
 jne .bad
 lea rdi,[index_data]
 lea rsi,[rbx+UV_DATA]
 rep movsb
 mov rdx,0x3158444953435655
 cmp [index_data],rdx
 jne .bad
 ; Validate paths and uniqueness.
 mov r14,[index_data+8]
 lea r15,[index_data+16]
.path:
 test r14,r14
 jz .ok
 mov rdi,r15
 call valid_relative
 test eax,eax
 jz .bad
 lea rbx,[index_data+16]
.unique:
 cmp rbx,r15
 jae .next
 mov rdi,rbx
 mov rsi,r15
 call same_name
 test eax,eax
 jnz .bad
 add rbx,240
 jmp .unique
.next:
 add r15,240
 dec r14
 jmp .path
.ok: xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

eligible:
 push rbx
 mov rbx,rdi
 lea rdi,[canonical]
 call uxv_find
 test rax,rax
 jz .tracked
 cmp qword [rax+UV_TYPE],1
 jne .no
 mov rdi,rbx
 call vcs_path_ignored
 test eax,eax
 jnz .tracked                    ; already tracked ignore still allowed
 mov eax,1
 pop rbx
 ret
.tracked:
 mov rdi,[vcs_repo_head]
 test rdi,rdi
 jz .no
 call vcs_load_manifest
 test rax,rax
 jz .no
 mov rcx,[rax+24]
 add rax,VR_HEADER
.find:
 test rcx,rcx
 jz .no
 mov rdi,rbx
 mov rsi,rax
 call same_name
 test eax,eax
 jnz .yes
 add rax,VR_ENTRY
 dec rcx
 jmp .find
.yes: mov eax,1
 pop rbx
 ret
.no: xor eax,eax
 pop rbx
 ret

add_path:
 push rbx
 mov rbx,rdi
 mov rcx,[index_data+8]
 lea rax,[index_data+16]
.find:
 test rcx,rcx
 jz .append
 mov rdi,rbx
 mov rsi,rax
 call same_name
 test eax,eax
 jnz .ok
 add rax,240
 dec rcx
 jmp .find
.append:
 mov rcx,[index_data+8]
 cmp rcx,VR_FILES
 jae .full
 imul rcx,240
 lea rdi,[index_data+16+rcx]
 mov rsi,rbx
 mov ecx,240
 rep movsb
 inc qword [index_data+8]
.ok: xor eax,eax
 pop rbx
 ret
.full: mov eax,VCS_ERR_NO_MEM
 pop rbx
 ret
remove_path:
 push rbx
 mov rbx,rdi
 xor edx,edx
.find:
 cmp rdx,[index_data+8]
 jae .done
 mov rax,rdx
 imul rax,240
 lea rsi,[index_data+16+rax]
 mov rdi,rbx
 call same_name
 test eax,eax
 jnz .erase
 inc rdx
 jmp .find
.erase:
 mov rax,[index_data+8]
 dec rax
 sub rax,rdx
 imul rcx,rax,240
 mov rdi,rsi
 add rsi,240
 rep movsb
 dec qword [index_data+8]
.done:
 xor eax,eax
 pop rbx
 ret

relative_path:
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 lea rsi,[vcs_repo_root]
 repe cmpsb
 jne .no
 cmp byte [rdi],'/'
 jne .no
 inc rdi
 jmp .check
.root:
 cmp byte [rdi],'/'
 jne .no
 inc rdi
.check:
 cmp byte [rdi],0
 je .no
 cmp dword [rdi],0x7363762e
 jne .yes
 cmp byte [rdi+4],0
 je .no
 cmp byte [rdi+4],'/'
 je .no
.yes: mov rax,rdi
 ret
.no: xor eax,eax
 ret
working_relative:
 jmp relative_path
valid_relative:
 xor ecx,ecx
.component:
 mov r8d,ecx
.scan:
 cmp ecx,240
 jae .bad
 mov al,[rdi+rcx]
 test al,al
 jz .end
 cmp al,'/'
 je .end
 cmp al,32
 jb .bad
 cmp al,127
 je .bad
 inc ecx
 jmp .scan
.end:
 mov edx,ecx
 sub edx,r8d
 jz .bad
 cmp edx,1
 jne .dotdot
 cmp byte [rdi+r8],'.'
 je .bad
.dotdot:
 cmp edx,2
 jne .metadata
 cmp word [rdi+r8],'..'
 je .bad
.metadata:
 cmp edx,4
 jne .continue
 cmp dword [rdi+r8],0x7363762e
 je .bad
.continue:
 test al,al
 jz .good
 inc ecx
 jmp .component
.good: mov eax,1
 ret
.bad: xor eax,eax
 ret
same_name:
 push rcx
 xor ecx,ecx
.loop:
 mov al,[rdi+rcx]
 cmp al,[rsi+rcx]
 jne .no
 test al,al
 jz .yes
 inc ecx
 jmp .loop
.yes: mov eax,1
 pop rcx
 ret
.no: xor eax,eax
 pop rcx
 ret
clear_node:
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret
print_string:
 xor esi,esi
.length:
 cmp byte [rdi+rsi],0
 je emit
 inc rsi
 jmp .length
print_newline:
 lea rdi,[newline]
 mov esi,1
emit:
 jmp [stage_writer]
section .note.GNU-stack noalloc noexec nowrite progbits
