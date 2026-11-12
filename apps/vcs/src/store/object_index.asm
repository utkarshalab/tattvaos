; Canonical object-index validation, lookup and copy-on-write merge planning.
%include "include/vcs.inc"
%define VCS_OBJECT_INDEX_IMPLEMENTATION
%include "include/object_index.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

section .text
global vcs_object_index_validate,vcs_object_index_find,vcs_object_index_merge_plan
global vcs_object_index_root_hash,vcs_object_index_root_verify
global vcs_object_index_verified_find

extern sha256_init,sha256_update,sha256_final

section .rodata
index_root_frame:
 db 'UVCSROT1'
 dw 1,5
 dd 0
index_root_frame_size equ $-index_root_frame

section .bss
alignb 16
index_hash_context: resb sha256_ctx_t_size
index_hash_digest: resb SHA256_DIGEST_SIZE

section .text

; RDI=records, RSI=count. RAX=VCS status.
vcs_object_index_validate:
 test rsi,rsi
 jz .validate_ok
 test rdi,rdi
 jz .validate_usage
 mov rax,rsi
 mov ecx,vcs_object_index_record_size
 mul rcx
 test rdx,rdx
 jnz .validate_corrupt
 add rax,rdi
 jc .validate_corrupt
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 xor r13d,r13d
.validate_loop:
 cmp r13,r12
 jae .validate_pop_ok
 mov rax,r13
 shl rax,6
 lea rdi,[rbx+rax]
 call index_record_validate
 test eax,eax
 jnz .validate_pop
 test r13,r13
 jz .validate_next
 lea rsi,[rdi-64]
 call index_id_compare
 cmp eax,1                         ; current must be greater than previous
 jne .validate_pop_corrupt
.validate_next:
 inc r13
 jmp .validate_loop
.validate_pop_ok:
 xor eax,eax
 jmp .validate_pop
.validate_pop_corrupt:
 mov eax,VCS_ERR_CORRUPT
.validate_pop:
 pop r13
 pop r12
 pop rbx
 ret
.validate_ok:
 xor eax,eax
 ret
.validate_usage:
 mov eax,VCS_ERR_USAGE
 ret
.validate_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

; RDI=vcs_object_index_lookup. Binary search over a validated catalog.
vcs_object_index_find:
 push rbx
 push r12
 push r13
 push r14
 push r15
 test rdi,rdi
 jz .find_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_object_index_lookup.records]
 mov r13,[rbx+vcs_object_index_lookup.record_count]
 mov r14,[rbx+vcs_object_index_lookup.object_id]
 test r14,r14
 jz .find_usage
 mov rdi,r12
 mov rsi,r13
 call vcs_object_index_validate
 test eax,eax
 jnz .find_done
 xor r15d,r15d                    ; lower bound
.find_loop:
 cmp r15,r13
 jae .find_missing
 mov rax,r15
 add rax,r13
 shr rax,1
 mov rdx,rax
 shl rax,6
 lea rdi,[r12+rax]
 mov rsi,r14
 call index_id_compare
 test eax,eax
 jz .find_hit
 js .find_raise_lower
 mov r13,rdx
 jmp .find_loop
.find_raise_lower:
 lea r15,[rdx+1]
 jmp .find_loop
.find_hit:
 mov [rbx+vcs_object_index_lookup.result],rdi
 xor eax,eax
 jmp .find_done
.find_missing:
 mov eax,VCS_ERR_NOT_FOUND
 jmp .find_done
.find_usage:
 mov eax,VCS_ERR_USAGE
.find_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=vcs_object_index_merge. Validates both inputs and every duplicate through
; verify_equal before copying anything. Existing records win exact duplicates.
vcs_object_index_merge_plan:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,40
 test rdi,rdi
 jz .merge_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_object_index_merge.existing]
 mov r13,[rbx+vcs_object_index_merge.existing_count]
 mov r14,[rbx+vcs_object_index_merge.inserts]
 mov r15,[rbx+vcs_object_index_merge.insert_count]
 mov rdi,r12
 mov rsi,r13
 call vcs_object_index_validate
 test eax,eax
 jnz .merge_done
 mov rdi,r14
 mov rsi,r15
 call vcs_object_index_validate
 test eax,eax
 jnz .merge_done
 mov qword [rsp],0                 ; existing index
 mov qword [rsp+8],0               ; insert index
 mov qword [rsp+16],0              ; merged count
.merge_preflight_loop:
 mov r8,[rsp]
 mov r9,[rsp+8]
 cmp r8,r13
 jae .merge_preflight_existing_end
 cmp r9,r15
 jae .merge_preflight_insert_end
 mov rax,r8
 shl rax,6
 lea rdi,[r12+rax]
 mov rax,r9
 shl rax,6
 lea rsi,[r14+rax]
 call index_id_compare
 test eax,eax
 jz .merge_preflight_duplicate
 js .merge_preflight_take_existing
 inc qword [rsp+8]
 inc qword [rsp+16]
 jmp .merge_preflight_loop
.merge_preflight_take_existing:
 inc qword [rsp]
 inc qword [rsp+16]
 jmp .merge_preflight_loop
.merge_preflight_duplicate:
 mov eax,[rdi+vcs_object_index_record.object_type]
 cmp eax,[rsi+vcs_object_index_record.object_type]
 jne .merge_corrupt
 mov rax,[rdi+vcs_object_index_record.payload_length]
 cmp rax,[rsi+vcs_object_index_record.payload_length]
 jne .merge_corrupt
 mov rax,[rbx+vcs_object_index_merge.verify_equal]
 test rax,rax
 jz .merge_corrupt
 mov rdx,[rbx+vcs_object_index_merge.context]
 call rax
 test eax,eax
 jnz .merge_done
 inc qword [rsp]
 inc qword [rsp+8]
 inc qword [rsp+16]
 jmp .merge_preflight_loop
.merge_preflight_existing_end:
 mov rax,r15
 sub rax,r9
 add [rsp+16],rax
 jc .merge_space
 jmp .merge_capacity
.merge_preflight_insert_end:
 mov rax,r13
 sub rax,r8
 add [rsp+16],rax
 jc .merge_space
.merge_capacity:
 mov rax,[rsp+16]
 cmp [rbx+vcs_object_index_merge.output_capacity],rax
 jb .merge_space
 test rax,rax
 jz .merge_success
 mov rbp,[rbx+vcs_object_index_merge.output]
 test rbp,rbp
 jz .merge_usage
 shl rax,6
 jc .merge_space
 add rax,rbp
 jc .merge_space
 mov qword [rsp],0
 mov qword [rsp+8],0
 mov qword [rsp+24],0              ; output index
.merge_copy_loop:
 mov r8,[rsp]
 mov r9,[rsp+8]
 cmp r8,r13
 jae .merge_copy_inserts
 cmp r9,r15
 jae .merge_copy_existing
 mov rax,r8
 shl rax,6
 lea rdi,[r12+rax]
 mov rax,r9
 shl rax,6
 lea rsi,[r14+rax]
 call index_id_compare
 test eax,eax
 jz .merge_copy_duplicate
 js .merge_copy_one_existing
 mov rsi,r14
 mov rax,r9
 shl rax,6
 add rsi,rax
 inc qword [rsp+8]
 jmp .merge_copy_record
.merge_copy_one_existing:
 mov rsi,r12
 mov rax,r8
 shl rax,6
 add rsi,rax
 inc qword [rsp]
 jmp .merge_copy_record
.merge_copy_duplicate:
 mov rsi,r12                       ; verified existing record wins
 mov rax,r8
 shl rax,6
 add rsi,rax
 inc qword [rsp]
 inc qword [rsp+8]
 jmp .merge_copy_record
.merge_copy_existing:
 cmp r8,r13
 jae .merge_success
 mov rsi,r12
 mov rax,r8
 shl rax,6
 add rsi,rax
 inc qword [rsp]
 jmp .merge_copy_record
.merge_copy_inserts:
 cmp r9,r15
 jae .merge_success
 mov rsi,r14
 mov rax,r9
 shl rax,6
 add rsi,rax
 inc qword [rsp+8]
.merge_copy_record:
 mov rax,[rsp+24]
 shl rax,6
 lea rdi,[rbp+rax]
 mov ecx,8
 rep movsq
 inc qword [rsp+24]
 jmp .merge_copy_loop
.merge_success:
 mov rax,[rsp+16]
 mov [rbx+vcs_object_index_merge.result_count],rax
 xor eax,eax
 jmp .merge_done
.merge_space:
 mov eax,VCS_ERR_NO_MEM
 jmp .merge_done
.merge_usage:
 mov eax,VCS_ERR_USAGE
 jmp .merge_done
.merge_corrupt:
 mov eax,VCS_ERR_CORRUPT
.merge_done:
 add rsp,40
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=vcs_object_index_root. Hashes kind-5 generation and canonical records.
vcs_object_index_root_hash:
 push rbx
 push r12
 push r13
 push r14
 test rdi,rdi
 jz .root_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_object_index_root.records]
 mov r13,[rbx+vcs_object_index_root.record_count]
 mov r14,[rbx+vcs_object_index_root.root_hash]
 test r14,r14
 jz .root_usage
 cmp qword [rbx+vcs_object_index_root.generation],0
 je .root_corrupt
 mov rdi,r12
 mov rsi,r13
 call vcs_object_index_validate
 test eax,eax
 jnz .root_done
 mov rax,r13
 shl rax,6
 jc .root_corrupt
 push rax
 lea rdi,[index_hash_context]
 call sha256_init
 lea rdi,[index_hash_context]
 lea rsi,[index_root_frame]
 mov edx,index_root_frame_size
 call sha256_update
 lea rdi,[index_hash_context]
 lea rsi,[rbx+vcs_object_index_root.generation]
 mov edx,8
 call sha256_update
 lea rdi,[index_hash_context]
 mov rsi,rsp
 mov edx,8
 call sha256_update
 mov rdx,[rsp]
 test rdx,rdx
 jz .root_records_done
 lea rdi,[index_hash_context]
 mov rsi,r12
 call sha256_update
.root_records_done:
 lea rdi,[index_hash_context]
 mov rsi,r14
 call sha256_final
 add rsp,8
 xor eax,eax
 jmp .root_done
.root_usage:
 mov eax,VCS_ERR_USAGE
 jmp .root_done
.root_corrupt:
 mov eax,VCS_ERR_CORRUPT
.root_done:
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI=vcs_object_index_root. Recomputes and constant-time compares root_hash.
vcs_object_index_root_verify:
 push rbx
 test rdi,rdi
 jz .root_verify_usage
 mov rbx,rdi
 cmp qword [rbx+vcs_object_index_root.root_hash],0
 je .root_verify_usage
 sub rsp,vcs_object_index_root_size
 mov rax,[rbx+vcs_object_index_root.records]
 mov [rsp+vcs_object_index_root.records],rax
 mov rax,[rbx+vcs_object_index_root.record_count]
 mov [rsp+vcs_object_index_root.record_count],rax
 mov rax,[rbx+vcs_object_index_root.generation]
 mov [rsp+vcs_object_index_root.generation],rax
 lea rax,[index_hash_digest]
 mov [rsp+vcs_object_index_root.root_hash],rax
 mov rdi,rsp
 call vcs_object_index_root_hash
 test eax,eax
 jnz .root_verify_pop
 lea rdi,[index_hash_digest]
 mov rsi,[rbx+vcs_object_index_root.root_hash]
 call index_ids_equal
 test eax,eax
 jnz .root_verify_ok
 mov eax,VCS_ERR_CORRUPT
 jmp .root_verify_pop
.root_verify_ok:
 xor eax,eax
.root_verify_pop:
 add rsp,vcs_object_index_root_size
 pop rbx
 ret
.root_verify_usage:
 mov eax,VCS_ERR_USAGE
 pop rbx
 ret

; RDI=vcs_object_index_verified_lookup. Authenticates the complete generation
; before binary lookup; lookup.result remains untouched on root failure.
vcs_object_index_verified_find:
 push rbx
 test rdi,rdi
 jz .verified_usage
 mov rbx,rdi
 mov rdi,[rbx+vcs_object_index_verified_lookup.root]
 test rdi,rdi
 jz .verified_usage
 call vcs_object_index_root_verify
 test eax,eax
 jnz .verified_done
 mov rdi,[rbx+vcs_object_index_verified_lookup.lookup]
 test rdi,rdi
 jz .verified_usage
 call vcs_object_index_find
 jmp .verified_done
.verified_usage:
 mov eax,VCS_ERR_USAGE
.verified_done:
 pop rbx
 ret

index_record_validate:
 mov rax,[rdi+vcs_object_index_record.object_id]
 or rax,[rdi+vcs_object_index_record.object_id+8]
 or rax,[rdi+vcs_object_index_record.object_id+16]
 or rax,[rdi+vcs_object_index_record.object_id+24]
 jz .record_bad
 cmp qword [rdi+vcs_object_index_record.envelope],0
 je .record_bad
 mov eax,[rdi+vcs_object_index_record.object_type]
 test eax,eax
 jz .record_bad
 cmp eax,VCS_OBJ_TREE_PAGE
 ja .record_bad
 cmp dword [rdi+vcs_object_index_record.flags],0
 jne .record_bad
 cmp qword [rdi+vcs_object_index_record.transaction],0
 je .record_bad
 xor eax,eax
 ret
.record_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

; RDI/SI point to records or raw 32-byte IDs. Compare unsigned ID bytes.
index_id_compare:
 xor ecx,ecx
.id_loop:
 cmp ecx,32
 jae .id_equal
 mov al,[rdi+rcx]
 cmp al,[rsi+rcx]
 jb .id_less
 ja .id_greater
 inc ecx
 jmp .id_loop
.id_equal:
 xor eax,eax
 ret
.id_less:
 mov eax,-1
 ret
.id_greater:
 mov eax,1
 ret

index_ids_equal:
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
