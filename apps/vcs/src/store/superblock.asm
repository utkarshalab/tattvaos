; Exact format-v3 repository superblock sealing and verification.
%include "include/vcs.inc"
%define VCS_SUPERBLOCK_IMPLEMENTATION
%include "include/superblock.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

extern sha256_init,sha256_update,sha256_final

section .rodata
superblock_magic: db 'UVCSREP3'

section .bss
alignb 16
superblock_hash_context: resb sha256_ctx_t_size
superblock_hash_digest: resb SHA256_DIGEST_SIZE

section .text
global vcs_superblock_seal,vcs_superblock_verify,vcs_superblock_select_latest

; RDI=512-byte superblock. Validates all semantic fields before publishing the
; checksum, so invalid input remains untouched.
vcs_superblock_seal:
 push rbx
 test rdi,rdi
 jz .seal_usage
 mov rbx,rdi
 call superblock_validate_fields
 test eax,eax
 jnz .seal_done
 lea rdi,[superblock_hash_context]
 call sha256_init
 lea rdi,[superblock_hash_context]
 mov rsi,rbx
 mov edx,VCS_SUPERBLOCK_CHECKSUM_AT
 call sha256_update
 lea rdi,[superblock_hash_context]
 lea rsi,[rbx+vcs_superblock.checksum]
 call sha256_final
 xor eax,eax
 jmp .seal_done
.seal_usage:
 mov eax,VCS_ERR_USAGE
.seal_done:
 pop rbx
 ret

; RDI=512-byte superblock. Validates fields and constant-time checksum equality.
vcs_superblock_verify:
 push rbx
 test rdi,rdi
 jz .verify_usage
 mov rbx,rdi
 call superblock_validate_fields
 test eax,eax
 jnz .verify_done
 lea rdi,[superblock_hash_context]
 call sha256_init
 lea rdi,[superblock_hash_context]
 mov rsi,rbx
 mov edx,VCS_SUPERBLOCK_CHECKSUM_AT
 call sha256_update
 lea rdi,[superblock_hash_context]
 lea rsi,[superblock_hash_digest]
 call sha256_final
 lea rdi,[superblock_hash_digest]
 lea rsi,[rbx+vcs_superblock.checksum]
 call superblock_ids_equal
 test eax,eax
 jz .verify_corrupt
 xor eax,eax
 jmp .verify_done
.verify_usage:
 mov eax,VCS_ERR_USAGE
 jmp .verify_done
.verify_corrupt:
 mov eax,VCS_ERR_CORRUPT
.verify_done:
 pop rbx
 ret

; RDI=vcs_superblock_select. Selects the newest compatible valid generation.
; One invalid slot is treated as a torn candidate. Equal-generation divergent
; slots are ambiguous and fail rather than choosing by position.
vcs_superblock_select_latest:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .select_usage
 mov rbx,rdi
 mov r12,[rbx+vcs_superblock_select.first]
 mov r13,[rbx+vcs_superblock_select.second]
 xor r14d,r14d
 xor r15d,r15d
 test r12,r12
 jz .select_second
 mov rdi,r12
 call vcs_superblock_verify
 test eax,eax
 setz r14b
.select_second:
 test r13,r13
 jz .select_validity
 mov rdi,r13
 call vcs_superblock_verify
 test eax,eax
 setz r15b
.select_validity:
 test r14b,r14b
 jz .select_only_second
 test r15b,r15b
 jz .select_first
 ; Both candidates belong to the same repository and immutable format policy.
 lea rdi,[r12+vcs_superblock.uuid]
 lea rsi,[r13+vcs_superblock.uuid]
 mov ecx,16
 call superblock_bytes_equal
 test eax,eax
 jz .select_corrupt
 mov eax,[r12+vcs_superblock.hash_algorithm]
 cmp eax,[r13+vcs_superblock.hash_algorithm]
 jne .select_corrupt
 mov eax,[r12+vcs_superblock.block_size]
 cmp eax,[r13+vcs_superblock.block_size]
 jne .select_corrupt
 mov rax,[r12+vcs_superblock.created_ns]
 cmp rax,[r13+vcs_superblock.created_ns]
 jne .select_corrupt
 mov rax,[r12+vcs_superblock.generation]
 cmp rax,[r13+vcs_superblock.generation]
 jb .select_second_newer
 ja .select_first_newer
 mov rdi,r12
 mov rsi,r13
 mov ecx,VCS_SUPERBLOCK_BYTES
 call superblock_bytes_equal
 test eax,eax
 jz .select_ambiguous
 jmp .select_first
.select_first_newer:
 mov rbp,r12
 mov rdx,r13
 jmp .select_monotonic
.select_second_newer:
 mov rbp,r13
 mov rdx,r12
.select_monotonic:
 ; A newer generation may enable a known optional feature, but it may not
 ; discard a feature required by the older published generation.
 mov rax,[rdx+vcs_superblock.features]
 mov rcx,[rbp+vcs_superblock.features]
 and rcx,rax
 cmp rcx,rax
 jne .select_corrupt
 mov rax,[rbp+vcs_superblock.next_transaction]
 cmp rax,[rdx+vcs_superblock.next_transaction]
 jbe .select_corrupt
 mov rax,[rbp+vcs_superblock.operation_sequence]
 cmp rax,[rdx+vcs_superblock.operation_sequence]
 jb .select_corrupt
 mov r12,rbp
 jmp .select_first
.select_only_second:
 test r15b,r15b
 jnz .select_second_result
 mov eax,VCS_ERR_CORRUPT
 jmp .select_done
.select_second_result:
 mov r12,r13
.select_first:
 mov [rbx+vcs_superblock_select.result],r12
 mov rax,[r12+vcs_superblock.generation]
 mov [rbx+vcs_superblock_select.result_generation],rax
 xor eax,eax
 jmp .select_done
.select_ambiguous:
 mov eax,VCS_ERR_CONFLICT
 jmp .select_done
.select_usage:
 mov eax,VCS_ERR_USAGE
 jmp .select_done
.select_corrupt:
 mov eax,VCS_ERR_CORRUPT
.select_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

superblock_validate_fields:
 mov rax,[superblock_magic]
 cmp [rdi+vcs_superblock.magic],rax
 jne .fields_bad
 cmp dword [rdi+vcs_superblock.version],3
 jne .fields_bad
 cmp dword [rdi+vcs_superblock.header_bytes],VCS_SUPERBLOCK_BYTES
 jne .fields_bad
 mov rax,[rdi+vcs_superblock.features]
 mov rcx,rax
 and rcx,~VCS_SUPERBLOCK_FEATURES
 jnz .fields_bad
 and eax,VCS_SUPERBLOCK_REQUIRED
 cmp eax,VCS_SUPERBLOCK_REQUIRED
 jne .fields_bad
 cmp qword [rdi+vcs_superblock.generation],0
 je .fields_bad
 lea rsi,[rdi+vcs_superblock.uuid]
 mov ecx,16
 call bytes_nonzero
 test eax,eax
 jz .fields_bad
 cmp dword [rdi+vcs_superblock.hash_algorithm],1
 jne .fields_bad
 cmp dword [rdi+vcs_superblock.block_size],4096
 jne .fields_bad
 lea rsi,[rdi+vcs_superblock.ref_root]
 mov ecx,32
 call bytes_nonzero
 test eax,eax
 jz .fields_bad
 lea rsi,[rdi+vcs_superblock.ownership_root]
 mov ecx,32
 call bytes_nonzero
 test eax,eax
 jz .fields_bad
 lea rsi,[rdi+vcs_superblock.object_index_root]
 mov ecx,32
 call bytes_nonzero
 test eax,eax
 jz .fields_bad
 cmp qword [rdi+vcs_superblock.next_transaction],0
 je .fields_bad
 mov rax,[rdi+vcs_superblock.operation_head]
 or rax,[rdi+vcs_superblock.operation_head+8]
 or rax,[rdi+vcs_superblock.operation_head+16]
 or rax,[rdi+vcs_superblock.operation_head+24]
 jz .operation_ok
 test qword [rdi+vcs_superblock.features],8
 jz .fields_bad
.operation_ok:
 lea rsi,[rdi+vcs_superblock.reserved]
 mov ecx,208
.reserved_loop:
 test ecx,ecx
 jz .fields_ok
 cmp byte [rsi],0
 jne .fields_bad
 inc rsi
 dec ecx
 jmp .reserved_loop
.fields_ok:
 xor eax,eax
 ret
.fields_bad:
 mov eax,VCS_ERR_CORRUPT
 ret

bytes_nonzero:
 xor eax,eax
.nonzero_loop:
 test ecx,ecx
 jz .nonzero_done
 or al,[rsi]
 inc rsi
 dec ecx
 jmp .nonzero_loop
.nonzero_done:
 test al,al
 setnz al
 movzx eax,al
 ret

superblock_ids_equal:
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

superblock_bytes_equal:
 xor eax,eax
 xor edx,edx
.bytes_loop:
 cmp rdx,rcx
 jae .bytes_equal
 mov r8b,[rdi+rdx]
 xor r8b,[rsi+rdx]
 or al,r8b
 inc rdx
 jmp .bytes_loop
.bytes_equal:
 test al,al
 setz al
 movzx eax,al
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
