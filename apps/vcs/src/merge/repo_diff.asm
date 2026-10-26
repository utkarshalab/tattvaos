; Repository-aware tree/index/worktree diff over the existing exact line engine.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/diff.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_nodes,uxv_find
extern vcs_repo_discover,vcs_load_manifest,vcs_object_name,vcs_path_ignored
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head,vcs_object_path
extern diff_files

%define RD_MAX 30
%define RD_ENTRY 288
%define RD_OLD 240
%define RD_OLD_SIZE 248
%define RD_NEW 256
%define RD_NEW_SIZE 264
%define RD_OLD_PRESENT 272
%define RD_NEW_PRESENT 280

section .bss
repo_writer: resq 1
repo_count: resq 1
repo_changed: resq 1
repo_entries: resb RD_MAX*RD_ENTRY
repo_request: resb vcs_diff_request_size
repo_scratch: resb VCS_DIFF_SCRATCH
repo_records: resb 512*vcs_diff_record_size
repo_rendered: resb 4096*4+2
repo_path: resb 240

section .rodata
index_suffix: db '/.vcs/index',0
index_magic: db 'UVCSIDX1'
old_header: db '--- '
old_header_len equ $-old_header
new_header: db '+++ '
new_header_len equ $-new_header
old_prefix: db 'a/'
new_prefix: db 'b/'
null_name: db '/dev/null'
null_name_len equ $-null_name
newline: db 10
no_newline: db 10,'\ No newline at end of file',10
no_newline_len equ $-no_newline
prefixes: db ' -+'
hex: db '0123456789abcdef'

section .text
global vcs_repo_diff
; op 0 working tree versus HEAD, 1 staged projection versus HEAD,
; 2 commit rsi versus commit rdx. rcx=write(bytes,length).
; RAX=0 identical, 1 different, or a VCS_ERR_* value greater than 1.
vcs_repo_diff:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,2
 ja .usage
 test rcx,rcx
 jz .usage
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov [repo_writer],rcx
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 mov qword [repo_count],0
 mov qword [repo_changed],0
 lea rdi,[repo_entries]
 xor eax,eax
 mov ecx,(RD_MAX*RD_ENTRY)/8
 rep stosq
 cmp rbp,2
 je .commits
 xor r14d,r14d
 mov rdi,[vcs_repo_head]
 test rdi,rdi
 jz .head_ready
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r14,rax
.head_ready:
 cmp rbp,1
 je .staged
 test r14,r14
 jz .working
 mov rdi,r14
 xor esi,esi
 call add_manifest
 test eax,eax
 jnz .done
.working:
 call add_worktree
 test eax,eax
 jnz .done
 jmp .render

.staged:
 mov rdi,r14
 call add_index
 test eax,eax
 jnz .done
 jmp .render

.commits:
 test r12,r12
 jz .usage
 test r13,r13
 jz .usage
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r14,rax
 mov rdi,r13
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r15,rax
 mov rdi,r14
 xor esi,esi
 call add_manifest
 test eax,eax
 jnz .done
 mov rdi,r15
 mov esi,1
 call add_manifest
 test eax,eax
 jnz .done

.render:
 xor r12d,r12d
.render_loop:
 cmp r12,[repo_count]
 jae .render_done
 mov rax,r12
 imul rax,RD_ENTRY
 lea rbx,[repo_entries+rax]
 call entry_equal
 test eax,eax
 jnz .render_next
 inc qword [repo_changed]
 mov rdi,rbx
 call render_entry
 test eax,eax
 jnz .done
.render_next:
 inc r12
 jmp .render_loop
.render_done:
 xor eax,eax
 cmp qword [repo_changed],0
 setne al
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

; RDI=validated manifest, ESI=0 old or 1 new.
add_manifest:
 push rbx
 push r12
 push r13
 push r14
 sub rsp,8
 mov r12,rdi
 mov r13,rsi
 mov r14,[r12+24]
 add r12,VR_HEADER
.loop:
 test r14,r14
 jz .ok
 mov rdi,r12
 call find_or_add
 test rax,rax
 jz .full
 mov rbx,rax
 mov rdi,[r12+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .bad
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 test r13,r13
 jnz .new
 lea rdx,[rax+UV_DATA]
 mov [rbx+RD_OLD],rdx
 mov rdx,[rax+UV_SIZE]
 mov [rbx+RD_OLD_SIZE],rdx
 mov qword [rbx+RD_OLD_PRESENT],1
 jmp .next
.new:
 lea rdx,[rax+UV_DATA]
 mov [rbx+RD_NEW],rdx
 mov rdx,[rax+UV_SIZE]
 mov [rbx+RD_NEW_SIZE],rdx
 mov qword [rbx+RD_NEW_PRESENT],1
.next:
 add r12,VR_ENTRY
 dec r14
 jmp .loop
.ok: xor eax,eax
 jmp .done
.full: mov eax,VCS_ERR_NO_MEM
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

add_worktree:
 push rbx
 push r12
 sub rsp,8
 lea rbx,[uxv_nodes+UV_NODE]
.node:
 cmp qword [rbx+UV_TYPE],1
 jne .next
 mov rdi,rbx
 call working_relative
 test rax,rax
 jz .next
 mov r12,rax
 mov rdi,r12
 call metadata_component
 test eax,eax
 jnz .next
 mov rdi,r12
 call vcs_path_ignored
 test eax,eax
 jnz .next
 mov rdi,r12
 call find_or_add
 test rax,rax
 jz .full
 lea rdx,[rbx+UV_DATA]
 mov [rax+RD_NEW],rdx
 mov rdx,[rbx+UV_SIZE]
 mov [rax+RD_NEW_SIZE],rdx
 mov qword [rax+RD_NEW_PRESENT],1
.next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .node
 xor eax,eax
 jmp .done
.full: mov eax,VCS_ERR_NO_MEM
.done:
 add rsp,8
 pop r12
 pop rbx
 ret

; RDI=HEAD manifest or zero. Only indexed paths enter the pair set.
add_index:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r15,rdi
 call make_index_path
 lea rdi,[repo_path]
 call uxv_find
 test rax,rax
 jz .ok
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rbx,rax
 mov rcx,[rbx+UV_SIZE]
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
 test rax,rax
 jz .bad
 cmp [rbx+UV_DATA+8],rax
 jne .bad
 mov rdx,0x3158444953435655
 cmp [rbx+UV_DATA],rdx
 jne .bad
 mov r14,rax
 lea r13,[rbx+UV_DATA+16]
.path:
 test r14,r14
 jz .ok
 mov rdi,r13
 call valid_relative
 test eax,eax
 jz .bad
 lea rdx,[rbx+UV_DATA+16]
.unique:
 cmp rdx,r13
 jae .unique_done
 mov rdi,r13
 mov rsi,rdx
 call same_name
 test eax,eax
 jnz .bad
 add rdx,240
 jmp .unique
.unique_done:
 mov rdi,r13
 call find_or_add
 test rax,rax
 jz .full
 mov r12,rax
 mov rdi,r13
 mov rsi,r15
 call manifest_span
 test eax,eax
 js .bad
 test eax,eax
 jz .working
 mov [r12+RD_OLD],rdx
 mov [r12+RD_OLD_SIZE],rcx
 mov qword [r12+RD_OLD_PRESENT],1
.working:
 mov rdi,r13
 call make_work_path
 test eax,eax
 jnz .bad
 lea rdi,[repo_path]
 call uxv_find
 test rax,rax
 jz .path_next
 cmp qword [rax+UV_TYPE],1
 jne .bad
 lea rdx,[rax+UV_DATA]
 mov [r12+RD_NEW],rdx
 mov rdx,[rax+UV_SIZE]
 mov [r12+RD_NEW_SIZE],rdx
 mov qword [r12+RD_NEW_PRESENT],1
.path_next:
 add r13,240
 dec r14
 jmp .path
.ok: xor eax,eax
 jmp .done
.full: mov eax,VCS_ERR_NO_MEM
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=path, RSI=manifest or zero. EAX=1 found, 0 absent, -1 corrupt.
; RDX=data pointer, RCX=size.
manifest_span:
 sub rsp,8
 test rsi,rsi
 jz .absent
 mov r8,rdi
 mov r9,[rsi+24]
 add rsi,VR_HEADER
.find:
 test r9,r9
 jz .absent
 mov rdi,r8
 call same_name
 test eax,eax
 jnz .found
 add rsi,VR_ENTRY
 dec r9
 jmp .find
.found:
 mov rdi,[rsi+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .bad
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 lea rdx,[rax+UV_DATA]
 mov rcx,[rax+UV_SIZE]
 mov eax,1
 jmp .done
.absent: xor eax,eax
 jmp .done
.bad: mov rax,-1
.done:
 add rsp,8
 ret

find_or_add:
 push rbx
 mov rbx,rdi
 xor ecx,ecx
.find:
 cmp rcx,[repo_count]
 jae .append
 mov rax,rcx
 imul rax,RD_ENTRY
 lea rsi,[repo_entries+rax]
 mov rdi,rbx
 call same_name
 test eax,eax
 jnz .found
 inc rcx
 jmp .find
.append:
 cmp rcx,RD_MAX
 jae .full
 mov rax,rcx
 imul rax,RD_ENTRY
 lea rax,[repo_entries+rax]
 mov rdi,rax
 mov rsi,rbx
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 inc qword [repo_count]
 pop rbx
 ret
.found:
 mov rax,rsi
 pop rbx
 ret
.full:
 xor eax,eax
 pop rbx
 ret

entry_equal:
 mov rax,[rbx+RD_OLD_PRESENT]
 cmp rax,[rbx+RD_NEW_PRESENT]
 jne .no
 test rax,rax
 jz .yes
 mov rcx,[rbx+RD_OLD_SIZE]
 cmp rcx,[rbx+RD_NEW_SIZE]
 jne .no
 mov rsi,[rbx+RD_OLD]
 mov rdi,[rbx+RD_NEW]
 repe cmpsb
 jne .no
.yes: mov eax,1
 ret
.no: xor eax,eax
 ret

render_entry:
 push rbx
 push r12
 sub rsp,8
 mov r12,rdi
 lea rdi,[old_header]
 mov esi,old_header_len
 call emit
 cmp qword [r12+RD_OLD_PRESENT],0
 je .old_null
 lea rdi,[old_prefix]
 mov esi,2
 call emit
 mov rdi,r12
 call print_string
 jmp .old_end
.old_null:
 lea rdi,[null_name]
 mov esi,null_name_len
 call emit
.old_end:
 call print_newline
 lea rdi,[new_header]
 mov esi,new_header_len
 call emit
 cmp qword [r12+RD_NEW_PRESENT],0
 je .new_null
 lea rdi,[new_prefix]
 mov esi,2
 call emit
 mov rdi,r12
 call print_string
 jmp .new_end
.new_null:
 lea rdi,[null_name]
 mov esi,null_name_len
 call emit
.new_end:
 call print_newline
 mov rax,[r12+RD_OLD]
 mov [repo_request+vcs_diff_request.old],rax
 mov rax,[r12+RD_OLD_SIZE]
 mov [repo_request+vcs_diff_request.old_size],rax
 mov rax,[r12+RD_NEW]
 mov [repo_request+vcs_diff_request.new],rax
 mov rax,[r12+RD_NEW_SIZE]
 mov [repo_request+vcs_diff_request.new_size],rax
 lea rax,[repo_scratch]
 mov [repo_request+vcs_diff_request.scratch],rax
 mov qword [repo_request+vcs_diff_request.scratch_size],VCS_DIFF_SCRATCH
 lea rax,[repo_records]
 mov [repo_request+vcs_diff_request.output],rax
 mov qword [repo_request+vcs_diff_request.capacity],512
 lea rdi,[repo_request]
 call diff_files
 test eax,eax
 jnz .bad
 mov r12,rdx
 lea rbx,[repo_records]
.record:
 test r12,r12
 jz .ok
 mov rax,[rbx+vcs_diff_record.kind]
 lea rdx,[prefixes]
 mov dl,[rdx+rax]
 lea rdi,[repo_rendered]
 mov [rdi],dl
 inc rdi
 mov rsi,[repo_request+vcs_diff_request.old]
 add rsi,[rbx+vcs_diff_record.old_offset]
 cmp eax,VCS_DIFF_INSERT
 jne .bytes
 mov rsi,[repo_request+vcs_diff_request.new]
 add rsi,[rbx+vcs_diff_record.new_offset]
.bytes:
 mov rcx,[rbx+vcs_diff_record.length]
 push rcx
 push rsi
 lea r8,[hex]
.byte:
 lodsb
 cmp al,10
 je .literal
 cmp al,32
 jb .escape
 cmp al,126
 ja .escape
 cmp al,92
 je .escape
.literal:
 stosb
 jmp .next_byte
.escape:
 mov byte [rdi],92
 mov byte [rdi+1],'x'
 movzx edx,al
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi+2],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+3],al
 add rdi,4
.next_byte:
 loop .byte
 mov rsi,rdi
 lea rdi,[repo_rendered]
 sub rsi,rdi
 call emit
 pop rsi
 pop rcx
 cmp byte [rsi+rcx-1],10
 je .next_record
 lea rdi,[no_newline]
 mov esi,no_newline_len
 call emit
.next_record:
 add rbx,vcs_diff_record_size
 dec r12
 jmp .record
.ok: xor eax,eax
 jmp .done
.bad: mov eax,VCS_ERR_NO_MEM
.done:
 add rsp,8
 pop r12
 pop rbx
 ret

working_relative:
 mov rax,rdi
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 lea rdi,[vcs_repo_root]
 mov rsi,rax
 repe cmpsb
 jne .no
 cmp byte [rsi],'/'
 jne .no
 lea rax,[rsi+1]
 ret
.root:
 cmp byte [rax],'/'
 jne .no
 inc rax
 cmp byte [rax],0
 je .no
 ret
.no: xor eax,eax
 ret

metadata_component:
 xor ecx,ecx
.component:
 mov edx,ecx
.scan:
 mov al,[rdi+rcx]
 test al,al
 jz .end
 cmp al,'/'
 je .end
 inc ecx
 cmp ecx,240
 jb .scan
 mov eax,1
 ret
.end:
 mov eax,ecx
 sub eax,edx
 cmp eax,4
 jne .continue
 cmp dword [rdi+rdx],0x7363762e
 je .yes
.continue:
 cmp byte [rdi+rcx],0
 je .no
 inc ecx
 jmp .component
.yes: mov eax,1
 ret
.no: xor eax,eax
 ret

valid_relative:
 xor ecx,ecx
.component:
 mov r8d,ecx
.scan:
 cmp ecx,240
 jae .bad
 mov al,[rdi+rcx]
 test al,al
 jz .end_component
 cmp al,'/'
 je .end_component
 cmp al,32
 jb .bad
 cmp al,127
 je .bad
 inc ecx
 jmp .scan
.end_component:
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

make_index_path:
 lea rdi,[repo_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy
 xor ecx,ecx
.copy:
 lea rsi,[vcs_repo_root]
 lea rdi,[repo_path]
 rep movsb
 lea rsi,[index_suffix]
 mov ecx,12
 rep movsb
 ret

make_work_path:
 mov r8,rdi
 lea rdi,[repo_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 lea rsi,[vcs_repo_root]
 lea rdi,[repo_path]
 rep movsb
 mov byte [rdi],'/'
 inc rdi
 jmp .relative
.root:
 lea rdi,[repo_path]
 mov byte [rdi],'/'
 inc rdi
.relative:
 mov rsi,r8
.copy_path:
 lodsb
 stosb
 test al,al
 jnz .copy_path
 xor eax,eax
 ret

same_name:
 xor ecx,ecx
.loop:
 mov al,[rdi+rcx]
 cmp al,[rsi+rcx]
 jne .no
 test al,al
 jz .yes
 inc ecx
 cmp ecx,240
 jb .loop
.no: xor eax,eax
 ret
.yes: mov eax,1
 ret

emit:
 jmp [repo_writer]

print_string:
 mov rsi,rdi
.length:
 cmp byte [rsi],0
 je .write
 inc rsi
 jmp .length
.write:
 sub rsi,rdi
 jmp emit

print_newline:
 lea rdi,[newline]
 mov esi,1
 jmp emit

section .note.GNU-stack noalloc noexec nowrite progbits
