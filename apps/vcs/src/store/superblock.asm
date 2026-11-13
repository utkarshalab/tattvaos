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
global vcs_superblock_seal,vcs_superblock_verify

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

section .note.GNU-stack noalloc noexec nowrite progbits
