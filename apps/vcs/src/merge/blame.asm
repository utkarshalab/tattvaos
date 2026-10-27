; First-parent, exact-line blame with verified signer attribution.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/diff.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_find
extern vcs_repo_discover,vcs_load_manifest,vcs_object_name,vcs_identity_name
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head,vcs_object_path
extern diff_files

section .bss
blame_writer: resq 1
blame_path: resb 240
blame_request: resb vcs_diff_request_size
blame_scratch: resb VCS_DIFF_SCRATCH
blame_records: resb 512*vcs_diff_record_size
blame_offsets: resq 256
blame_current: resq 256
blame_commit: resq 256
blame_active: resb 256
blame_lines: resq 1
blame_head_data: resq 1
blame_head_size: resq 1
blame_child_data: resq 1
blame_child_size: resq 1
blame_render: resb 16386
blame_number: resb 17

section .rodata
unsigned: db 'unsigned'
unsigned_len equ $-unsigned
space: db ' '
hex: db '0123456789abcdef'
no_newline: db 10

section .text
global vcs_blame

; RDI=canonical absolute file path, RSI=writer(bytes,length).
vcs_blame:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov [blame_writer],rsi
 test rbp,rbp
 jz .usage
 test rsi,rsi
 jz .usage
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 cmp qword [vcs_repo_head],0
 je .missing
 ; Convert canonical absolute input into a repository-relative path.
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root_path
 lea rdi,[vcs_repo_root]
 mov rsi,rbp
 repe cmpsb
 jne .usage
 cmp byte [rsi],'/'
 jne .usage
.relative_path:
 inc rsi
 jmp .copy_path
.root_path:
 cmp byte [rbp],'/'
 jne .usage
.root_relative:
 lea rsi,[rbp+1]
.copy_path:
 lea rdi,[blame_path]
 xor ecx,ecx
.copy_path_loop:
 lodsb
 stosb
 test al,al
 jz .path_ready
 inc ecx
 cmp ecx,239
 jb .copy_path_loop
 jmp .usage
.path_ready:
 mov r12,[vcs_repo_head]
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rdi,rax
 call manifest_file
 test rax,rax
 jz .missing
 mov [blame_head_data],rax
 mov [blame_head_size],rdx
 ; Split the HEAD file and initialize every line to HEAD.
 mov qword [blame_lines],0
 test rdx,rdx
 jz .render
 xor ecx,ecx
 xor r13d,r13d
.line_start:
 cmp r13,256
 jae .capacity
 lea rax,[blame_offsets]
 mov [rax+r13*8],rcx
 lea rax,[blame_current]
 mov [rax+r13*8],rcx
 lea rax,[blame_commit]
 mov [rax+r13*8],r12
 mov byte [blame_active+r13],1
 inc r13
.line_scan:
 cmp rcx,rdx
 jae .line_done
 mov rax,[blame_head_data]
 cmp byte [rax+rcx],10
 jne .line_next_byte
 inc rcx
 cmp rcx,rdx
 jb .line_start
 jmp .line_done
.line_next_byte:
 inc rcx
 jmp .line_scan
.line_done:
 mov [blame_lines],r13
 ; Walk child -> parent, moving only exact equal lines backward.
.history:
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rbx,rax
 mov r14,[rbx+16]
 test r14,r14
 jz .render
 mov rdi,rbx
 call manifest_file
 test rax,rax
 jz .corrupt
 mov [blame_child_data],rax
 mov [blame_child_size],rdx
 mov rdi,r14
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rbx,rax
 mov rdi,rbx
 call manifest_file
 mov r10,rax
 mov r9,rdx
 test r10,r10
 jz .deactivate_all
 mov [blame_request+vcs_diff_request.old],r10
 mov [blame_request+vcs_diff_request.old_size],r9
 mov rax,[blame_child_data]
 mov [blame_request+vcs_diff_request.new],rax
 mov rax,[blame_child_size]
 mov [blame_request+vcs_diff_request.new_size],rax
 lea rax,[blame_scratch]
 mov [blame_request+vcs_diff_request.scratch],rax
 mov qword [blame_request+vcs_diff_request.scratch_size],VCS_DIFF_SCRATCH
 lea rax,[blame_records]
 mov [blame_request+vcs_diff_request.output],rax
 mov qword [blame_request+vcs_diff_request.capacity],512
 lea rdi,[blame_request]
 call diff_files
 test eax,eax
 jnz .capacity
 mov r15,rdx
 xor r13d,r13d
.map_line:
 cmp r13,[blame_lines]
 jae .history_next
 cmp byte [blame_active+r13],0
 je .map_next
 lea rax,[blame_current]
 mov r11,[rax+r13*8]
 lea rbx,[blame_records]
 mov rcx,r15
.find_equal:
 test rcx,rcx
 jz .line_changed
 cmp qword [rbx+vcs_diff_record.kind],VCS_DIFF_EQUAL
 jne .equal_next
 cmp [rbx+vcs_diff_record.new_offset],r11
 jne .equal_next
 mov rax,[rbx+vcs_diff_record.old_offset]
 lea rdx,[blame_current]
 mov [rdx+r13*8],rax
 lea rdx,[blame_commit]
 mov [rdx+r13*8],r14
 jmp .map_next
.equal_next:
 add rbx,vcs_diff_record_size
 dec rcx
 jmp .find_equal
.line_changed:
 mov byte [blame_active+r13],0
.map_next:
 inc r13
 jmp .map_line
.deactivate_all:
 xor r13d,r13d
.deactivate_loop:
 cmp r13,[blame_lines]
 jae .history_next
 mov byte [blame_active+r13],0
 inc r13
 jmp .deactivate_loop
.history_next:
 mov r12,r14
 jmp .history
.render:
 xor r13d,r13d
.render_line:
 cmp r13,[blame_lines]
 jae .ok
 lea rax,[blame_commit]
 mov rdi,[rax+r13*8]
 call emit_id
 lea rdi,[space]
 mov esi,1
 call emit
 lea rax,[blame_commit]
 mov rdi,[rax+r13*8]
 call vcs_identity_name
 test eax,eax
 jnz .render_unsigned
 mov rdi,rdx
 call emit_string
 jmp .render_space
.render_unsigned:
 lea rdi,[unsigned]
 mov esi,unsigned_len
 call emit
.render_space:
 lea rdi,[space]
 mov esi,1
 call emit
 lea rax,[blame_offsets]
 mov r14,[rax+r13*8]
 mov r15,[blame_head_size]
 mov rax,[blame_head_data]
 lea rsi,[rax+r14]
 sub r15,r14
 xor ecx,ecx
.render_len:
 cmp rcx,r15
 jae .render_bytes
 cmp byte [rsi+rcx],10
 je .render_include_lf
 inc rcx
 jmp .render_len
.render_include_lf:
 inc rcx
.render_bytes:
 mov rdx,rcx
 xor r12d,r12d
 test rdx,rdx
 jz .render_emit
 mov rax,[blame_head_data]
 add rax,r14
 cmp byte [rax+rdx-1],10
 sete r12b
.render_emit:
 call emit_escaped
 test r12b,r12b
 jnz .render_next
.render_add_lf:
 lea rdi,[no_newline]
 mov esi,1
 call emit
.render_next:
 inc r13
 jmp .render_line
.ok: xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
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

; RDI=manifest -> RAX=blob bytes, RDX=size, or zero.
manifest_file:
 push rbx
 push r12
 mov rbx,rdi
 mov r12,[rbx+24]
 add rbx,VR_HEADER
.file_loop:
 test r12,r12
 jz .file_missing
 lea rdi,[blame_path]
 mov rsi,rbx
 call same_name
 test eax,eax
 jnz .file_found
 add rbx,VR_ENTRY
 dec r12
 jmp .file_loop
.file_found:
 mov rdi,[rbx+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .file_missing
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .file_missing
 cmp qword [rax+UV_TYPE],1
 jne .file_missing
 mov rdx,[rbx+VR_SIZE]
 cmp [rax+UV_SIZE],rdx
 jne .file_missing
 add rax,UV_DATA
 pop r12
 pop rbx
 ret
.file_missing:
 xor eax,eax
 xor edx,edx
 pop r12
 pop rbx
 ret

same_name:
 xor ecx,ecx
.name_loop:
 mov al,[rdi+rcx]
 cmp al,[rsi+rcx]
 jne .name_no
 test al,al
 jz .name_yes
 inc ecx
 cmp ecx,VR_PATH
 jb .name_loop
.name_no: xor eax,eax
 ret
.name_yes: mov eax,1
 ret

emit_id:
 lea rsi,[blame_number]
 mov ecx,16
 lea rdx,[hex]
.id_digit:
 rol rdi,4
 mov rax,rdi
 and eax,15
 mov al,[rdx+rax]
 mov [rsi],al
 inc rsi
 loop .id_digit
 lea rdi,[blame_number]
 mov esi,16
 jmp emit

emit_string:
 xor esi,esi
.string_len:
 cmp byte [rdi+rsi],0
 je emit
 inc esi
 jmp .string_len

; RSI bytes, RDX length. Escape terminal controls and non-ASCII bytes.
emit_escaped:
 lea rdi,[blame_render]
 xor ecx,ecx
 lea r8,[hex]
.escape_loop:
 test rdx,rdx
 jz .escape_done
 lodsb
 dec rdx
 cmp al,10
 je .literal
 cmp al,32
 jb .escape
 cmp al,126
 ja .escape
 cmp al,92
 je .escape
.literal:
 mov [rdi+rcx],al
 inc rcx
 jmp .escape_loop
.escape:
 mov byte [rdi+rcx],92
 mov byte [rdi+rcx+1],'x'
 movzx r9d,al
 shr r9d,4
 mov r9b,[r8+r9]
 mov [rdi+rcx+2],r9b
 and eax,15
 mov al,[r8+rax]
 mov [rdi+rcx+3],al
 add rcx,4
 jmp .escape_loop
.escape_done:
 mov rsi,rcx
 lea rdi,[blame_render]
 jmp emit

emit:
 jmp [blame_writer]

section .note.GNU-stack noalloc noexec nowrite progbits
