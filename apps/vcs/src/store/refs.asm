; Local branch/tag refs over validated commit IDs. Serialized with UXFS owner.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_find,uxv_commit
extern vcs_repo_discover,vcs_load_manifest
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head
extern vcs_active_ref_node
section .bss
ref_writer: resq 1
ref_path: resb 240
ref_prefix: resb 240
ref_number: resb 16
section .rodata
branch_part: db '/.vcs/rh.',0
tag_part: db '/.vcs/rt.',0
branch_text: db 'branch '
branch_text_len equ $-branch_text
tag_text: db 'tag '
tag_text_len equ $-tag_text
created_text: db 'Created '
created_text_len equ $-created_text
deleted_text: db 'Deleted '
deleted_text_len equ $-deleted_text
space: db ' '
newline: db 10
digits: db '0123456789abcdef'
section .text
global vcs_ref
; op: 0 create branch, 1 create tag, 2 list, 3 delete branch, 4 delete tag,
; 5 resolve branch. Resolve returns the commit ID in rdx.
; rsi=name (unused for list), rdx=commit or zero for HEAD, rcx=write callback.
vcs_ref:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,5
 ja .usage
 test rcx,rcx
 jz .usage
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov [ref_writer],rcx
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 cmp rbp,2
 je .list
 test r12,r12
 jz .usage
 mov rdi,r12
 call valid_name
 test eax,eax
 jz .usage
 mov rdi,rbp
 call make_path
 test eax,eax
 jnz .usage
 lea rdi,[ref_path]
 call uxv_find
 cmp rbp,5
 je .resolve
 cmp rbp,3
 jae .delete
 test rax,rax
 jnz .conflict
 test r13,r13
 jnz .target
 mov r13,[vcs_repo_head]
.target:
 test r13,r13
 jz .usage
 mov rdi,r13
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 call free_node
 test rax,rax
 jz .capacity
 mov rbx,rax
 call clear_node
 mov rdi,rbx
 lea rsi,[ref_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],8
 mov [rbx+UV_DATA],r13
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[created_text]
 mov esi,created_text_len
 call emit
 mov rdi,rbp
 call print_kind
 mov rdi,r12
 call print_string
 call print_newline
 jmp .ok
.resolve:
 test rax,rax
 jz .missing
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],8
 jne .corrupt
 mov r13,[rax+UV_DATA]
 test r13,r13
 jz .corrupt
 mov rdi,r13
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 xor eax,eax
 mov rdx,r13
 jmp .done
.delete:
 test rax,rax
 jz .missing
 cmp rbp,3
 jne .delete_not_active
 cmp rax,[vcs_active_ref_node]
 je .conflict
.delete_not_active:
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],8
 jne .corrupt
 mov rbx,rax
 call clear_node
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[deleted_text]
 mov esi,deleted_text_len
 call emit
 mov rdi,rbp
 call print_kind
 mov rdi,r12
 call print_string
 call print_newline
 jmp .ok
.list:
 ; Validate every ref and target before emitting partial output.
 xor r14d,r14d
.list_validate_kind:
 mov rdi,r14
 call make_prefix
 lea rbx,[uxv_nodes+UV_NODE]
.validate_node:
 cmp qword [rbx+UV_TYPE],1
 jne .validate_next
 mov rdi,rbx
 lea rsi,[ref_prefix]
 call has_prefix
 test eax,eax
 jz .validate_next
 cmp qword [rbx+UV_SIZE],8
 jne .corrupt
 mov rdi,[rbx+UV_DATA]
 test rdi,rdi
 jz .corrupt
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
.validate_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .validate_node
 inc r14
 cmp r14,2
 jb .list_validate_kind
 xor r14d,r14d
.list_print_kind:
 mov rdi,r14
 call make_prefix
 lea rbx,[uxv_nodes+UV_NODE]
.print_node:
 cmp qword [rbx+UV_TYPE],1
 jne .print_next
 mov rdi,rbx
 lea rsi,[ref_prefix]
 call has_prefix
 test eax,eax
 jz .print_next
 mov rdi,r14
 call print_kind
 lea rdi,[rbx]
 call suffix_pointer
 call print_string
 lea rdi,[space]
 mov esi,1
 call emit
 mov rdi,[rbx+UV_DATA]
 call print_id
 call print_newline
.print_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .print_node
 inc r14
 cmp r14,2
 jb .list_print_kind
.ok: xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
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

valid_name:
 xor ecx,ecx
.loop:
 movzx edx,byte [rdi+rcx]
 test dl,dl
 jz .end
 cmp ecx,31
 jae .bad
 cmp dl,'-'
 je .good_char
 cmp dl,'.'
 je .good_char
 cmp dl,'_'
 je .good_char
 cmp dl,'0'
 jb .bad
 cmp dl,'9'
 jbe .good_char
 or dl,32
 cmp dl,'a'
 jb .bad
 cmp dl,'z'
 ja .bad
.good_char:
 inc ecx
 jmp .loop
.end:
 test ecx,ecx
 jz .bad
 cmp byte [rdi],'.'
 je .bad
 mov eax,1
 ret
.bad: xor eax,eax
 ret

; rdi op; construct full ref path and prefix.
make_path:
 push rbx
 mov rbx,rdi
 xor ecx,ecx
.name_length:
 cmp byte [r12+rcx],0
 je .name_ready
 inc ecx
 jmp .name_length
.name_ready:
 mov rax,[vcs_repo_root_size]
 cmp rax,1
 jne .bound
 xor eax,eax
.bound:
 add rax,9                       ; '/.vcs/r?.'
 add rax,rcx
 cmp rax,239
 ja .bad
 xor edi,edi
 cmp ebx,1
 je .tag
 cmp ebx,4
 jne .kind_ready
.tag: mov edi,1
.kind_ready:
 call make_prefix
 lea rdi,[ref_path]
 lea rsi,[ref_prefix]
.copy_prefix:
 lodsb
 stosb
 test al,al
 jnz .copy_prefix
 dec rdi
 mov rsi,r12
.copy_name:
 lodsb
 stosb
 test al,al
 jnz .copy_name
 xor eax,eax
 pop rbx
 ret
.bad:
 mov eax,VCS_ERR_USAGE
 pop rbx
 ret

; rdi kind: 0 branch, 1 tag.
make_prefix:
 push rbx
 mov rbx,rdi
 lea rdi,[ref_prefix]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[vcs_repo_root]
 lea rdi,[ref_prefix]
 rep movsb
 lea rsi,[branch_part]
 test rbx,rbx
 jz .part
 lea rsi,[tag_part]
.part:
 mov ecx,10
 rep movsb
 pop rbx
 ret

has_prefix:
 xor ecx,ecx
.loop:
 mov al,[rsi+rcx]
 test al,al
 jz .yes
 cmp al,[rdi+rcx]
 jne .no
 inc ecx
 jmp .loop
.yes: mov eax,1
 ret
.no: xor eax,eax
 ret
suffix_pointer:
 lea rsi,[ref_prefix]
.skip:
 cmp byte [rsi],0
 je .done
 inc rsi
 inc rdi
 jmp .skip
.done: ret
free_node:
 lea rax,[uxv_nodes+UV_NODE]
 mov ecx,UV_NODES-1
.scan:
 cmp qword [rax+UV_TYPE],0
 je .done
 add rax,UV_NODE
 loop .scan
 xor eax,eax
.done: ret
clear_node:
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret
print_kind:
 cmp edi,1
 je .tag
 cmp edi,4
 sete dil
 movzx edi,dil
.tag:
 lea rax,[branch_text]
 mov esi,branch_text_len
 test edi,edi
 jz .emit
 lea rax,[tag_text]
 mov esi,tag_text_len
.emit:
 mov rdi,rax
 jmp emit
print_id:
 mov r8,rdi
 lea rdi,[ref_number]
 lea r10,[digits]
 mov ecx,16
.loop:
 rol r8,4
 mov rax,r8
 and eax,15
 mov al,[r10+rax]
 stosb
 loop .loop
 lea rdi,[ref_number]
 mov esi,16
 jmp emit
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
 jmp [ref_writer]
section .note.GNU-stack noalloc noexec nowrite progbits
