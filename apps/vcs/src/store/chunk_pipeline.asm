; Content-defined whole-file chunk writer with collision-safe deduplication.
%include "include/vcs.inc"
%include "include/chunk.inc"
%include "include/object_store.inc"
%define VCS_CHUNK_PIPELINE_IMPLEMENTATION
%include "include/chunk_pipeline.inc"
bits 64
default rel

extern vcs_chunk_count,vcs_chunk
extern vcs_chunk_object_id,vcs_chunk_object_write

section .text
global vcs_file_chunks_write

; RDI=vcs_chunk_pipeline. RAX=VCS status.
vcs_file_chunks_write:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,40
 test rdi,rdi
 jz .usage
 mov rbx,rdi
 mov r12,[rbx+vcs_chunk_pipeline.data]
 mov r13,[rbx+vcs_chunk_pipeline.length]
 test r13,r13
 jnz .nonempty
 mov qword [rbx+vcs_chunk_pipeline.result_count],0
 mov qword [rbx+vcs_chunk_pipeline.result_new],0
 xor eax,eax
 jmp .done
.nonempty:
 test r12,r12
 jz .usage
 mov rax,r12
 add rax,r13
 jc .usage
 mov r14,[rbx+vcs_chunk_pipeline.bounds]
 mov r15,[rbx+vcs_chunk_pipeline.entries]
 test r14,r14
 jz .usage
 test r15,r15
 jz .usage
 mov rdi,r12
 mov rsi,r13
 call vcs_chunk_count
 test rax,rax
 js .usage
 mov [rsp],rax
 mov rdx,-1
 shr rdx,6
 cmp rax,rdx
 ja .space
 mov rdx,rax
 shl rdx,6
 add rdx,r15
 jc .space
 mov rdx,rax
 shl rdx,3
 add rdx,r14
 jc .space
 cmp [rbx+vcs_chunk_pipeline.bounds_capacity],rax
 jb .space
 cmp [rbx+vcs_chunk_pipeline.entry_capacity],rax
 jb .space
 mov rdi,r12
 mov rsi,r13
 mov rdx,r14
 mov rcx,[rbx+vcs_chunk_pipeline.bounds_capacity]
 call vcs_chunk
 cmp rax,[rsp]
 jne .corrupt
 mov rax,[rbx+vcs_chunk_pipeline.existing_count]
 test rax,rax
 jz .existing_ok
 cmp qword [rbx+vcs_chunk_pipeline.existing],0
 je .usage
 mov ecx,vcs_chunk_record_size
 mul rcx
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_chunk_pipeline.existing]
 jc .space
.existing_ok:
 mov rax,[rbx+vcs_chunk_pipeline.new_capacity]
 test rax,rax
 jz .new_slots_ok
 cmp qword [rbx+vcs_chunk_pipeline.new_ios],0
 je .usage
 mov rax,[rbx+vcs_chunk_pipeline.new_capacity]
 mov ecx,vcs_chunk_io_size
 mul rcx
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_chunk_pipeline.new_ios]
 jc .space
.new_slots_ok:
 mov qword [rsp+8],0                 ; chunk index
 mov qword [rsp+16],0                ; current start
 mov qword [rsp+24],0                ; new object count
.chunk_loop:
 mov r8,[rsp+8]
 cmp r8,[rsp]
 jae .success
 mov r9,[rsp+16]
 mov r10,[r14+r8*8]
 cmp r10,r9
 jbe .corrupt
 cmp r10,r13
 ja .corrupt
 mov r11,r10
 sub r11,r9
 cmp r11,VCS_CHUNK_MAX
 ja .corrupt
 mov rax,r8
 shl rax,6
 lea rbp,[r15+rax]
 mov [rbp+vcs_file_chunk.offset],r9
 mov [rbp+vcs_file_chunk.length],r11
 mov qword [rbp+vcs_file_chunk.storage_index],0
 mov qword [rbp+vcs_file_chunk.flags],0
 lea rdi,[r12+r9]
 mov rsi,r11
 lea rdx,[rbp+vcs_file_chunk.id]
 call vcs_chunk_object_id
 test eax,eax
 jnz .done
 mov qword [rsp+32],0                ; matching existing index plus one
 xor ecx,ecx
.existing_loop:
 cmp rcx,[rbx+vcs_chunk_pipeline.existing_count]
 jae .existing_complete
 mov rax,rcx
 imul rax,vcs_chunk_record_size
 add rax,[rbx+vcs_chunk_pipeline.existing]
 mov rdx,[rbp]
 xor rdx,[rax]
 mov rsi,[rbp+8]
 xor rsi,[rax+8]
 or rdx,rsi
 mov rsi,[rbp+16]
 xor rsi,[rax+16]
 or rdx,rsi
 mov rsi,[rbp+24]
 xor rsi,[rax+24]
 or rdx,rsi
 jnz .existing_next
 mov rsi,[rax+vcs_chunk_record.length]
 cmp rsi,[rbp+vcs_file_chunk.length]
 jne .collision
 mov rdi,[rax+vcs_chunk_record.data]
 test rdi,rdi
 jz .corrupt
 mov rdx,[rbp+vcs_file_chunk.offset]
 lea rdx,[r12+rdx]
 mov r9,rcx
 call bytes_equal_full
 mov rcx,r9
 test eax,eax
 jz .collision
 cmp qword [rsp+32],0
 jne .corrupt
 lea rdx,[rcx+1]
 mov [rsp+32],rdx
.existing_next:
 inc rcx
 jmp .existing_loop
.existing_complete:
 mov rcx,[rsp+32]
 test rcx,rcx
 jz .prior_begin
 dec rcx
 mov [rbp+vcs_file_chunk.storage_index],rcx
 mov qword [rbp+vcs_file_chunk.flags],VCS_FILE_CHUNK_EXISTING
 jmp .chunk_done
.prior_begin:
 xor ecx,ecx
.prior_loop:
 cmp rcx,[rsp+8]
 jae .write_new
 mov rax,rcx
 shl rax,6
 lea rax,[r15+rax]
 mov rdx,[rbp]
 xor rdx,[rax]
 mov rsi,[rbp+8]
 xor rsi,[rax+8]
 or rdx,rsi
 mov rsi,[rbp+16]
 xor rsi,[rax+16]
 or rdx,rsi
 mov rsi,[rbp+24]
 xor rsi,[rax+24]
 or rdx,rsi
 jnz .prior_next
 mov rsi,[rax+vcs_file_chunk.length]
 cmp rsi,[rbp+vcs_file_chunk.length]
 jne .collision
 mov rdi,[rax+vcs_file_chunk.offset]
 lea rdi,[r12+rdi]
 mov rdx,[rbp+vcs_file_chunk.offset]
 lea rdx,[r12+rdx]
 mov [rsp+32],rcx
 call bytes_equal_full
 mov rcx,[rsp+32]
 test eax,eax
 jz .collision
 mov rax,rcx
 shl rax,6
 lea rax,[r15+rax]
 mov rdx,[rax+vcs_file_chunk.storage_index]
 mov [rbp+vcs_file_chunk.storage_index],rdx
 mov rdx,[rax+vcs_file_chunk.flags]
 test rdx,VCS_FILE_CHUNK_EXISTING
 jnz .copy_prior_flag
 mov edx,VCS_FILE_CHUNK_PRIOR
.copy_prior_flag:
 mov [rbp+vcs_file_chunk.flags],rdx
 jmp .chunk_done
.prior_next:
 inc rcx
 jmp .prior_loop
.write_new:
 mov r8,[rsp+24]
 cmp r8,[rbx+vcs_chunk_pipeline.new_capacity]
 jae .space
 mov rax,vcs_chunk_io_size
 mul r8
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_chunk_pipeline.new_ios]
 jc .space
 mov rdx,[rbp+vcs_file_chunk.offset]
 lea rdx,[r12+rdx]
 mov [rax+vcs_chunk_io.payload],rdx
 mov rdx,[rbp+vcs_file_chunk.length]
 mov [rax+vcs_chunk_io.payload_length],rdx
 lea rdx,[rbp+vcs_file_chunk.id]
 mov [rax+vcs_chunk_io.object_id],rdx
 mov [rbp+vcs_file_chunk.storage_index],r8
 mov qword [rbp+vcs_file_chunk.flags],0
 mov rdi,rax
 call vcs_chunk_object_write
 test eax,eax
 jnz .done
 inc qword [rsp+24]
.chunk_done:
 mov r8,[rsp+8]
 mov rax,[r14+r8*8]
 mov [rsp+16],rax
 inc qword [rsp+8]
 jmp .chunk_loop
.success:
 cmp qword [rsp+16],r13
 jne .corrupt
 mov rax,[rsp]
 mov [rbx+vcs_chunk_pipeline.result_count],rax
 mov rax,[rsp+24]
 mov [rbx+vcs_chunk_pipeline.result_new],rax
 xor eax,eax
 jmp .done
.collision:
 mov eax,VCS_ERR_CONFLICT
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,40
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=left, RDX=right, RSI=length. EAX=1 equal, zero different.
; The complete length is visited even after a mismatch.
bytes_equal_full:
 xor eax,eax
 xor ecx,ecx
.compare:
 cmp rcx,rsi
 jae .result
 mov r8b,[rdi+rcx]
 xor r8b,[rdx+rcx]
 or al,r8b
 inc rcx
 jmp .compare
.result:
 test al,al
 setz al
 movzx eax,al
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
