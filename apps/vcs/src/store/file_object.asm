; Canonical v3 file pages, file roots and verified file reconstruction.
%include "include/vcs.inc"
%include "include/object_store.inc"
%include "include/chunk_pipeline.inc"
%define VCS_FILE_OBJECT_IMPLEMENTATION
%include "include/file_object.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

extern sha256_init,sha256_update,sha256_final
extern vcs_object_id,vcs_chunk_object_id

section .rodata
file_page_magic: db 'UVCSFPG1'
file_root_magic: db 'UVCSFIL1'
file_hash_magic: db 'UVCSBYT1'

section .text
global vcs_file_bytes_hash,vcs_file_object_build
global vcs_file_object_read,vcs_file_object_verify

; RDI=file bytes, RSI=length, RDX=32-byte output.
vcs_file_bytes_hash:
 push rbx
 push r12
 push r13
 push r14
 sub rsp,136
 test rdx,rdx
 jz .hash_usage
 test rsi,rsi
 jz .hash_input_ok
 test rdi,rdi
 jz .hash_usage
.hash_input_ok:
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 lea rdi,[rsp+112]
 lea rsi,[file_hash_magic]
 mov ecx,8
 rep movsb
 mov [rsp+120],r13
 lea rdi,[rsp]
 call sha256_init
 lea rdi,[rsp]
 lea rsi,[rsp+112]
 mov edx,16
 call sha256_update
 test r13,r13
 jz .hash_final
 lea rdi,[rsp]
 mov rsi,r12
 mov rdx,r13
 call sha256_update
.hash_final:
 lea rdi,[rsp]
 mov rsi,r14
 call sha256_final
 xor eax,eax
 jmp .hash_done
.hash_usage:
 mov eax,VCS_ERR_USAGE
.hash_done:
 add rsp,136
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=vcs_file_build. Produces pages in chain order and one file root.
vcs_file_object_build:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,120
 test rdi,rdi
 jz .build_usage
 mov rbx,rdi
 mov r13,[rbx+vcs_file_build.data]
 mov r12,[rbx+vcs_file_build.entries]
 mov r14,[rbx+vcs_file_build.pages]
 mov r15,[rbx+vcs_file_build.page_ids]
 mov rbp,[rbx+vcs_file_build.root]
 test rbp,rbp
 jz .build_usage
 cmp qword [rbx+vcs_file_build.root_id],0
 je .build_usage
 mov rax,[rbx+vcs_file_build.mode]
 cmp rax,VCS_FILE_MODE_MASK
 ja .build_corrupt
 mov rax,[rbx+vcs_file_build.flags]
 cmp rax,VCS_FILE_FLAGS_MASK
 ja .build_corrupt
 mov r10,[rbx+vcs_file_build.length]
 test r10,r10
 jz .build_data_ok
 test r13,r13
 jz .build_usage
 mov rax,r13
 add rax,r10
 jc .build_usage
.build_data_ok:
 mov r11,[rbx+vcs_file_build.entry_count]
 test r11,r11
 jnz .build_nonempty
 test r10,r10
 jnz .build_corrupt
 mov qword [rsp],0
 jmp .build_hash
.build_nonempty:
 test r10,r10
 jz .build_corrupt
 test r12,r12
 jz .build_usage
 test r14,r14
 jz .build_usage
 test r15,r15
 jz .build_usage
 cmp qword [rbx+vcs_file_build.page_lengths],0
 je .build_usage
 mov rax,r11
 xor edx,edx
 mov ecx,VCS_FILE_PAGE_MAX_ENTRIES
 div rcx
 test rdx,rdx
 jz .build_pages_counted
 inc rax
.build_pages_counted:
 mov [rsp],rax
 cmp [rbx+vcs_file_build.page_capacity],rax
 jb .build_space
 mov rdx,-1
 shr rdx,6
 cmp r11,rdx
 ja .build_space
 mov rax,[rsp]
 mov ecx,VCS_FILE_PAGE_BYTES
 mul rcx
 test rdx,rdx
 jnz .build_space
 add rax,r14
 jc .build_space
 mov rax,[rsp]
 shl rax,5
 jc .build_space
 add rax,r15
 jc .build_space
 xor r8d,r8d
 xor r9d,r9d
.build_validate_entry:
 cmp r8,[rbx+vcs_file_build.entry_count]
 jae .build_validate_done
 mov rax,r8
 shl rax,6
 lea r10,[r12+rax]
 cmp [r10+vcs_file_chunk.offset],r9
 jne .build_corrupt
 mov rsi,[r10+vcs_file_chunk.length]
 test rsi,rsi
 jz .build_corrupt
 cmp rsi,VCS_CHUNK_OBJECT_MAX
 ja .build_corrupt
 mov rax,r9
 add rax,rsi
 jc .build_corrupt
 cmp rax,[rbx+vcs_file_build.length]
 ja .build_corrupt
 mov [rsp+104],r8
 mov [rsp+112],rax
 lea rdi,[r13+r9]
 lea rdx,[rsp+32]
 call vcs_chunk_object_id
 test eax,eax
 jnz .build_done
 mov r8,[rsp+104]
 mov rax,r8
 shl rax,6
 lea r10,[r12+rax]
 lea rdi,[rsp+32]
 lea rsi,[r10+vcs_file_chunk.id]
 call ids_equal
 test eax,eax
 jz .build_corrupt
 mov r9,[rsp+112]
 inc r8
 jmp .build_validate_entry
.build_validate_done:
 cmp r9,[rbx+vcs_file_build.length]
 jne .build_corrupt
.build_hash:
 mov rdi,r13
 mov rsi,[rbx+vcs_file_build.length]
 lea rdx,[rsp+64]
 call vcs_file_bytes_hash
 test eax,eax
 jnz .build_done
 mov rdi,rbp
 xor eax,eax
 mov ecx,VCS_FILE_ROOT_BYTES
 rep stosb
 mov rax,[rsp]
 test rax,rax
 jz .build_root
 mov rax,[rsp]
 dec rax
 mov [rsp+8],rax
.build_page_loop:
 mov r8,[rsp+8]
 mov rax,r8
 imul rax,VCS_FILE_PAGE_MAX_ENTRIES
 mov [rsp+16],rax
 mov r9,[rbx+vcs_file_build.entry_count]
 sub r9,rax
 cmp r9,VCS_FILE_PAGE_MAX_ENTRIES
 jbe .build_page_count_ok
 mov r9d,VCS_FILE_PAGE_MAX_ENTRIES
.build_page_count_ok:
 mov [rsp+24],r9
 mov rax,r8
 imul rax,VCS_FILE_PAGE_BYTES
 lea r10,[r14+rax]
 mov rdi,r10
 xor eax,eax
 mov ecx,VCS_FILE_PAGE_BYTES
 rep stosb
 mov rax,[file_page_magic]
 mov [r10],rax
 mov [r10+8],r8d
 mov [r10+12],r9d
 mov rax,[rsp+16]
 shl rax,6
 lea r11,[r12+rax]
 mov rax,[r11+vcs_file_chunk.offset]
 mov [r10+16],rax
 xor edx,edx
 xor ecx,ecx
.build_page_entries:
 cmp rcx,r9
 jae .build_page_entries_done
 mov rax,[rsp+16]
 add rax,rcx
 shl rax,6
 lea r11,[r12+rax]
 mov rax,rcx
 imul rax,VCS_FILE_PAGE_ENTRY
 lea rdi,[r10+VCS_FILE_PAGE_HEADER+rax]
 lea rsi,[r11+vcs_file_chunk.id]
 push rcx
 push rdx
 mov ecx,32
 rep movsb
 pop rdx
 pop rcx
 mov rax,[r11+vcs_file_chunk.length]
 mov [rdi],rax
 add rdx,rax
 jc .build_corrupt
 inc rcx
 jmp .build_page_entries
.build_page_entries_done:
 mov [r10+24],rdx
 mov r8,[rsp+8]
 mov rax,[rsp]
 dec rax
 cmp r8,rax
 jae .build_page_final
 lea rax,[r8+1]
 shl rax,5
 lea rsi,[r15+rax]
 lea rdi,[r10+32]
 mov ecx,32
 rep movsb
.build_page_final:
 mov rax,[rsp+24]
 imul rax,VCS_FILE_PAGE_ENTRY
 add rax,VCS_FILE_PAGE_HEADER
 mov [rsp+56],rax
 mov rdx,r8
 shl rdx,3
 mov rcx,[rbx+vcs_file_build.page_lengths]
 mov [rcx+rdx],rax
 mov rdx,r8
 shl rdx,5
 lea rcx,[r15+rdx]
 mov edi,9
 mov rsi,r10
 mov rdx,rax
 call vcs_object_id
 test eax,eax
 jnz .build_done
 cmp qword [rsp+8],0
 je .build_root
 dec qword [rsp+8]
 jmp .build_page_loop
.build_root:
 mov rax,[file_root_magic]
 mov [rbp],rax
 mov eax,[rbx+vcs_file_build.mode]
 mov [rbp+8],eax
 mov eax,[rbx+vcs_file_build.flags]
 mov [rbp+12],eax
 mov rax,[rbx+vcs_file_build.length]
 mov [rbp+16],rax
 mov rax,[rbx+vcs_file_build.entry_count]
 mov [rbp+24],rax
 mov rax,[rsp]
 mov [rbp+32],rax
 test rax,rax
 jz .build_root_hash
 lea rdi,[rbp+48]
 mov rsi,r15
 mov ecx,32
 rep movsb
.build_root_hash:
 lea rdi,[rbp+80]
 lea rsi,[rsp+64]
 mov ecx,32
 rep movsb
 mov edi,VCS_OBJ_FILE
 mov rsi,rbp
 mov edx,VCS_FILE_ROOT_BYTES
 mov rcx,[rbx+vcs_file_build.root_id]
 call vcs_object_id
 test eax,eax
 jnz .build_done
 mov rax,[rsp]
 mov [rbx+vcs_file_build.result_pages],rax
 xor eax,eax
 jmp .build_done
.build_space:
 mov eax,VCS_ERR_NO_MEM
 jmp .build_done
.build_usage:
 mov eax,VCS_ERR_USAGE
 jmp .build_done
.build_corrupt:
 mov eax,VCS_ERR_CORRUPT
.build_done:
 add rsp,120
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=vcs_file_read. Validates the complete resolved chain before copy-out.
vcs_file_object_read:
 mov esi,1
 jmp file_object_read_common

; RDI=vcs_file_read. Validates without requiring or writing an output buffer.
vcs_file_object_verify:
 xor esi,esi

file_object_read_common:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,296
 mov [rsp+288],rsi
 test rdi,rdi
 jz .read_usage
 mov rbx,rdi
 mov rbp,[rbx+vcs_file_read.root]
 mov r12,[rbx+vcs_file_read.pages]
 mov r13,[rbx+vcs_file_read.chunks]
 mov r14,[rbx+vcs_file_read.output]
 mov r15,[rbx+vcs_file_read.root_id]
 test rbp,rbp
 jz .read_usage
 test r15,r15
 jz .read_usage
 mov rax,[file_root_magic]
 cmp [rbp],rax
 jne .read_corrupt
 mov eax,[rbp+8]
 test eax,~VCS_FILE_MODE_MASK
 jnz .read_corrupt
 mov eax,[rbp+12]
 test eax,~VCS_FILE_FLAGS_MASK
 jnz .read_corrupt
 cmp qword [rbp+40],0
 jne .read_corrupt
 cmp qword [rbp+112],0
 jne .read_corrupt
 cmp qword [rbp+120],0
 jne .read_corrupt
 mov edi,VCS_OBJ_FILE
 mov rsi,rbp
 mov edx,VCS_FILE_ROOT_BYTES
 lea rcx,[rsp]
 call vcs_object_id
 test eax,eax
 jnz .read_done
 lea rdi,[rsp]
 mov rsi,r15
 call ids_equal
 test eax,eax
 jz .read_corrupt
 mov rax,[rbp+32]
 cmp [rbx+vcs_file_read.page_count],rax
 jne .read_not_found
 mov rax,[rbp+24]
 cmp [rbx+vcs_file_read.chunk_count],rax
 jne .read_not_found
 cmp qword [rsp+288],0
 je .read_output_ok
 mov rax,[rbp+16]
 cmp [rbx+vcs_file_read.output_capacity],rax
 jb .read_space
.read_output_ok:
 test rax,rax
 jz .read_empty
 test r12,r12
 jz .read_usage
 test r13,r13
 jz .read_usage
 cmp qword [rsp+288],0
 je .read_hash_begin
 test r14,r14
 jz .read_usage
 cmp qword [rbp+24],0
 je .read_corrupt
 cmp qword [rbp+32],0
 je .read_corrupt
 jmp .read_hash_begin
.read_empty:
 cmp qword [rbp+24],0
 jne .read_corrupt
 cmp qword [rbp+32],0
 jne .read_corrupt
 mov rax,[rbp+48]
 or rax,[rbp+56]
 or rax,[rbp+64]
 or rax,[rbp+72]
 jnz .read_corrupt
.read_hash_begin:
 lea rdi,[rsp+96]
 call sha256_init
 lea rdi,[rsp+64]
 lea rsi,[file_hash_magic]
 mov ecx,8
 rep movsb
 mov rax,[rbp+16]
 mov [rsp+72],rax
 lea rdi,[rsp+96]
 lea rsi,[rsp+64]
 mov edx,16
 call sha256_update
 mov qword [rsp+32],0                ; page index
 mov qword [rsp+40],0                ; chunk index
 mov qword [rsp+48],0                ; reconstructed bytes
 lea rdi,[rsp+256]
 lea rsi,[rbp+48]
 mov ecx,32
 rep movsb
.read_page_loop:
 mov r8,[rsp+32]
 cmp r8,[rbp+32]
 jae .read_pages_done
 mov rax,r8
 imul rax,vcs_chunk_record_size
 lea r10,[r12+rax]
 mov [rsp+208],r10
 lea rdi,[r10+vcs_chunk_record.id]
 lea rsi,[rsp+256]
 call ids_equal
 test eax,eax
 jz .read_not_found
 mov r11,[r10+vcs_chunk_record.data]
 test r11,r11
 jz .read_corrupt
 mov [rsp+216],r11
 mov rdx,[r10+vcs_chunk_record.length]
 cmp rdx,VCS_FILE_PAGE_HEADER+VCS_FILE_PAGE_ENTRY
 jb .read_corrupt
 cmp rdx,VCS_FILE_PAGE_BYTES
 ja .read_corrupt
 mov edi,9
 mov rsi,r11
 lea rcx,[rsp]
 call vcs_object_id
 test eax,eax
 jnz .read_done
 lea rdi,[rsp]
 mov r10,[rsp+208]
 lea rsi,[r10+vcs_chunk_record.id]
 call ids_equal
 test eax,eax
 jz .read_corrupt
 mov r11,[rsp+216]
 mov rax,[file_page_magic]
 cmp [r11],rax
 jne .read_corrupt
 mov r8,[rsp+32]
 cmp [r11+8],r8d
 jne .read_corrupt
 mov r9d,[r11+12]
 test r9d,r9d
 jz .read_corrupt
 cmp r9d,VCS_FILE_PAGE_MAX_ENTRIES
 ja .read_corrupt
 mov [rsp+224],r9
 mov eax,r9d
 imul rax,VCS_FILE_PAGE_ENTRY
 add rax,VCS_FILE_PAGE_HEADER
 cmp [r10+vcs_chunk_record.length],rax
 jne .read_corrupt
 mov rax,[rsp+48]
 cmp [r11+16],rax
 jne .read_corrupt
 mov rax,r8
 inc rax
 cmp rax,[rbp+32]
 jae .read_last_page
 mov rax,[r11+32]
 or rax,[r11+40]
 or rax,[r11+48]
 or rax,[r11+56]
 jz .read_corrupt
 jmp .read_next_saved
.read_last_page:
 mov rax,[r11+32]
 or rax,[r11+40]
 or rax,[r11+48]
 or rax,[r11+56]
 jnz .read_corrupt
.read_next_saved:
 lea rdi,[rsp+256]
 lea rsi,[r11+32]
 mov ecx,32
 rep movsb
 mov qword [rsp+56],0                ; page bytes
 mov qword [rsp+232],0               ; entry index within page
.read_chunk_loop:
 mov r8,[rsp+232]
 mov r9,[rsp+224]
 cmp r8,r9
 jae .read_page_done
 mov rax,[rsp+40]
 cmp rax,[rbp+24]
 jae .read_corrupt
 imul rax,vcs_chunk_record_size
 lea r10,[r13+rax]
 mov [rsp+240],r10
 mov rax,r8
 imul rax,VCS_FILE_PAGE_ENTRY
 mov r11,[rsp+216]
 lea r11,[r11+VCS_FILE_PAGE_HEADER+rax]
 mov [rsp+248],r11
 lea rdi,[r10+vcs_chunk_record.id]
 mov rsi,r11
 call ids_equal
 test eax,eax
 jz .read_not_found
 mov r11,[rsp+248]
 mov r10,[rsp+240]
 mov rsi,[r11+32]
 cmp [r10+vcs_chunk_record.length],rsi
 jne .read_corrupt
 test rsi,rsi
 jz .read_corrupt
 cmp rsi,VCS_CHUNK_OBJECT_MAX
 ja .read_corrupt
 mov rdi,[r10+vcs_chunk_record.data]
 test rdi,rdi
 jz .read_corrupt
 lea rdx,[rsp]
 call vcs_chunk_object_id
 test eax,eax
 jnz .read_done
 lea rdi,[rsp]
 mov r10,[rsp+240]
 lea rsi,[r10+vcs_chunk_record.id]
 call ids_equal
 test eax,eax
 jz .read_corrupt
 mov rax,[rsp+40]
 imul rax,vcs_chunk_record_size
 lea r10,[r13+rax]
 lea rdi,[rsp+96]
 mov rsi,[r10+vcs_chunk_record.data]
 mov rdx,[r10+vcs_chunk_record.length]
 call sha256_update
 mov r10,[rsp+240]
 mov rax,[r10+vcs_chunk_record.length]
 add [rsp+56],rax
 jc .read_corrupt
 add [rsp+48],rax
 jc .read_corrupt
 inc qword [rsp+40]
 inc qword [rsp+232]
 jmp .read_chunk_loop
.read_page_done:
 cmp qword [rsp+56],0
 je .read_corrupt
 mov r11,[rsp+216]
 mov rax,[rsp+56]
 cmp [r11+24],rax
 jne .read_corrupt
 inc qword [rsp+32]
 jmp .read_page_loop
.read_pages_done:
 mov rax,[rsp+40]
 cmp rax,[rbp+24]
 jne .read_not_found
 mov rax,[rsp+48]
 cmp rax,[rbp+16]
 jne .read_corrupt
 lea rdi,[rsp+96]
 lea rsi,[rsp]
 call sha256_final
 lea rdi,[rsp]
 lea rsi,[rbp+80]
 call ids_equal
 test eax,eax
 jz .read_corrupt
 cmp qword [rsp+288],0
 je .read_verified
 xor r8d,r8d
 mov rdi,r14
.read_copy_loop:
 cmp r8,[rbp+24]
 jae .read_success
 mov rax,r8
 imul rax,vcs_chunk_record_size
 lea r10,[r13+rax]
 mov rsi,[r10+vcs_chunk_record.data]
 mov rcx,[r10+vcs_chunk_record.length]
 rep movsb
 inc r8
 jmp .read_copy_loop
.read_success:
 mov rax,[rbp+16]
 mov [rbx+vcs_file_read.result_length],rax
.read_verified:
 xor eax,eax
 jmp .read_done
.read_not_found:
 mov eax,VCS_ERR_NOT_FOUND
 jmp .read_done
.read_space:
 mov eax,VCS_ERR_NO_MEM
 jmp .read_done
.read_usage:
 mov eax,VCS_ERR_USAGE
 jmp .read_done
.read_corrupt:
 mov eax,VCS_ERR_CORRUPT
.read_done:
 add rsp,296
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI and RSI point to 32-byte IDs. EAX=1 only when every byte matches.
ids_equal:
 mov rax,[rdi]
 xor rax,[rsi]
 mov rcx,[rdi+8]
 xor rcx,[rsi+8]
 or rax,rcx
 mov rcx,[rdi+16]
 xor rcx,[rsi+16]
 or rax,rcx
 mov rcx,[rdi+24]
 xor rcx,[rsi+24]
 or rax,rcx
 setz al
 movzx eax,al
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
