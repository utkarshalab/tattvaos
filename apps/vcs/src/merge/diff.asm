; Bounded exact line diff. SysV AMD64; no allocation, syscalls or global state.
%include "include/diff.inc"
bits 64
default rel
section .text
global diff_files, diff_trees, diff_emit
; rdi=request; rax=status, rdx=count (required count on output NO_MEM).
; Scratch may change on failure; output is unchanged on every failure.
; Caller owns readable inputs and disjoint writable scratch/output extents.
diff_files:
 push rbp
 mov rbp,rsp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,24
 mov r12,rdi
 test rdi,rdi
 jz .usage
 cmp qword [r12+vcs_diff_request.old_size],VCS_DIFF_BYTES
 ja .usage
 cmp qword [r12+vcs_diff_request.new_size],VCS_DIFF_BYTES
 ja .usage
 cmp qword [r12+vcs_diff_request.old_size],0
 je .check_new
 cmp qword [r12+vcs_diff_request.old],0
 je .usage
.check_new:
 cmp qword [r12+vcs_diff_request.new_size],0
 je .check_scratch
 cmp qword [r12+vcs_diff_request.new],0
 je .usage
.check_scratch:
 cmp qword [r12+vcs_diff_request.scratch],0
 je .usage
 cmp qword [r12+vcs_diff_request.scratch_size],VCS_DIFF_SCRATCH
 jb .memory
 mov rdi,[r12+vcs_diff_request.old]
 mov rsi,[r12+vcs_diff_request.old_size]
 mov rdx,[r12+vcs_diff_request.scratch]
 call .split
 test rax,rax
 js .usage
 mov r13,rax
 mov rdi,[r12+vcs_diff_request.new]
 mov rsi,[r12+vcs_diff_request.new_size]
 mov rdx,[r12+vcs_diff_request.scratch]
 add rdx,4096
 call .split
 test rax,rax
 js .usage
 mov r14,rax
 mov r15,[r12+vcs_diff_request.scratch]
 add r15,8192
 mov rdi,r15
 mov ecx,257*257
 xor eax,eax
 rep stosd
 mov rbx,r13
.row:
 test rbx,rbx
 jz .capacity
 dec rbx
 mov [rbp-48],r14
.column:
 cmp qword [rbp-48],0
 je .row
 dec qword [rbp-48]
 mov r8,rbx
 mov r9,[rbp-48]
 call .equal
 imul ecx,ebx,257
 add ecx,[rbp-48]
 test eax,eax
 jz .different
 mov eax,[r15+rcx*4+258*4]
 inc eax
 jmp .cell
.different:
 mov eax,[r15+rcx*4+257*4]
 mov edx,[r15+rcx*4+4]
 cmp eax,edx
 cmovb eax,edx
.cell:
 mov [r15+rcx*4],eax
 jmp .column
.capacity:
 lea rdx,[r13+r14]
 mov eax,[r15]
 sub rdx,rax
 mov [rbp-56],rdx
 cmp [r12+vcs_diff_request.capacity],rdx
 jb .required
 test rdx,rdx
 jz .success
 cmp qword [r12+vcs_diff_request.output],0
 je .usage
 mov rbx,[r12+vcs_diff_request.output]
 xor r8d,r8d
 xor r9d,r9d
.walk:
 cmp r8,r13
 jae .only_new
 cmp r9,r14
 jae .delete
 call .equal
 test eax,eax
 jnz .same
 imul ecx,r8d,257
 add ecx,r9d
 mov eax,[r15+rcx*4+257*4]
 cmp eax,[r15+rcx*4+4]
 jae .delete
.insert:
 mov eax,VCS_DIFF_INSERT
 jmp .record
.only_new:
 cmp r9,r14
 jae .success
 jmp .insert
.delete:
 mov eax,VCS_DIFF_DELETE
 jmp .record
.same:
 xor eax,eax
.record:
 mov [rbx+vcs_diff_record.kind],rax
 mov r10,[r12+vcs_diff_request.scratch]
 mov rdi,[r12+vcs_diff_request.old_size]
 cmp r8,r13
 jae .old_end
 mov rcx,r8
 shl rcx,4
 mov rdi,[r10+rcx]
.old_end:
 mov [rbx+vcs_diff_record.old_offset],rdi
 mov rdi,[r12+vcs_diff_request.new_size]
 cmp r9,r14
 jae .new_end
 mov rcx,r9
 shl rcx,4
 mov rdi,[r10+4096+rcx]
.new_end:
 mov [rbx+vcs_diff_record.new_offset],rdi
 cmp eax,VCS_DIFF_INSERT
 je .new_length
 mov rcx,r8
 shl rcx,4
 mov rdx,[r10+rcx+8]
 inc r8
 test eax,eax
 jnz .advance
 inc r9
 jmp .advance
.new_length:
 mov rcx,r9
 shl rcx,4
 mov rdx,[r10+4096+rcx+8]
 inc r9
.advance:
 mov [rbx+vcs_diff_record.length],rdx
 add rbx,vcs_diff_record_size
 jmp .walk
.success:
 mov rdx,[rbp-56]
 xor eax,eax
 jmp .return
.usage:
 mov eax,VCS_ERR_USAGE
 xor edx,edx
 jmp .return
.memory:
 xor edx,edx
.required:
 mov eax,VCS_ERR_NO_MEM
.return:
 add rsp,24
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret
; LF-inclusive lines, without a phantom empty line after final LF.
.split:
 xor eax,eax
 xor ecx,ecx
.line:
 cmp rcx,rsi
 jae .split_done
 cmp eax,VCS_DIFF_LINES
 jae .too_many
 mov r8,rcx
.byte:
 mov r9b,[rdi+rcx]
 inc rcx
 cmp r9b,10
 je .store_line
 cmp rcx,rsi
 jb .byte
.store_line:
 mov [rdx],r8
 mov r9,rcx
 sub r9,r8
 mov [rdx+8],r9
 add rdx,16
 inc eax
 jmp .line
.too_many:
 mov rax,-1
.split_done:
 ret
; r8/r9=line indexes, preserved. eax=equal; other volatile regs scratch.
.equal:
 mov r10,[r12+vcs_diff_request.scratch]
 mov rax,r8
 shl rax,4
 mov rdi,[r10+rax]
 mov rcx,[r10+rax+8]
 mov rax,r9
 shl rax,4
 cmp rcx,[r10+4096+rax+8]
 jne .not_equal
 mov rsi,[r10+4096+rax]
 add rdi,[r12+vcs_diff_request.old]
 add rsi,[r12+vcs_diff_request.new]
 repe cmpsb
 sete al
 movzx eax,al
 ret
.not_equal:
 xor eax,eax
 ret
; Unimplemented legacy entries must not report successful work.
diff_trees:
diff_emit:
 mov eax,VCS_ERR_UNSUPPORTED
 xor edx,edx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
