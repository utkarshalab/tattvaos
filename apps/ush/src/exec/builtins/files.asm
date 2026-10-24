; Real UXFS volume commands. No simulated VFS or host filesystem passthrough.
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_mount,uxv_ready,uxv_nodes,uxv_cwd,uxv_find,uxv_free
extern uxv_normalize,uxv_commit,frontend_write_str,frontend_write
section .bss
global fs_path
fs_path:
path1: resb 240
path2: resb 240
rename_paths: resb UV_NODES*240
rename_cwd: resb 240
section .rodata
unavailable: db 'ush: no valid UXFS v2 data volume mounted',10,0
failure: db 'ush: filesystem operation failed (path, type, capacity, or destination conflict)',10,0
io_failure: db 'ush: storage I/O failed; volume disabled until remount',10,0
newline: db 10,0
slash: db '/',0
section .text
global cmd_pwd,cmd_ls,cmd_cd,cmd_cat,cmd_touch,cmd_mkdir,cmd_cp,cmd_mv,cmd_write
global cmd_rm,cmd_rmdir,cmd_append,fs_resolve,fs_belongs
cmd_pwd: xor edx,edx
 jmp command
cmd_ls: mov edx,1
 jmp command
cmd_cd: mov edx,2
 jmp command
cmd_cat: mov edx,3
 jmp command
cmd_touch: mov edx,4
 jmp command
cmd_mkdir: mov edx,5
 jmp command
cmd_cp: mov edx,6
 jmp command
cmd_mv: mov edx,7
 jmp command
cmd_write: mov edx,8
 jmp command
cmd_rm: mov edx,9
 jmp command
cmd_rmdir: mov edx,10
 jmp command
cmd_append: mov edx,11
 jmp command
; path -> record or zero; canonical path is published in fs_path.
fs_resolve:
 sub rsp,8
 lea rsi,[path1]
 call uxv_normalize
 test rax,rax
 js .bad
 lea rdi,[path1]
 call uxv_find
 add rsp,8
 ret
.bad:
 xor eax,eax
 add rsp,8
 ret
; Is canonical candidate rdi equal to/inside canonical directory rsi?
; Both pointers are preserved. A slash boundary excludes same-prefix siblings.
fs_belongs:
 cmp word [rsi],'/'
 je .yes
 xor ecx,ecx
.prefix:
 mov al,[rsi+rcx]
 test al,al
 jz .boundary
 cmp al,[rdi+rcx]
 jne .no
 inc ecx
 jmp .prefix
.boundary:
 cmp byte [rdi+rcx],0
 je .yes
 cmp byte [rdi+rcx],'/'
 je .yes
.no: xor eax,eax
 ret
.yes: mov eax,1
 ret
command:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdx
 mov r13,rsi
 mov r14,rdi
 cmp qword [uxv_ready],1
 jne .unavailable
 test r12,r12
 jz .pwd
 lea rdi,[uxv_cwd]
 cmp r14,1
 je .normalize
 mov rdi,[r13+8]
.normalize:
 lea rsi,[path1]
 call uxv_normalize
 test rax,rax
 js .bad
 lea rdi,[path1]
 call uxv_find
 mov rbx,rax
 cmp r12,4
 jae .mutation
 test rbx,rbx
 jz .bad
 cmp r12,3
 je .cat
 cmp qword [rbx+UV_TYPE],2
 jne .bad
 cmp r12,2
 je .cd
 ; ls: direct children only, one name per line, directory suffix '/'.
 lea r15,[uxv_nodes+UV_NODE]
.list:
 cmp qword [r15+UV_TYPE],0
 je .next
 lea rsi,[path1]
 mov rdi,r15
.prefix:
 mov al,[rsi]
 test al,al
 jz .boundary
 cmp al,[rdi]
 jne .next
 inc rsi
 inc rdi
 jmp .prefix
.boundary:
 cmp word [path1],'/'
 je .child
 cmp byte [rdi],'/'
 jne .next
 inc rdi
.child:
 cmp byte [rdi],0
 je .next
 mov rdx,rdi
.scan:
 cmp byte [rdx],'/'
 je .next
 cmp byte [rdx],0
 je .print
 inc rdx
 jmp .scan
.print:
 call frontend_write_str
 cmp qword [r15+UV_TYPE],2
 jne .nl
 lea rdi,[slash]
 call frontend_write_str
.nl:
 lea rdi,[newline]
 call frontend_write_str
.next:
 add r15,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp r15,rax
 jb .list
 jmp .success
.pwd:
 lea rdi,[uxv_cwd]
 call frontend_write_str
 lea rdi,[newline]
 call frontend_write_str
 jmp .success
.cd:
 lea rsi,[path1]
 lea rdi,[uxv_cwd]
 mov ecx,240
 rep movsb
 jmp .success
.cat:
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 lea rdi,[rbx+UV_DATA]
 mov rsi,[rbx+UV_SIZE]
 call frontend_write
 jmp .success
.mutation:
 cmp r12,9
 je .remove
 cmp r12,10
 je .remove
 cmp r12,11
 je .write
 cmp r12,6
 je .two_paths
 cmp r12,7
 je .two_paths
 cmp r12,8
 je .write
 test rbx,rbx
 jz .create
 cmp r12,4
 jne .bad
 ; touch preserves existing contents; timestamps are not yet represented.
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 jmp .success
.create:
 call uxv_free
 test rax,rax
 jz .bad
 mov rbx,rax
 mov rdi,rax
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 mov rdi,rbx
 lea rsi,[path1]
 mov ecx,240
 rep movsb
 mov eax,1
 cmp r12,5
 jne .type
 inc eax
.type:
 mov [rbx+UV_TYPE],rax
 jmp .commit
.write:
 ; Validate the full content length before creating or modifying any record.
 mov rsi,[r13+16]
 xor r15d,r15d
.length:
 cmp byte [rsi+r15],0
 je .write_ready
 inc r15d
 cmp r15d,4096
 jbe .length
 jmp .bad
.write_ready:
 test rbx,rbx
 jz .write_allocate
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 cmp r12,11
 jne .write_allocate
 mov rax,[rbx+UV_SIZE]
 add rax,r15
 cmp rax,4096
 ja .bad
.write_allocate:
 test rbx,rbx
 jnz .write_existing
 call uxv_free
 test rax,rax
 jz .bad
 mov rbx,rax
 mov rdi,rax
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 lea rsi,[path1]
 mov rdi,rbx
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
.write_existing:
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 lea rdi,[rbx+UV_DATA]
 xor edx,edx
 cmp r12,11
 jne .write_copy
 mov rdx,[rbx+UV_SIZE]
 add rdi,rdx
.write_copy:
 mov rsi,[r13+16]
 mov rcx,r15
 rep movsb
 add r15,rdx
 mov [rbx+UV_SIZE],r15
 jmp .commit
.remove:
 test rbx,rbx
 jz .bad
 cmp r12,10
 je .remove_directory
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 jmp .erase
.remove_directory:
 cmp qword [rbx+UV_TYPE],2
 jne .bad
 cmp word [path1],'/'
 je .bad
 lea rdi,[uxv_cwd]
 lea rsi,[path1]
 call fs_belongs
 test eax,eax
 jnz .bad
 lea r15,[uxv_nodes+UV_NODE]
.children:
 cmp r15,rbx
 je .child_next
 cmp qword [r15+UV_TYPE],0
 je .child_next
 mov rdi,r15
 lea rsi,[path1]
 call fs_belongs
 test eax,eax
 jnz .bad
.child_next:
 add r15,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp r15,rax
 jb .children
.erase:
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 jmp .commit
.two_paths:
 test rbx,rbx
 jz .bad
 cmp r12,7
 je .destination
 cmp qword [rbx+UV_TYPE],1
 jne .bad
.destination:
 mov rdi,[r13+16]
 lea rsi,[path2]
 call uxv_normalize
 test rax,rax
 js .bad
 lea rdi,[path2]
 call uxv_find
 ; Refuse overwrite and same-file operations; failed commands change nothing.
 test rax,rax
 jnz .bad
 cmp r12,7
 jne .copy_file
 cmp qword [rbx+UV_TYPE],2
 je .rename_directory
 jmp .rename
.copy_file:
 call uxv_free
 test rax,rax
 jz .bad
 mov rdi,rax
 mov r15,rax
 mov rsi,rbx
 mov ecx,UV_NODE/8
 rep movsq
 mov rbx,r15
.rename:
 mov rdi,rbx
 lea rsi,[path2]
 mov ecx,240
 rep movsb
 jmp .commit
.rename_directory:
 ; Preflight all descendant paths and cwd before changing any record.
 cmp word [path1],'/'
 je .bad
 xor r14d,r14d
 xor r15d,r15d
.source_length:
 cmp byte [path1+r14],0
 je .destination_length
 inc r14
 jmp .source_length
.destination_length:
 cmp byte [path2+r15],0
 je .check_subtree
 inc r15
 jmp .destination_length
.check_subtree:
 xor ecx,ecx
.inside:
 cmp rcx,r14
 je .boundary_check
 mov al,[path1+rcx]
 cmp al,[path2+rcx]
 jne .preflight
 inc rcx
 jmp .inside
.boundary_check:
 cmp byte [path2+r14],'/'
 je .bad
 cmp byte [path2+r14],0
 je .bad
.preflight:
 xor ebx,ebx
.candidate:
 imul rax,rbx,UV_NODE
 lea rdi,[uxv_nodes+rax]
 cmp qword [rdi+UV_TYPE],0
 je .candidate_next
 imul rax,rbx,240
 lea rsi,[rename_paths+rax]
 call renamed_path
 test eax,eax
 js .bad
 jz .candidate_next
 imul rax,rbx,240
 lea rdi,[rename_paths+rax]
 call uxv_find
 test rax,rax
 jnz .bad
.candidate_next:
 inc ebx
 cmp ebx,UV_NODES
 jb .candidate
 lea rdi,[uxv_cwd]
 lea rsi,[rename_cwd]
 call renamed_path
 test eax,eax
 js .bad
 xor ebx,ebx
.apply:
 imul rax,rbx,UV_NODE
 lea rdi,[uxv_nodes+rax]
 cmp qword [rdi+UV_TYPE],0
 je .apply_next
 imul rax,rbx,240
 lea rsi,[rename_paths+rax]
 mov ecx,240
 rep movsb
.apply_next:
 inc ebx
 cmp ebx,UV_NODES
 jb .apply
 lea rsi,[rename_cwd]
 lea rdi,[uxv_cwd]
 mov ecx,240
 rep movsb
.commit:
 call uxv_commit
 test rax,rax
 jns .success
 lea rdi,[io_failure]
 jmp .error
.unavailable:
 lea rdi,[unavailable]
 jmp .error
.bad:
 lea rdi,[failure]
.error:
 call frontend_write_str
 mov eax,1
 jmp .done
.success:
 xor eax,eax
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; Preflight replacement helper. r14/r15=source/destination lengths.
; Returns 1 replaced, 0 unchanged, -1 too long. No metadata mutations.
renamed_path:
 mov r10,rdi
 mov r11,rsi
 xor ecx,ecx
.compare:
 cmp rcx,r14
 je .boundary
 mov al,[rdi+rcx]
 cmp al,[path1+rcx]
 jne .unchanged
 inc rcx
 jmp .compare
.boundary:
 cmp byte [rdi+rcx],0
 je .replace
 cmp byte [rdi+rcx],'/'
 jne .unchanged
.replace:
 mov rdx,r14
.length:
 cmp byte [r10+rdx],0
 je .fits
 inc rdx
 jmp .length
.fits:
 sub rdx,r14
 lea rax,[rdx+r15]
 cmp rax,239
 ja .too_long
 mov rdi,r11
 lea rsi,[path2]
 mov rcx,r15
 rep movsb
 lea rsi,[r10+r14]
 lea rcx,[rdx+1]
 rep movsb
 mov eax,1
 ret
.unchanged:
 mov rsi,r10
 mov rdi,r11
 mov ecx,240
 rep movsb
 xor eax,eax
 ret
.too_long:
 mov eax,-1
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
