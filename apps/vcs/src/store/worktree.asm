; Atomic forced checkout of regular files. Empty directories are not versioned.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_find,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_object_name
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_format,vcs_repo_last,vcs_object_path
section .bss
checkout_writer: resq 1
checkout_manifest: resq 1
checkout_id: resq 1
active_node: resq 1
active_name: resb 33
active_path: resb 240
checkout_count: resq 1
checkout_nodes: resq VR_FILES
checkout_paths: resb VR_FILES*240
recycle_nodes: resq UV_NODES
recycle_count: resq 1
recycle_used: resq 1
parent_path: resb 240
number: resb 16
section .rodata
checked: db 'Checked out '
checked_len equ $-checked
newline: db 10
digits: db '0123456789abcdef'
active_part: db '/.vcs/active',0
section .text
global vcs_checkout
; rdi=commit ID, rsi=write callback, rdx=branch name or NULL for detached.
; Caller must enforce explicit --force.
vcs_checkout:
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
 mov [checkout_id],rdi
 mov [checkout_writer],rsi
 lea rdi,[active_name]
 xor eax,eax
 mov ecx,33
 rep stosb
 test rdx,rdx
 jz .active_copied
 lea rdi,[active_name]
 mov rsi,rdx
 mov ecx,32
.copy_active:
 lodsb
 stosb
 test al,al
 jz .active_copied
 loop .copy_active
 cmp byte [rsi],0
 jne .usage
.active_copied:
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 mov rdi,[checkout_id]
 cmp rdi,[vcs_repo_last]
 ja .usage
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov [checkout_manifest],rax
 mov rax,[rax+24]
 mov [checkout_count],rax
 call build_active_path
 lea rdi,[active_path]
 call uxv_find
 test rax,rax
 jz .active_missing
 cmp qword [rax+UV_TYPE],1
 jne .conflict
 mov [active_node],rax
 jmp .target_start
.active_missing:
 mov qword [active_node],0
.target_start:
 ; Resolve every target path/blob and require its parent directory.
 xor r12d,r12d
.target:
 cmp r12,[checkout_count]
 jae .recycle
 mov r13,r12
 shl r13,8
 add r13,[checkout_manifest]
 add r13,VR_HEADER
 mov rdi,r12
 call build_path
 test eax,eax
 jnz .corrupt
 mov r14,r12
 imul r14,240
 lea rdi,[checkout_paths+r14]
 call uxv_find
 test rax,rax
 jz .parent
 cmp qword [rax+UV_TYPE],1
 jne .conflict
 jmp .save_node
.parent:
 mov rdi,r12
 call parent_exists
 test eax,eax
 jz .conflict
 xor eax,eax
.save_node:
 lea rdx,[checkout_nodes]
 mov [rdx+r12*8],rax
 inc r12
 jmp .target
.recycle:
 mov qword [recycle_count],0
 mov qword [recycle_used],0
 lea rbx,[uxv_nodes+UV_NODE]
.node:
 cmp qword [rbx+UV_TYPE],0
 je .add_recycle
 cmp qword [rbx+UV_TYPE],1
 jne .node_next
 mov rdi,rbx
 call working_relative
 test rax,rax
 jz .node_next
 mov rdi,rbx
 call target_node
 test eax,eax
 jnz .node_next
.add_recycle:
 mov rax,[recycle_count]
 lea rdx,[recycle_nodes]
 mov [rdx+rax*8],rbx
 inc qword [recycle_count]
.node_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .node
 xor r12d,r12d
 xor r13d,r13d
.count_missing:
 cmp r12,[checkout_count]
 jae .capacity_check
 lea rax,[checkout_nodes]
 cmp qword [rax+r12*8],0
 jne .missing_next
 inc r13
.missing_next:
 inc r12
 jmp .count_missing
.capacity_check:
 cmp byte [active_name],0
 je .capacity_ready
 cmp qword [active_node],0
 jne .capacity_ready
 inc r13
.capacity_ready:
 cmp r13,[recycle_count]
 ja .capacity
 ; Clear extra working files. Free records in the recycle list remain free.
 xor r12d,r12d
.clear_extra:
 cmp r12,[recycle_count]
 jae .write_targets
 lea rax,[recycle_nodes]
 mov rdi,[rax+r12*8]
 cmp qword [rdi+UV_TYPE],0
 je .clear_next
 call clear_node
.clear_next:
 inc r12
 jmp .clear_extra
.write_targets:
 xor r12d,r12d
.write:
 cmp r12,[checkout_count]
 jae .publish
 lea rax,[checkout_nodes]
 mov rbx,[rax+r12*8]
 test rbx,rbx
 jnz .have_node
.take_recycle:
 mov rax,[recycle_used]
 cmp rax,[recycle_count]
 jae .capacity
 lea rdx,[recycle_nodes]
 mov rbx,[rdx+rax*8]
 inc qword [recycle_used]
 ; Skip a recycled node that is also an existing target node.
 mov rdi,rbx
 call target_node
 test eax,eax
 jnz .take_recycle
.have_node:
 mov rdi,rbx
 call clear_node
 mov r14,r12
 imul r14,240
 mov rdi,rbx
 lea rsi,[checkout_paths+r14]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov r13,r12
 shl r13,8
 add r13,[checkout_manifest]
 add r13,VR_HEADER
 mov rcx,[r13+VR_SIZE]
 mov [rbx+UV_SIZE],rcx
 mov rdi,[r13+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 lea rsi,[rax+UV_DATA]
 lea rdi,[rbx+UV_DATA]
 rep movsb
 inc r12
 jmp .write
.publish:
 ; Attach to the selected branch, or remove prior attachment for detached HEAD.
 mov rbx,[active_node]
 cmp byte [active_name],0
 jne .write_active
 test rbx,rbx
 jz .publish_head
 mov rdi,rbx
 call clear_node
 jmp .publish_head
.write_active:
 test rbx,rbx
 jnz .active_have_node
.active_take:
 mov rax,[recycle_used]
 cmp rax,[recycle_count]
 jae .capacity
 lea rdx,[recycle_nodes]
 mov rbx,[rdx+rax*8]
 inc qword [recycle_used]
 mov rdi,rbx
 call target_node
 test eax,eax
 jnz .active_take
.active_have_node:
 mov rdi,rbx
 call clear_node
 mov rdi,rbx
 lea rsi,[active_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 xor ecx,ecx
.active_length:
 cmp byte [active_name+rcx],0
 je .active_length_done
 inc ecx
 jmp .active_length
.active_length_done:
 inc ecx
 mov [rbx+UV_SIZE],rcx
 lea rsi,[active_name]
 lea rdi,[rbx+UV_DATA]
 rep movsb
.publish_head:
 mov rax,[vcs_repo_format]
 mov rdx,[checkout_id]
 mov [rax+UV_DATA+24],rdx
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[checked]
 mov esi,checked_len
 call emit
 mov rdi,[checkout_id]
 call print_id
 call print_newline
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
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

; rdi target index -> absolute path in checkout_paths[index].
build_path:
 mov r8,rdi
 imul r8,240
 ; Validate the combined absolute length before copying untrusted metadata.
 xor edx,edx
.relative_length:
 cmp byte [r13+rdx],0
 je .length_ready
 inc edx
 cmp edx,239
 ja .bad
 jmp .relative_length
.length_ready:
 mov rax,[vcs_repo_root_size]
 add rax,rdx
 cmp qword [vcs_repo_root_size],1
 je .root_length
 inc rax
.root_length:
 cmp rax,239
 ja .bad
 lea rdi,[checkout_paths+r8]
 xor eax,eax
 mov ecx,30
 rep stosq
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[vcs_repo_root]
 lea rdi,[checkout_paths+r8]
 rep movsb
 mov byte [rdi],'/'
 inc rdi
 mov rax,[vcs_repo_root_size]
 cmp rax,1
 jne .length
 dec rdi
.length:
 mov rdx,rdi
 mov rsi,r13
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret
build_active_path:
 lea rdi,[active_path]
 xor eax,eax
 mov ecx,30
 rep stosq
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[vcs_repo_root]
 lea rdi,[active_path]
 rep movsb
 lea rsi,[active_part]
 mov ecx,13
 rep movsb
 ret

; rdi target index; parent must already be a directory.
parent_exists:
 imul rdi,240
 lea rsi,[checkout_paths+rdi]
 lea rdi,[parent_path]
 mov ecx,240
 rep movsb
 lea rdi,[parent_path+239]
.trim:
 cmp byte [rdi],'/'
 je .found
 dec rdi
 lea rax,[parent_path]
 cmp rdi,rax
 jae .trim
 xor eax,eax
 ret
.found:
 lea rax,[parent_path]
 cmp rdi,rax
 jne .zero
 inc rdi
.zero:
 mov byte [rdi],0
 lea rdi,[parent_path]
 call uxv_find
 test rax,rax
 jz .no
 cmp qword [rax+UV_TYPE],2
 jne .no
 mov eax,1
 ret
.no: xor eax,eax
 ret

; rdi=node -> relative pointer or zero; excludes .vcs metadata.
working_relative:
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

; rdi=node -> eax=1 if it is an existing target node.
target_node:
 xor ecx,ecx
.loop:
 cmp rcx,[checkout_count]
 jae .no
 lea rax,[checkout_nodes]
 cmp [rax+rcx*8],rdi
 je .yes
 inc rcx
 jmp .loop
.yes: mov eax,1
 ret
.no: xor eax,eax
 ret
clear_node:
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret
print_id:
 mov r8,rdi
 lea rdi,[number]
 lea r10,[digits]
 mov ecx,16
.loop:
 rol r8,4
 mov rax,r8
 and eax,15
 mov al,[r10+rax]
 stosb
 loop .loop
 lea rdi,[number]
 mov esi,16
 jmp emit
print_newline:
 lea rdi,[newline]
 mov esi,1
emit:
 jmp [checkout_writer]
section .note.GNU-stack noalloc noexec nowrite progbits
