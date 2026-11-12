; Canonical v3 paged tree builder and verified decoder.
%include "include/vcs.inc"
%include "include/object_store.inc"
%include "include/chunk_pipeline.inc"
%include "include/file_object.inc"
%define VCS_TREE_OBJECT_IMPLEMENTATION
%include "include/tree_object.inc"
bits 64
default rel

extern vcs_object_id

section .rodata
tree_page_magic: db 'UVCSTPG1'
tree_root_magic: db 'UVCSTRE1'

section .text
global vcs_tree_object_build,vcs_tree_object_read,vcs_tree_object_verify

; RDI=vcs_tree_build.
vcs_tree_object_build:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,104
 test rdi,rdi
 jz .build_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_tree_build.entries]
 mov r13,[rbx+vcs_tree_build.entry_count]
 mov r14,[rbx+vcs_tree_build.pages]
 mov r15,[rbx+vcs_tree_build.page_ids]
 mov rbp,[rbx+vcs_tree_build.root]
 test rbp,rbp
 jz .build_usage
 cmp qword [rbx+vcs_tree_build.root_id],0
 je .build_usage
 test r13,r13
 jnz .build_validate_setup
 mov qword [rsp],0
 jmp .build_outputs_ready
.build_validate_setup:
 test r12,r12
 jz .build_usage
 mov rax,r13
 mov ecx,vcs_tree_entry_size
 mul rcx
 test rdx,rdx
 jnz .build_space
 add rax,r12
 jc .build_space
 mov qword [rsp],1                 ; measured pages
 mov qword [rsp+8],0               ; current page entries
 mov qword [rsp+16],0              ; current encoded bytes
 mov qword [rsp+24],0              ; entry index
 xor r10d,r10d                     ; previous name pointer
 xor r11d,r11d                     ; previous name length
.build_validate_loop:
 mov r8,[rsp+24]
 cmp r8,r13
 jae .build_validate_done
 mov rax,r8
 imul rax,vcs_tree_entry_size
 lea r9,[r12+rax]
 mov rdi,[r9+vcs_tree_entry.name]
 mov rsi,[r9+vcs_tree_entry.name_length]
 test rdi,rdi
 jz .build_corrupt
 test rsi,rsi
 jz .build_corrupt
 cmp rsi,VCS_TREE_NAME_MAX
 ja .build_corrupt
 mov [rsp+72],r9
 mov [rsp+80],r10
 mov [rsp+88],r11
 call tree_name_valid
 test eax,eax
 jz .build_corrupt
 mov r9,[rsp+72]
 mov r10,[rsp+80]
 mov r11,[rsp+88]
 test r10,r10
 jz .build_order_ok
 mov rdi,r10
 mov rsi,r11
 mov rdx,[r9+vcs_tree_entry.name]
 mov rcx,[r9+vcs_tree_entry.name_length]
 call name_compare
 cmp eax,-1
 jne .build_corrupt
  mov r9,[rsp+72]
.build_order_ok:
 mov r10,[r9+vcs_tree_entry.name]
 mov r11,[r9+vcs_tree_entry.name_length]
 mov rax,[r9+vcs_tree_entry.kind]
 cmp rax,VCS_OBJ_FILE
 je .build_kind_ok
 cmp rax,VCS_OBJ_TREE
 jne .build_corrupt
.build_kind_ok:
 cmp qword [r9+vcs_tree_entry.mode],VCS_FILE_MODE_MASK
 ja .build_corrupt
 cmp qword [r9+vcs_tree_entry.flags],0
 jne .build_corrupt
 mov rax,[r9+vcs_tree_entry.target_id]
 or rax,[r9+vcs_tree_entry.target_id+8]
 or rax,[r9+vcs_tree_entry.target_id+16]
 or rax,[r9+vcs_tree_entry.target_id+24]
 jz .build_corrupt
 mov rax,r11
 add rax,7
 jc .build_space
 and rax,-8
 add rax,VCS_TREE_ENTRY_BASE
 mov rdx,[rsp+16]
 add rdx,rax
 jc .build_space
 mov rcx,[rsp+8]
 cmp rcx,VCS_TREE_PAGE_MAX_ENTRIES
 jae .build_new_page
 cmp rdx,VCS_TREE_PAGE_BYTES-VCS_TREE_PAGE_HEADER
 jbe .build_fit
.build_new_page:
 inc qword [rsp]
 mov qword [rsp+8],0
 mov rdx,rax
.build_fit:
 mov [rsp+16],rdx
 inc qword [rsp+8]
 inc qword [rsp+24]
 jmp .build_validate_loop
.build_validate_done:
 mov rax,[rsp]
 cmp [rbx+vcs_tree_build.page_capacity],rax
 jb .build_space
 test r14,r14
 jz .build_usage
 test r15,r15
 jz .build_usage
 cmp qword [rbx+vcs_tree_build.page_lengths],0
 je .build_usage
 cmp qword [rbx+vcs_tree_build.page_starts],0
 je .build_usage
 cmp qword [rbx+vcs_tree_build.page_counts],0
 je .build_usage
 mov rcx,VCS_TREE_PAGE_BYTES
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
 ; Partition the already-validated entries into deterministic greedy pages.
 mov qword [rsp+24],0              ; entry
 mov qword [rsp+32],0              ; page
 mov qword [rsp+40],0              ; page start
 mov qword [rsp+48],0              ; page count
 mov qword [rsp+56],0              ; encoded bytes
.build_partition_loop:
 mov r8,[rsp+24]
 cmp r8,r13
 jae .build_partition_finish
 mov rax,r8
 imul rax,vcs_tree_entry_size
 lea r9,[r12+rax]
 mov rax,[r9+vcs_tree_entry.name_length]
 add rax,7
 and rax,-8
 add rax,VCS_TREE_ENTRY_BASE
 mov rdx,[rsp+56]
 add rdx,rax
 mov rcx,[rsp+48]
 cmp rcx,VCS_TREE_PAGE_MAX_ENTRIES
 jae .build_partition_close
 cmp rdx,VCS_TREE_PAGE_BYTES-VCS_TREE_PAGE_HEADER
 jbe .build_partition_add
.build_partition_close:
 call build_record_partition
 inc qword [rsp+32]
 mov rax,[rsp+24]
 mov [rsp+40],rax
 mov qword [rsp+48],0
 mov qword [rsp+56],0
 jmp .build_partition_loop
.build_partition_add:
 mov [rsp+56],rdx
 inc qword [rsp+48]
 inc qword [rsp+24]
 jmp .build_partition_loop
.build_partition_finish:
 call build_record_partition
.build_outputs_ready:
 mov rdi,rbp
 xor eax,eax
 mov ecx,96
 rep stosb
 mov rax,[rsp]
 test rax,rax
 jz .build_root
 dec rax
 mov [rsp+32],rax
.build_page_loop:
 mov r8,[rsp+32]
 mov rax,r8
 imul rax,VCS_TREE_PAGE_BYTES
 lea r10,[r14+rax]
 mov rdi,r10
 xor eax,eax
 mov ecx,VCS_TREE_PAGE_BYTES
 rep stosb
 mov rax,[tree_page_magic]
 mov [r10],rax
 mov [r10+8],r8d
 mov rcx,[rbx+vcs_tree_build.page_counts]
 mov r9,[rcx+r8*8]
 mov [r10+12],r9d
 mov rcx,[rbx+vcs_tree_build.page_starts]
 mov r11,[rcx+r8*8]
 xor edx,edx
 xor ecx,ecx
.build_page_entry_loop:
 cmp rcx,r9
 jae .build_page_entries_done
 mov rax,r11
 add rax,rcx
 imul rax,vcs_tree_entry_size
 lea rsi,[r12+rax]
 lea rdi,[r10+VCS_TREE_PAGE_HEADER+rdx]
 mov al,[rsi+vcs_tree_entry.kind]
 mov [rdi],al
 mov rax,[rsi+vcs_tree_entry.name_length]
 mov [rdi+1],al
 mov ax,[rsi+vcs_tree_entry.mode]
 mov [rdi+2],ax
 mov dword [rdi+4],0
 mov rax,[rsi+vcs_tree_entry.target_size]
 mov [rdi+8],rax
 push rcx
 push rdx
 push rsi
 lea rsi,[rsi+vcs_tree_entry.target_id]
 lea rdi,[rdi+16]
 mov ecx,32
 rep movsb
 pop rsi
 mov rax,[rsi+vcs_tree_entry.name_length]
 mov rcx,rax
 mov rsi,[rsi+vcs_tree_entry.name]
 rep movsb
 pop rdx
 pop rcx
 mov rax,r11
 add rax,rcx
 imul rax,vcs_tree_entry_size
 lea rsi,[r12+rax]
 mov rax,[rsi+vcs_tree_entry.name_length]
 add rax,7
 and rax,-8
 add rax,VCS_TREE_ENTRY_BASE
 add rdx,rax
 inc rcx
 jmp .build_page_entry_loop
.build_page_entries_done:
 mov [r10+16],rdx
 mov r8,[rsp+32]
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
 mov rax,rdx
 add rax,VCS_TREE_PAGE_HEADER
 mov rcx,[rbx+vcs_tree_build.page_lengths]
 mov [rcx+r8*8],rax
 mov rcx,r8
 shl rcx,5
 lea rcx,[r15+rcx]
 mov edi,VCS_OBJ_TREE_PAGE
 mov rsi,r10
 mov rdx,rax
 call vcs_object_id
 test eax,eax
 jnz .build_done
 cmp qword [rsp+32],0
 je .build_root
 dec qword [rsp+32]
 jmp .build_page_loop
.build_root:
 mov rax,[tree_root_magic]
 mov [rbp],rax
 mov rax,r13
 mov [rbp+8],rax
 mov rax,[rsp]
 mov [rbp+16],rax
 test rax,rax
 jz .build_root_id
 lea rdi,[rbp+32]
 mov rsi,r15
 mov ecx,32
 rep movsb
.build_root_id:
 mov edi,VCS_OBJ_TREE
 mov rsi,rbp
 mov edx,96
 mov rcx,[rbx+vcs_tree_build.root_id]
 call vcs_object_id
 test eax,eax
 jnz .build_done
 mov rax,[rsp]
 mov [rbx+vcs_tree_build.result_pages],rax
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
 add rsp,104
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Uses builder locals and RBX request to record the current partition.
build_record_partition:
 mov r8,[rsp+40+8]                ; account for return address
 mov r9,[rsp+48+8]
 mov r10,[rsp+32+8]
 mov rax,[rbx+vcs_tree_build.page_starts]
 mov [rax+r10*8],r8
 mov rax,[rbx+vcs_tree_build.page_counts]
 mov [rax+r10*8],r9
 ret

vcs_tree_object_read:
 mov esi,1
 jmp tree_read_common

vcs_tree_object_verify:
 xor esi,esi

; RDI=vcs_tree_read, ESI=decode entries when nonzero.
tree_read_common:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,152
 test rdi,rdi
 jz .read_usage
 mov rbx,rdi
 mov [rsp+128],rsi
 mov rbp,[rbx+vcs_tree_read.root]
 mov r12,[rbx+vcs_tree_read.root_id]
 mov r13,[rbx+vcs_tree_read.pages]
 mov r14,[rbx+vcs_tree_read.entries]
 test rbp,rbp
 jz .read_usage
 test r12,r12
 jz .read_usage
 mov rax,[tree_root_magic]
 cmp [rbp],rax
 jne .read_corrupt
 cmp qword [rbp+24],0
 jne .read_corrupt
 mov rax,[rbp+64]
 or rax,[rbp+72]
 or rax,[rbp+80]
 or rax,[rbp+88]
 jnz .read_corrupt
 mov edi,VCS_OBJ_TREE
 mov rsi,rbp
 mov edx,96
 lea rcx,[rsp]
 call vcs_object_id
 test eax,eax
 jnz .read_done
 lea rdi,[rsp]
 mov rsi,r12
 call ids_equal_tree
 test eax,eax
 jz .read_corrupt
 mov rax,[rbp+16]
 cmp [rbx+vcs_tree_read.page_count],rax
 jne .read_not_found
 test rax,rax
 jz .read_empty
 test r13,r13
 jz .read_usage
 cmp qword [rsp+128],0
 je .read_begin
  mov rax,[rbp+8]
  cmp [rbx+vcs_tree_read.entry_capacity],rax
 jb .read_space
 test r14,r14
 jz .read_usage
 jmp .read_begin
.read_empty:
 cmp qword [rbp+8],0
 jne .read_corrupt
 mov rax,[rbp+32]
 or rax,[rbp+40]
 or rax,[rbp+48]
 or rax,[rbp+56]
 jnz .read_corrupt
.read_begin:
 mov qword [rsp+32],0             ; page index
 mov qword [rsp+40],0             ; entry total
 mov qword [rsp+48],0             ; previous name ptr
 mov qword [rsp+56],0             ; previous name len
  mov qword [rsp+136],0            ; previous page encoded bytes
  mov qword [rsp+144],0            ; previous page entry count
 lea rdi,[rsp+64]
 lea rsi,[rbp+32]
 mov ecx,32
 rep movsb
.read_page_loop:
 mov r8,[rsp+32]
 cmp r8,[rbp+16]
 jae .read_pages_done
 mov rax,r8
 imul rax,vcs_chunk_record_size
 lea r9,[r13+rax]
 lea rdi,[r9+vcs_chunk_record.id]
 lea rsi,[rsp+64]
 call ids_equal_tree
 test eax,eax
 jz .read_not_found
 mov r10,[r9+vcs_chunk_record.data]
 test r10,r10
 jz .read_corrupt
 mov rdx,[r9+vcs_chunk_record.length]
 cmp rdx,VCS_TREE_PAGE_HEADER+VCS_TREE_ENTRY_BASE+8
 jb .read_corrupt
 cmp rdx,VCS_TREE_PAGE_BYTES
 ja .read_corrupt
 mov [rsp+96],r9
 mov [rsp+104],r10
 mov edi,VCS_OBJ_TREE_PAGE
 mov rsi,r10
 lea rcx,[rsp]
 call vcs_object_id
 test eax,eax
 jnz .read_done
 mov r9,[rsp+96]
 lea rdi,[rsp]
 lea rsi,[r9+vcs_chunk_record.id]
 call ids_equal_tree
 test eax,eax
 jz .read_corrupt
 mov r10,[rsp+104]
 mov rax,[tree_page_magic]
 cmp [r10],rax
 jne .read_corrupt
 mov r8,[rsp+32]
 cmp [r10+8],r8d
 jne .read_corrupt
 mov r11d,[r10+12]
 test r11d,r11d
 jz .read_corrupt
 cmp r11d,VCS_TREE_PAGE_MAX_ENTRIES
 ja .read_corrupt
 cmp qword [r10+24],0
 jne .read_corrupt
 mov rax,[r10+16]
 add rax,VCS_TREE_PAGE_HEADER
 jc .read_corrupt
 mov r9,[rsp+96]
 cmp [r9+vcs_chunk_record.length],rax
 jne .read_corrupt
 mov rax,r8
 inc rax
 cmp rax,[rbp+16]
 jae .read_final_link
 mov rax,[r10+32]
 or rax,[r10+40]
 or rax,[r10+48]
 or rax,[r10+56]
 jz .read_corrupt
 jmp .read_link_ok
.read_final_link:
 mov rax,[r10+32]
 or rax,[r10+40]
 or rax,[r10+48]
 or rax,[r10+56]
 jnz .read_corrupt
.read_link_ok:
 lea rdi,[rsp+64]
 lea rsi,[r10+32]
 mov ecx,32
 rep movsb
 mov [rsp+112],r11
 mov qword [rsp+120],0             ; page entry index
 mov r15,VCS_TREE_PAGE_HEADER
.read_entry_loop:
 mov r8,[rsp+120]
 cmp r8,[rsp+112]
 jae .read_page_done
 mov r10,[rsp+104]
 mov rax,r15
 add rax,VCS_TREE_ENTRY_BASE
 mov r9,[rsp+96]
 cmp rax,[r9+vcs_chunk_record.length]
 ja .read_corrupt
 lea r10,[r10+r15]
 movzx eax,byte [r10]
 cmp eax,VCS_OBJ_FILE
 je .read_kind_ok
 cmp eax,VCS_OBJ_TREE
 jne .read_corrupt
.read_kind_ok:
 movzx r11d,byte [r10+1]
 test r11d,r11d
 jz .read_corrupt
 cmp r11d,VCS_TREE_NAME_MAX
 ja .read_corrupt
 movzx eax,word [r10+2]
 cmp eax,VCS_FILE_MODE_MASK
 ja .read_corrupt
 cmp dword [r10+4],0
 jne .read_corrupt
 mov rax,[r10+16]
 or rax,[r10+24]
 or rax,[r10+32]
 or rax,[r10+40]
 jz .read_corrupt
 lea rdi,[r10+VCS_TREE_ENTRY_BASE]
 mov rsi,r11
 call tree_name_valid
 test eax,eax
 jz .read_corrupt
 mov r10,[rsp+104]
 add r10,r15
 cmp qword [rsp+48],0
 je .read_name_ordered
 mov rdi,[rsp+48]
 mov rsi,[rsp+56]
 lea rdx,[r10+VCS_TREE_ENTRY_BASE]
 mov rcx,r11
 call name_compare
 cmp eax,-1
 jne .read_corrupt
.read_name_ordered:
 lea rax,[r10+VCS_TREE_ENTRY_BASE]
 mov [rsp+48],rax
 mov [rsp+56],r11
 mov rax,r11
 add rax,7
 and rax,-8
 mov rdx,rax
 add rax,VCS_TREE_ENTRY_BASE
  cmp qword [rsp+120],0
  jne .read_split_canonical
  cmp qword [rsp+32],0
  je .read_split_canonical
  cmp qword [rsp+144],VCS_TREE_PAGE_MAX_ENTRIES
  jae .read_split_canonical
  mov rcx,[rsp+136]
  add rcx,rax
  jc .read_corrupt
  cmp rcx,VCS_TREE_PAGE_BYTES-VCS_TREE_PAGE_HEADER
  jbe .read_corrupt                 ; previous page stopped before it was full
.read_split_canonical:
 add r15,rax
 jc .read_corrupt
 mov r9,[rsp+96]
 cmp r15,[r9+vcs_chunk_record.length]
 ja .read_corrupt
 lea rdi,[r10+VCS_TREE_ENTRY_BASE+r11]
 sub rdx,r11
 xor eax,eax
.read_padding:
 test rdx,rdx
 jz .read_padding_ok
 or al,[rdi]
 inc rdi
 dec rdx
 jmp .read_padding
.read_padding_ok:
 test al,al
 jnz .read_corrupt
 inc qword [rsp+40]
 inc qword [rsp+120]
 jmp .read_entry_loop
.read_page_done:
 mov r10,[rsp+104]
 mov rax,r15
 sub rax,VCS_TREE_PAGE_HEADER
 cmp [r10+16],rax
 jne .read_corrupt
 mov r9,[rsp+96]
 cmp r15,[r9+vcs_chunk_record.length]
 jne .read_corrupt
  mov rax,r15
  sub rax,VCS_TREE_PAGE_HEADER
  mov [rsp+136],rax
  mov rax,[rsp+112]
  mov [rsp+144],rax
 inc qword [rsp+32]
 jmp .read_page_loop
.read_pages_done:
 mov rax,[rsp+40]
 cmp rax,[rbp+8]
 jne .read_corrupt
 cmp qword [rsp+128],0
 je .read_verified
 ; Decode only after the complete chain has validated.
 xor r8d,r8d
 xor r9d,r9d
.read_decode_page:
 cmp r8,[rbp+16]
 jae .read_decoded
 mov rax,r8
 imul rax,vcs_chunk_record_size
 add rax,r13
 mov r10,[rax+vcs_chunk_record.data]
 mov r11d,[r10+12]
 mov r15,VCS_TREE_PAGE_HEADER
 xor ecx,ecx
.read_decode_entry:
 cmp rcx,r11
 jae .read_decode_next
 mov rax,r9
 imul rax,vcs_tree_entry_size
 lea rdx,[r14+rax]
 lea rax,[r10+r15+VCS_TREE_ENTRY_BASE]
 mov [rdx+vcs_tree_entry.name],rax
 movzx eax,byte [r10+r15+1]
 mov [rdx+vcs_tree_entry.name_length],rax
 lea rdi,[rdx+vcs_tree_entry.target_id]
 lea rsi,[r10+r15+16]
 push rcx
 mov ecx,32
 rep movsb
 pop rcx
 mov rax,[r10+r15+8]
 mov [rdx+vcs_tree_entry.target_size],rax
 movzx eax,byte [r10+r15]
 mov [rdx+vcs_tree_entry.kind],rax
 movzx eax,word [r10+r15+2]
 mov [rdx+vcs_tree_entry.mode],rax
 mov qword [rdx+vcs_tree_entry.flags],0
 movzx eax,byte [r10+r15+1]
 add rax,7
 and rax,-8
 add rax,VCS_TREE_ENTRY_BASE
 add r15,rax
 inc r9
 inc rcx
 jmp .read_decode_entry
.read_decode_next:
 inc r8
 jmp .read_decode_page
.read_decoded:
 mov [rbx+vcs_tree_read.result_entries],r9
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
 add rsp,152
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=name, RSI=length. Strict canonical UTF-8 and tree-name restrictions.
tree_name_valid:
 cmp rsi,1
 jb .name_bad
 cmp rsi,VCS_TREE_NAME_MAX
 ja .name_bad
 cmp rsi,1
 jne .name_dot_two
 cmp byte [rdi],'.'
 je .name_bad
.name_dot_two:
 cmp rsi,2
 jne .name_dot_vcs
 cmp word [rdi],0x2e2e
 je .name_bad
.name_dot_vcs:
 cmp rsi,4
 jne .utf8_begin
 cmp dword [rdi],0x7363762e          ; `.vcs`
 je .name_bad
.utf8_begin:
 xor ecx,ecx
.utf8_loop:
 cmp rcx,rsi
 jae .name_good
 movzx eax,byte [rdi+rcx]
 cmp eax,0x80
 jae .utf8_multibyte
 cmp eax,0x20
 jb .name_bad
 cmp eax,0x7f
 je .name_bad
 cmp eax,'/'
 je .name_bad
 inc rcx
 jmp .utf8_loop
.utf8_multibyte:
 cmp eax,0xc2
 jb .name_bad
 cmp eax,0xdf
 jbe .utf8_two
 cmp eax,0xef
 jbe .utf8_three
 cmp eax,0xf4
 jbe .utf8_four
 jmp .name_bad
.utf8_two:
 lea rdx,[rcx+1]
 cmp rdx,rsi
 jae .name_bad
 movzx edx,byte [rdi+rcx+1]
 cmp edx,0x80
 jb .name_bad
 cmp edx,0xbf
 ja .name_bad
 add rcx,2
 jmp .utf8_loop
.utf8_three:
 lea rdx,[rcx+2]
 cmp rdx,rsi
 jae .name_bad
 movzx edx,byte [rdi+rcx+1]
 cmp eax,0xe0
 jne .utf8_three_ed
 cmp edx,0xa0
 jb .name_bad
 jmp .utf8_three_second_hi
.utf8_three_ed:
 cmp eax,0xed
 jne .utf8_three_normal
 cmp edx,0x80
 jb .name_bad
 cmp edx,0x9f
 ja .name_bad
 jmp .utf8_three_third
.utf8_three_normal:
 cmp edx,0x80
 jb .name_bad
.utf8_three_second_hi:
 cmp edx,0xbf
 ja .name_bad
.utf8_three_third:
 movzx edx,byte [rdi+rcx+2]
 cmp edx,0x80
 jb .name_bad
 cmp edx,0xbf
 ja .name_bad
 add rcx,3
 jmp .utf8_loop
.utf8_four:
 lea rdx,[rcx+3]
 cmp rdx,rsi
 jae .name_bad
 movzx edx,byte [rdi+rcx+1]
 cmp eax,0xf0
 jne .utf8_four_f4
 cmp edx,0x90
 jb .name_bad
 jmp .utf8_four_second_hi
.utf8_four_f4:
 cmp eax,0xf4
 jne .utf8_four_normal
 cmp edx,0x80
 jb .name_bad
 cmp edx,0x8f
 ja .name_bad
 jmp .utf8_four_tail
.utf8_four_normal:
 cmp edx,0x80
 jb .name_bad
.utf8_four_second_hi:
 cmp edx,0xbf
 ja .name_bad
.utf8_four_tail:
 movzx edx,byte [rdi+rcx+2]
 cmp edx,0x80
 jb .name_bad
 cmp edx,0xbf
 ja .name_bad
 movzx edx,byte [rdi+rcx+3]
 cmp edx,0x80
 jb .name_bad
 cmp edx,0xbf
 ja .name_bad
 add rcx,4
 jmp .utf8_loop
.name_good:
 mov eax,1
 ret
.name_bad:
 xor eax,eax
 ret

; RDI/RSI=left ptr/len, RDX/RCX=right ptr/len. Raw unsigned order.
name_compare:
 mov r8,rsi
 cmp r8,rcx
 cmova r8,rcx
 xor r9d,r9d
.compare_loop:
 cmp r9,r8
 jae .compare_prefix
 mov al,[rdi+r9]
 cmp al,[rdx+r9]
 jb .compare_less
 ja .compare_greater
 inc r9
 jmp .compare_loop
.compare_prefix:
 cmp rsi,rcx
 jb .compare_less
 ja .compare_greater
 xor eax,eax
 ret
.compare_less:
 mov eax,-1
 ret
.compare_greater:
 mov eax,1
 ret

ids_equal_tree:
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
