; Recursive Git tree directory planner for bounded VCS manifests.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/git_tree.inc"
%include "include/git_pack.inc"
bits 64
default rel

extern git_object_hash,git_pack_add

section .bss
plan_manifest: resq 1
plan_output: resq 1
plan_capacity: resq 1
plan_count: resq 1
prefix: resb VR_PATH
entry_names: resb GIT_TREE_MAX*VR_PATH

section .text
global git_tree_plan,git_tree_file_parents,git_tree_collect_entries,git_tree_sort_entries,git_tree_emit_entries
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

; Map every manifest file to its planned parent directory.
; RDI=manifest, RSI=plan, RDX=plan count, RCX=VR_FILES-byte output.
; Returns RAX=status. Root files map to zero.
git_tree_file_parents:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .map_usage
 test rsi,rsi
 jz .map_usage
 test rcx,rcx
 jz .map_usage
 test rdx,rdx
 jz .map_usage
 cmp rdx,GIT_TREE_MAX
 ja .map_usage
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 mov r15,[rbp+24]
 cmp r15,VR_FILES
 ja .map_corrupt
 xor ebx,ebx
.map_file:
 cmp rbx,r15
 jae .map_ok
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 xor ecx,ecx
 xor edx,edx
.map_scan:
 cmp rcx,VR_PATH
 jae .map_corrupt
 mov sil,[rax+rcx]
 test sil,sil
 jz .map_scanned
 cmp sil,'/'
 jne .map_next_byte
 lea rdx,[rcx+1]
.map_next_byte:
 inc rcx
 jmp .map_scan
.map_scanned:
 test rcx,rcx
 jz .map_corrupt
 test rdx,rdx
 jz .map_root
 cmp rdx,VR_PATH
 jae .map_corrupt
 lea rsi,[rax]
 lea rdi,[prefix]
 mov rcx,rdx
 rep movsb
 mov byte [prefix+rdx],0
 mov r8d,1
.map_find:
 cmp r8,r13
 jae .map_corrupt
 mov r9,r8
 shl r9,8
 add r9,r12
 xor ecx,ecx
.map_compare:
 mov al,[prefix+rcx]
 cmp al,[r9+GT_PATH+rcx]
 jne .map_find_next
 test al,al
 jz .map_found
 inc rcx
 cmp rcx,VR_PATH
 jb .map_compare
.map_find_next:
 inc r8
 jmp .map_find
.map_found:
 mov [r14+rbx],r8b
 jmp .map_next
.map_root:
 mov byte [r14+rbx],0
.map_next:
 inc rbx
 jmp .map_file
.map_ok: xor eax,eax
 jmp .map_done
.map_usage: mov eax,VCS_ERR_USAGE
 jmp .map_done
.map_corrupt: mov eax,VCS_ERR_CORRUPT
.map_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=GIT_TREE_COLLECT_REQUEST. Returns RDX=direct entry count.
git_tree_collect_entries:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 test rbp,rbp
 jz .collect_usage
 mov r15,[rbp+GTC_CAPACITY]
 test r15,r15
 jz .collect_usage
 xor r12d,r12d
 xor r13d,r13d
 mov rbx,[rbp+GTC_MANIFEST]
 mov r14,[rbx+24]
.collect_file:
 cmp r12,r14
 jae .collect_dirs
 mov rax,[rbp+GTC_FILE_PARENTS]
 movzx ecx,byte [rax+r12]
 cmp rcx,[rbp+GTC_DIRECTORY]
 jne .file_next
 cmp r13,r15
 jae .collect_full
 mov rax,r12
 shl rax,8
 add rax,rbx
 add rax,VR_HEADER
 mov rdi,rax
 xor ecx,ecx
.basename_scan:
 mov dl,[rax]
 test dl,dl
 jz .file_entry
 cmp dl,'/'
 jne .basename_next
 lea rdi,[rax+1]
.basename_next:
 inc rax
 inc ecx
 cmp ecx,VR_PATH
 jb .basename_scan
 jmp .collect_corrupt
.file_entry:
 call collect_slot
 mov [rax+GTE_NAME],rdi
 mov rcx,[rbp+GTC_BLOB_HASHES]
 mov rdx,r12
 imul rdx,GIT_TREE_HASH_SIZE
 add rcx,rdx
 mov [rax+GTE_HASH],rcx
 mov qword [rax+GTE_KIND],GTE_FILE
 inc r13
.file_next:
 inc r12
 jmp .collect_file
.collect_dirs:
 mov r12d,1
.dir_loop:
 cmp r12,[rbp+GTC_PLAN_COUNT]
 jae .collect_sort
 mov rax,r12
 shl rax,8
 add rax,[rbp+GTC_PLAN]
 mov rcx,[rbp+GTC_DIRECTORY]
 cmp [rax+GT_PARENT],rcx
 jne .dir_next
 cmp r13,r15
 jae .collect_full
 mov r14,rax
 mov rdi,r13
 imul rdi,VR_PATH
 lea rdi,[entry_names+rdi]
 call copy_dir_basename
 test eax,eax
 jnz .collect_corrupt
 call collect_slot
 mov [rax+GTE_NAME],rdi
 mov rcx,[rbp+GTC_TREE_HASHES]
 mov rdx,r12
 imul rdx,GIT_TREE_HASH_SIZE
 add rcx,rdx
 mov [rax+GTE_HASH],rcx
 mov qword [rax+GTE_KIND],GTE_DIRECTORY
 inc r13
.dir_next:
 inc r12
 jmp .dir_loop
.collect_sort:
 mov rdi,[rbp+GTC_OUTPUT]
 mov rsi,r13
 call git_tree_sort_entries
 mov rdx,r13
 xor eax,eax
 jmp .collect_done
.collect_usage: mov eax,VCS_ERR_USAGE
 jmp .collect_done
.collect_full: mov eax,VCS_ERR_NO_MEM
 jmp .collect_done
.collect_corrupt: mov eax,VCS_ERR_CORRUPT
.collect_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

collect_slot:
 mov rax,r13
 imul rax,GIT_TREE_ENTRY
 add rax,[rbp+GTC_OUTPUT]
 ret

copy_dir_basename:
 ; R14=plan record, RDI=destination.
 lea rsi,[r14+GT_PATH]
 mov r9,rdi
 xor ecx,ecx
 mov rdx,rsi
.dir_name_scan:
 mov al,[rsi+rcx]
 test al,al
 jz .dir_name_end
 cmp al,'/'
 jne .dir_name_next
 lea rdx,[rsi+rcx+1]
.dir_name_next:
 inc ecx
 cmp ecx,VR_PATH
 jb .dir_name_scan
 mov eax,1
 ret
.dir_name_end:
 cmp rdx,rsi
 je .dir_name_root
 ; Trailing slash made RDX point at NUL; find the preceding component.
 dec rcx
 mov r8,rcx
.dir_name_back:
 test r8,r8
 jz .dir_name_copy
 dec r8
 cmp byte [rsi+r8],'/'
 jne .dir_name_back
 inc r8
.dir_name_copy:
 lea rsi,[rsi+r8]
 sub rcx,r8
 rep movsb
 mov byte [rdi],0
 mov rdi,r9
 xor eax,eax
 ret
.dir_name_root: mov eax,1
 ret

; Canonically sort direct Git tree-entry descriptors in place.
; RDI=array of GIT_TREE_ENTRY records, RSI=count.
git_tree_sort_entries:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r12,rsi
 cmp r12,1
 jbe .sort_ok
 mov r13d,1
.sort_outer:
 cmp r13,r12
 jae .sort_ok
 mov rax,r13
 imul rax,GIT_TREE_ENTRY
 add rax,rbp
 mov r14,[rax+GTE_NAME]
 mov r15,[rax+GTE_HASH]
 mov rbx,[rax+GTE_KIND]
 mov r11,r13
.sort_inner:
 test r11,r11
 jz .sort_place
 mov rax,r11
 dec rax
 imul rax,GIT_TREE_ENTRY
 add rax,rbp
 mov r10,rax
 mov rdi,[rax+GTE_NAME]
 mov rsi,[rax+GTE_KIND]
 mov rdx,r14
 mov rcx,rbx
 call compare_entry_names
 cmp eax,0
 jle .sort_place
 ; Shift the preceding descriptor one slot to the right.
 mov rdx,[r10+GTE_NAME]
 mov rsi,[r10+GTE_HASH]
 mov rdi,[r10+GTE_KIND]
 mov [r10+GIT_TREE_ENTRY+GTE_NAME],rdx
 mov [r10+GIT_TREE_ENTRY+GTE_HASH],rsi
 mov [r10+GIT_TREE_ENTRY+GTE_KIND],rdi
 dec r11
 jmp .sort_inner
.sort_place:
 mov rax,r11
 imul rax,GIT_TREE_ENTRY
 add rax,rbp
 mov [rax+GTE_NAME],r14
 mov [rax+GTE_HASH],r15
 mov [rax+GTE_KIND],rbx
 inc r13
 jmp .sort_outer
.sort_ok:
 xor eax,eax
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Git compares a directory as if its name ended in '/', a file in NUL.
; RDI=name A, RSI=kind A, RDX=name B, RCX=kind B -> signed EAX.
compare_entry_names:
 xor r8d,r8d
.name_byte:
 movzx eax,byte [rdi+r8]
 movzx r9d,byte [rdx+r8]
 test al,al
 jnz .a_ready
 cmp rsi,GTE_DIRECTORY
 jne .a_ready
 mov al,'/'
.a_ready:
 test r9b,r9b
 jnz .b_ready
 cmp rcx,GTE_DIRECTORY
 jne .b_ready
 mov r9b,'/'
.b_ready:
 cmp al,r9b
 jne .different
 test al,al
 jz .equal
 cmp al,'/'
 jne .next_byte
 ; Equal virtual slashes mean identical directory names.
 cmp rsi,GTE_DIRECTORY
 jne .next_byte
 cmp rcx,GTE_DIRECTORY
 je .equal
.next_byte:
 inc r8
 cmp r8,VR_PATH
 jb .name_byte
.equal: xor eax,eax
 ret
.different:
 movzx eax,al
 movzx r9d,r9b
 sub eax,r9d
 ret

; Encode one canonically sorted directory, hash it, and append it to PACK v2.
; RDI=entries, RSI=count, RDX=output, RCX=capacity, R8=32-byte hash output.
; Returns RAX=status, RDX=encoded tree length.
git_tree_emit_entries:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .emit_usage
 test rdx,rdx
 jz .emit_usage
 test r8,r8
 jz .emit_usage
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 mov r15,r8
 xor ebx,ebx
 xor r10d,r10d
.emit_entry:
 cmp rbx,r12
 jae .emit_hash
 mov rax,rbx
 imul rax,GIT_TREE_ENTRY
 add rax,rbp
 mov r9,rax
 cmp qword [rax+GTE_KIND],GTE_DIRECTORY
 je .emit_directory
 lea rsi,[tree_file_mode]
 mov ecx,tree_file_mode_len
 jmp .emit_mode
.emit_directory:
 lea rsi,[tree_directory_mode]
 mov ecx,tree_directory_mode_len
.emit_mode:
 mov r11,rcx
 mov rax,r10
 add rax,rcx
 cmp rax,r14
 ja .emit_space
 lea rdi,[r13+r10]
 rep movsb
 add r10,r11
 mov rsi,[r9+GTE_NAME]
 xor ecx,ecx
.emit_name_length:
 cmp ecx,VR_PATH
 jae .emit_corrupt
 cmp byte [rsi+rcx],0
 je .emit_name_ready
 inc ecx
 jmp .emit_name_length
.emit_name_ready:
 test ecx,ecx
 jz .emit_corrupt
 mov r11,rcx
 mov rax,r10
 add rax,rcx
 add rax,1+GIT_HASH_SIZE
 cmp rax,r14
 ja .emit_space
 lea rdi,[r13+r10]
 rep movsb
 add r10,r11
 mov byte [r13+r10],0
 inc r10
 mov rsi,[r9+GTE_HASH]
 lea rdi,[r13+r10]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 add r10,GIT_HASH_SIZE
 inc rbx
 jmp .emit_entry
.emit_hash:
 lea rdi,[tree_object_type]
 mov esi,4
 mov rdx,r13
 mov rcx,r10
 mov r8,r15
 call git_object_hash
 test eax,eax
 jnz .emit_done
 mov edi,GIT_PACK_TREE
 mov rsi,r13
 mov rdx,r10
 call git_pack_add
 test eax,eax
 jnz .emit_done
 mov rdx,r10
 xor eax,eax
 jmp .emit_done
.emit_usage: mov eax,VCS_ERR_USAGE
 jmp .emit_done
.emit_space: mov eax,VCS_ERR_NO_MEM
 jmp .emit_done
.emit_corrupt: mov eax,VCS_ERR_CORRUPT
.emit_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

section .rodata
tree_file_mode: db '100644 '
tree_file_mode_len equ $-tree_file_mode
tree_directory_mode: db '40000 '
tree_directory_mode_len equ $-tree_directory_mode
tree_object_type: db 'tree'

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
