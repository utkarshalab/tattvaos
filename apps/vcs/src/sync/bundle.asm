; Portable single-commit bundle export and validation. Import validation is
; deliberately side-effect free; publication/remapping is a separate step.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/bundle.inc"
%include "include/wire.inc"
%include "storage/uxfs/volume.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel

extern uxv_ready,uxv_nodes,uxv_find,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_object_name
extern vcs_repo_head,vcs_repo_last,vcs_repo_format,vcs_object_path
extern sha256_init,sha256_update,sha256_final
extern signing_verify,signing_sign,signing_public_from_seed
extern vcs_signature_policy,vcs_signature_prepare
extern vcs_identity_trust_key

section .bss
global vcs_bundle_manifest_ptr,vcs_bundle_manifest_bytes
global vcs_bundle_digest_ptr,vcs_bundle_signature_ptr
global vcs_bundle_blob_count,vcs_bundle_blob_ids,vcs_bundle_blob_ptrs
global vcs_bundle_blob_sizes
vcs_bundle_manifest_ptr:
bundle_manifest: resq 1
vcs_bundle_manifest_bytes:
bundle_manifest_size: resq 1
vcs_bundle_digest_ptr:
bundle_digest: resq 1
bundle_parent_digest: resq 1
vcs_bundle_signature_ptr:
bundle_signature: resq 1
bundle_output: resq 1
bundle_capacity: resq 1
bundle_cursor: resq 1
bundle_count: resq 1
bundle_tip: resq 1
bundle_blob_ptrs: resq VR_FILES
bundle_blob_sizes: resq VR_FILES
publish_nodes: resq (VR_FILES+4)
publish_node_count: resq 1
publish_manifest: resb 4096
vcs_bundle_blob_count:
parse_blob_count: resq 1
vcs_bundle_blob_ids:
parse_blob_ids: resq VR_FILES
vcs_bundle_blob_ptrs:
parse_blob_ptrs: resq VR_FILES
vcs_bundle_blob_sizes:
parse_blob_sizes: resq VR_FILES
alignb 16
bundle_hash: resb sha256_ctx_t_size
bundle_hash_out: resb 32

section .rodata
hash_domain: db 'UVCSCHK1'

section .text
global vcs_bundle_export,vcs_bundle_validate,vcs_bundle_publish
global vcs_bundle_seal,vcs_bundle_open

; Create a contiguous signed wire frame around a validated bundle payload.
; RDI=output, RSI=capacity, RDX=payload, RCX=payload length,
; R8D=wire operation, R9=seed32. RAX=status, RDX=frame length.
vcs_bundle_seal:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 mov r15,r9
 test rbx,rbx
 jz .seal_usage
 test r13,r13
 jz .seal_usage
 test r15,r15
 jz .seal_usage
 cmp r14,VCS_WIRE_MAX_PAYLOAD
 ja .seal_usage
 cmp r8d,VCS_WIRE_FETCH
 jb .seal_usage
 cmp r8d,VCS_WIRE_PATCH
 ja .seal_usage
 lea rax,[r14+VCS_WIRE_HEADER]
 cmp rax,r12
 ja .seal_capacity
 push r8
 mov rdi,r13
 mov rsi,r14
 call vcs_bundle_validate
 pop r8
 test eax,eax
 jnz .seal_done
 mov rdi,rbx
 xor eax,eax
 mov ecx,VCS_WIRE_HEADER/8
 rep stosq
 mov rax,VCS_WIRE_MAGIC
 mov [rbx+VW_MAGIC],rax
 mov dword [rbx+VW_VERSION],VCS_WIRE_VERSION
 mov [rbx+VW_OPERATION],r8d
 mov [rbx+VW_PAYLOAD],r14
 mov rax,[r13+VBH_RECORDS]
 mov [rbx+VW_OBJECTS],rax
 mov qword [rbx+VW_REPOSITORY],0
 lea rdi,[bundle_hash]
 call sha256_init
 lea rdi,[bundle_hash]
 mov rsi,rbx
 mov edx,VW_DIGEST
 call sha256_update
 lea rdi,[bundle_hash]
 mov rsi,r13
 mov rdx,r14
 call sha256_update
 lea rdi,[bundle_hash]
 lea rsi,[bundle_hash_out]
 call sha256_final
 lea rdi,[rbx+VW_DIGEST]
 lea rsi,[bundle_hash_out]
 mov ecx,32
 rep movsb
 lea rdi,[rbx+VW_PUBLIC]
 mov rsi,r15
 call signing_public_from_seed
 test eax,eax
 jnz .seal_corrupt
 lea rdi,[rbx+VW_DIGEST]
 mov rsi,r15
 lea rdx,[rbx+VW_SIGNATURE]
 call signing_sign
 test eax,eax
 jnz .seal_corrupt
 lea rdi,[rbx+VCS_WIRE_HEADER]
 mov rsi,r13
 mov rcx,r14
 rep movsb
 lea rdx,[r14+VCS_WIRE_HEADER]
 xor eax,eax
 jmp .seal_done
.seal_usage: mov eax,VCS_ERR_USAGE
 jmp .seal_done
.seal_capacity: mov eax,VCS_ERR_NO_MEM
 jmp .seal_done
.seal_corrupt: mov eax,VCS_ERR_CORRUPT
.seal_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; Verify a complete trusted wire frame and its enclosed bundle.
; RDI=frame, RSI=length. RAX=status, RDX=payload, RCX=payload length,
; R8D=operation.
vcs_bundle_open:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 test rbx,rbx
 jz .open_usage
 cmp r12,VCS_WIRE_HEADER
 jb .open_corrupt
 mov rax,VCS_WIRE_MAGIC
 cmp [rbx+VW_MAGIC],rax
 jne .open_corrupt
 cmp dword [rbx+VW_VERSION],VCS_WIRE_VERSION
 jne .open_corrupt
 mov r13d,[rbx+VW_OPERATION]
 cmp r13d,VCS_WIRE_FETCH
 jb .open_corrupt
 cmp r13d,VCS_WIRE_PATCH
 ja .open_corrupt
 mov rcx,[rbx+VW_PAYLOAD]
 test rcx,rcx
 jz .open_corrupt
 cmp rcx,VCS_WIRE_MAX_PAYLOAD
 ja .open_corrupt
 lea rax,[rcx+VCS_WIRE_HEADER]
 cmp rax,r12
 jne .open_corrupt
 lea rdi,[bundle_hash]
 call sha256_init
 lea rdi,[bundle_hash]
 mov rsi,rbx
 mov edx,VW_DIGEST
 call sha256_update
 lea rdi,[bundle_hash]
 lea rsi,[rbx+VCS_WIRE_HEADER]
 mov rdx,[rbx+VW_PAYLOAD]
 call sha256_update
 lea rdi,[bundle_hash]
 lea rsi,[bundle_hash_out]
 call sha256_final
 lea rdi,[bundle_hash_out]
 lea rsi,[rbx+VW_DIGEST]
 mov ecx,32
 repe cmpsb
 jne .open_corrupt
 lea rdi,[rbx+VW_PUBLIC]
 call vcs_identity_trust_key
 test eax,eax
 jnz .open_done
 lea rdi,[rbx+VW_DIGEST]
 lea rsi,[rbx+VW_SIGNATURE]
 lea rdx,[rbx+VW_PUBLIC]
 call signing_verify
 test eax,eax
 jnz .open_permission
 lea rdi,[rbx+VCS_WIRE_HEADER]
 mov rsi,[rbx+VW_PAYLOAD]
 call vcs_bundle_validate
 test eax,eax
 jnz .open_done
 lea rdx,[rbx+VCS_WIRE_HEADER]
 mov rcx,[rbx+VW_PAYLOAD]
 mov r8d,r13d
 xor eax,eax
 jmp .open_done
.open_usage: mov eax,VCS_ERR_USAGE
 jmp .open_done
.open_corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .open_done
.open_permission: mov eax,VCS_ERR_PERM
.open_done:
 pop r13
 pop r12
 pop rbx
 ret

; Export one locally valid commit into a portable payload.
; rdi=commit ID (zero selects HEAD), rsi=output, rdx=capacity.
; rax=status, rdx=written bytes, rcx=record count.
vcs_bundle_export:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov [bundle_output],rsi
 mov [bundle_capacity],rdx
 test rsi,rsi
 jz .export_usage
 cmp qword [uxv_ready],1
 jne .export_io
 call vcs_repo_discover
 test eax,eax
 jnz .export_done
 test rbp,rbp
 jnz .export_id
 mov rbp,[vcs_repo_head]
.export_id:
 test rbp,rbp
 jz .export_missing
 cmp rbp,[vcs_repo_last]
 ja .export_missing
 mov rdi,rbp
 call vcs_load_manifest
 test rax,rax
 jz .export_corrupt
 mov [bundle_manifest],rax
 mov r12,[rax+24]
 mov rcx,r12
 inc rcx
 shl rcx,8
 mov [bundle_manifest_size],rcx
 mov qword [bundle_parent_digest],0
 mov rax,[rax+16]
 test rax,rax
 jz .export_digest
 mov rdi,rax
 mov sil,'h'
 call find_object
 test rax,rax
 jz .export_corrupt
 cmp qword [rax+UV_SIZE],32
 jne .export_corrupt
 lea rax,[rax+UV_DATA]
 mov [bundle_parent_digest],rax
.export_digest:
 mov rdi,rbp
 mov sil,'h'
 call find_object
 test rax,rax
 jz .export_corrupt
 cmp qword [rax+UV_SIZE],32
 jne .export_corrupt
 lea rax,[rax+UV_DATA]
 mov [bundle_digest],rax
 mov qword [bundle_signature],0
 mov rdi,rbp
 mov sil,'s'
 call find_object
 test rax,rax
 jz .export_blobs
 cmp qword [rax+UV_SIZE],VR_SIG_SIZE
 jne .export_corrupt
 mov rdx,VR_SIG_MAGIC
 cmp [rax+UV_DATA],rdx
 jne .export_corrupt
 cmp qword [rax+UV_DATA+8],1
 jne .export_corrupt
 cmp [rax+UV_DATA+16],rbp
 jne .export_corrupt
 lea rax,[rax+UV_DATA]
 mov [bundle_signature],rax
.export_blobs:
 mov r13,[bundle_manifest]
 add r13,VR_HEADER
 xor r14d,r14d
 mov r15,VB_HEADER
 add r15,VB_RECORD
 add r15,[bundle_manifest_size]
 add r15,VB_RECORD+32
 cmp qword [bundle_signature],0
 je .export_blob_loop
 add r15,VB_RECORD+VR_SIG_SIZE
.export_blob_loop:
 cmp r14,r12
 jae .export_preflight
 mov rdi,[r13+VR_BLOB]
 mov sil,'b'
 call find_object
 test rax,rax
 jz .export_corrupt
 mov rcx,[r13+VR_SIZE]
 cmp [rax+UV_SIZE],rcx
 jne .export_corrupt
 lea rdx,[rax+UV_DATA]
 lea rax,[bundle_blob_ptrs]
 mov [rax+r14*8],rdx
 lea rax,[bundle_blob_sizes]
 mov [rax+r14*8],rcx
 add r15,VB_RECORD
 add r15,rcx
 add r13,VR_ENTRY
 inc r14
 jmp .export_blob_loop
.export_preflight:
 cmp r15,VCS_WIRE_MAX_PAYLOAD
 ja .export_capacity
 cmp r15,[bundle_capacity]
 ja .export_capacity
 mov rax,r12
 add rax,2
 cmp qword [bundle_signature],0
 je .export_count
 inc rax
.export_count:
 mov [bundle_count],rax
 mov rdi,[bundle_output]
 xor eax,eax
 mov ecx,VB_HEADER/8
 rep stosq
 mov rax,VB_MAGIC
 mov [rdi-VB_HEADER+VBH_MAGIC],rax
 mov qword [rdi-VB_HEADER+VBH_VERSION],VB_VERSION
 mov [rdi-VB_HEADER+VBH_TOTAL],r15
 mov rax,[bundle_count]
 mov [rdi-VB_HEADER+VBH_RECORDS],rax
 mov [rdi-VB_HEADER+VBH_TIP],rbp
 mov rax,[bundle_manifest]
 mov rax,[rax+16]
 mov [rdi-VB_HEADER+VBH_PARENT],rax
 mov rsi,[bundle_parent_digest]
 test rsi,rsi
 jz .export_parent_hash_done
 lea rdi,[rdi-VB_HEADER+VBH_PARENT_HASH]
 mov ecx,32
 rep movsb
 mov rdi,[bundle_output]
 add rdi,VB_HEADER
.export_parent_hash_done:
 cmp qword [bundle_signature],0
 je .export_header_done
 mov qword [rdi-VB_HEADER+VBH_FLAGS],VB_FLAG_SIGNED
.export_header_done:
 mov [bundle_cursor],rdi
 mov edi,VB_KIND_COMMIT
 mov rsi,rbp
 mov rdx,[bundle_manifest]
 mov rcx,[bundle_manifest_size]
 call append_record
 mov edi,VB_KIND_HASH
 mov rsi,rbp
 mov rdx,[bundle_digest]
 mov ecx,32
 call append_record
 cmp qword [bundle_signature],0
 je .export_write_blobs
 mov edi,VB_KIND_SIGN
 mov rsi,rbp
 mov rdx,[bundle_signature]
 mov ecx,VR_SIG_SIZE
 call append_record
.export_write_blobs:
 mov r13,[bundle_manifest]
 add r13,VR_HEADER
 xor r14d,r14d
.export_write_loop:
 cmp r14,r12
 jae .export_ok
 mov edi,VB_KIND_BLOB
 mov rsi,[r13+VR_BLOB]
 lea rax,[bundle_blob_ptrs]
 mov rdx,[rax+r14*8]
 lea rax,[bundle_blob_sizes]
 mov rcx,[rax+r14*8]
 call append_record
 add r13,VR_ENTRY
 inc r14
 jmp .export_write_loop
.export_ok:
 mov rdx,r15
 mov rcx,[bundle_count]
 xor eax,eax
 jmp .export_done
.export_usage: mov eax,VCS_ERR_USAGE
 jmp .export_done
.export_missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .export_done
.export_capacity: mov eax,VCS_ERR_NO_MEM
 jmp .export_done
.export_corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .export_done
.export_io: mov eax,VCS_ERR_IO
.export_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Validate a complete bundle without modifying repository or worktree state.
; rdi=payload, rsi=length. rax=status, rdx=tip, rcx=parent, r8=flags.
vcs_bundle_validate:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r15,rsi
 test rbp,rbp
 jz .parse_usage
 cmp r15,VB_HEADER
 jb .parse_corrupt
 cmp r15,VCS_WIRE_MAX_PAYLOAD
 ja .parse_corrupt
 mov rax,VB_MAGIC
 cmp [rbp+VBH_MAGIC],rax
 jne .parse_corrupt
 cmp qword [rbp+VBH_VERSION],VB_VERSION
 jne .parse_corrupt
 cmp [rbp+VBH_TOTAL],r15
 jne .parse_corrupt
 mov r12,[rbp+VBH_RECORDS]
 cmp r12,2
 jb .parse_corrupt
 cmp r12,VB_MAX_RECORDS
 ja .parse_corrupt
 mov [bundle_tip],r12
 mov r14,[rbp+VBH_TIP]
 test r14,r14
 jz .parse_corrupt
 mov rax,[rbp+VBH_FLAGS]
 test rax,~VB_FLAG_SIGNED
 jnz .parse_corrupt
 cmp qword [rbp+VBH_RESERVED],0
 jne .parse_corrupt
 cmp qword [rbp+VBH_PARENT],0
 jne .parse_parent_hash
 mov rax,[rbp+VBH_PARENT_HASH]
 or rax,[rbp+VBH_PARENT_HASH+8]
 or rax,[rbp+VBH_PARENT_HASH+16]
 or rax,[rbp+VBH_PARENT_HASH+24]
 jnz .parse_corrupt
 jmp .parse_parent_hash_done
.parse_parent_hash:
 mov rax,[rbp+VBH_PARENT_HASH]
 or rax,[rbp+VBH_PARENT_HASH+8]
 or rax,[rbp+VBH_PARENT_HASH+16]
 or rax,[rbp+VBH_PARENT_HASH+24]
 jz .parse_corrupt
.parse_parent_hash_done:
 lea r13,[rbp+VB_HEADER]
 mov qword [bundle_manifest],0
 mov qword [bundle_digest],0
 mov qword [bundle_signature],0
 mov qword [parse_blob_count],0
.parse_record:
 test r12,r12
 jz .parse_records_done
 lea rax,[rbp+r15]
 mov rcx,rax
 sub rcx,r13
 cmp rcx,VB_RECORD
 jb .parse_corrupt
 mov rax,[r13+VBR_SIZE]
 cmp rax,4096
 ja .parse_corrupt
 mov [bundle_capacity],rax
 lea rdx,[r13+VB_RECORD]
 lea rcx,[rdx+rax]
 lea rbx,[rbp+r15]
 cmp rcx,rbx
 ja .parse_corrupt
 mov r9,[r13+VBR_KIND]
 cmp r9,VB_KIND_COMMIT
 je .parse_commit
 cmp r9,VB_KIND_HASH
 je .parse_hash
 cmp r9,VB_KIND_SIGN
 je .parse_sign
 cmp r9,VB_KIND_BLOB
 je .parse_blob
 jmp .parse_corrupt
.parse_commit:
 cmp qword [bundle_manifest],0
 jne .parse_corrupt
 cmp [r13+VBR_ID],r14
 jne .parse_corrupt
 cmp rax,VR_HEADER
 jb .parse_corrupt
 mov [bundle_manifest],rdx
 mov [bundle_manifest_size],rax
 jmp .parse_next
.parse_hash:
 cmp qword [bundle_digest],0
 jne .parse_corrupt
 cmp [r13+VBR_ID],r14
 jne .parse_corrupt
 cmp rax,32
 jne .parse_corrupt
 mov [bundle_digest],rdx
 jmp .parse_next
.parse_sign:
 cmp qword [bundle_signature],0
 jne .parse_corrupt
 cmp [r13+VBR_ID],r14
 jne .parse_corrupt
 cmp rax,VR_SIG_SIZE
 jne .parse_corrupt
 mov [bundle_signature],rdx
 jmp .parse_next
.parse_blob:
 mov rcx,[parse_blob_count]
 cmp rcx,VR_FILES
 jae .parse_corrupt
 lea rbx,[parse_blob_ids]
 mov r10,[r13+VBR_ID]
 test r10,r10
 jz .parse_corrupt
 xor r11d,r11d
.parse_blob_unique:
 cmp r11,rcx
 jae .parse_blob_store
 cmp [rbx+r11*8],r10
 je .parse_corrupt
 inc r11
 jmp .parse_blob_unique
.parse_blob_store:
 mov [rbx+rcx*8],r10
 lea rbx,[parse_blob_ptrs]
 mov [rbx+rcx*8],rdx
 lea rbx,[parse_blob_sizes]
 mov [rbx+rcx*8],rax
 inc qword [parse_blob_count]
.parse_next:
 add r13,VB_RECORD
 add r13,[bundle_capacity]
 dec r12
 jmp .parse_record
.parse_records_done:
 lea rax,[rbp+r15]
 cmp r13,rax
 jne .parse_corrupt
 cmp qword [bundle_manifest],0
 je .parse_corrupt
 cmp qword [bundle_digest],0
 je .parse_corrupt
 mov rax,[parse_blob_count]
 add rax,2
 cmp qword [bundle_signature],0
 je .parse_count_ready
 inc rax
.parse_count_ready:
 cmp rax,[bundle_tip]
 jne .parse_corrupt
 mov rbx,[bundle_manifest]
 mov rax,VR_COM_MAGIC
 cmp [rbx],rax
 jne .parse_corrupt
 cmp [rbx+8],r14
 jne .parse_corrupt
 mov rax,[rbx+16]
 cmp rax,[rbp+VBH_PARENT]
 jne .parse_corrupt
 cmp rax,r14
 jae .parse_corrupt
 mov r12,[rbx+24]
 cmp r12,VR_FILES
 ja .parse_corrupt
 cmp r12,[parse_blob_count]
 jne .parse_corrupt
 mov rax,r12
 inc rax
 shl rax,8
 cmp rax,[bundle_manifest_size]
 jne .parse_corrupt
 mov rcx,[rbx+32]
 btr rcx,63
 jc .parse_corrupt              ; portable v1 carries first-parent commits
 test rcx,rcx
 jz .parse_corrupt
 cmp rcx,VR_MESSAGE_MAX
 ja .parse_corrupt
 cmp byte [rbx+VR_MESSAGE+rcx],0
 jne .parse_corrupt
 xor eax,eax
.parse_message:
 cmp rax,rcx
 jae .parse_entries
 cmp byte [rbx+VR_MESSAGE+rax],0
 je .parse_corrupt
 inc rax
 jmp .parse_message
.parse_entries:
 lea r13,[rbx+VR_HEADER]
 xor r15d,r15d
.parse_entry:
 cmp r15,r12
 jae .parse_hash_bundle
 mov rdi,r13
 call valid_relative
 test eax,eax
 jz .parse_corrupt
 mov r11,[bundle_manifest]
 add r11,VR_HEADER
 xor r10d,r10d
.parse_unique_path:
 cmp r10,r15
 jae .parse_unique_done
 mov rdi,r13
 mov rsi,r11
 call same_name
 test eax,eax
 jnz .parse_corrupt
 add r11,VR_ENTRY
 inc r10
 jmp .parse_unique_path
.parse_unique_done:
 mov r10,[r13+VR_BLOB]
 mov rax,r10
 shr rax,8
 test rax,rax
 jz .parse_corrupt
 cmp rax,r14
 ja .parse_corrupt
 movzx eax,r10b
 test eax,eax
 jz .parse_corrupt
 cmp eax,VR_FILES
 ja .parse_corrupt
 xor r11d,r11d
.parse_find_blob:
 cmp r11,[parse_blob_count]
 jae .parse_corrupt
 lea rax,[parse_blob_ids]
 cmp [rax+r11*8],r10
 je .parse_blob_match
 inc r11
 jmp .parse_find_blob
.parse_blob_match:
 lea rax,[parse_blob_sizes]
 mov rdx,[rax+r11*8]
 cmp rdx,[r13+VR_SIZE]
 jne .parse_corrupt
 lea rax,[parse_blob_ptrs]
 mov rcx,[rax+r11*8]
 lea rax,[bundle_blob_ptrs]
 mov [rax+r15*8],rcx
 lea rax,[bundle_blob_sizes]
 mov [rax+r15*8],rdx
 add r13,VR_ENTRY
 inc r15
 jmp .parse_entry
.parse_hash_bundle:
 lea rdi,[bundle_hash]
 call sha256_init
 lea rdi,[bundle_hash]
 lea rsi,[hash_domain]
 mov edx,8
 call sha256_update
 lea rdi,[bundle_hash]
 mov rsi,[bundle_manifest]
 mov rdx,[bundle_manifest_size]
 call sha256_update
 mov r13,[bundle_manifest]
 add r13,VR_HEADER
 xor r15d,r15d
.parse_hash_blob:
 cmp r15,r12
 jae .parse_hash_final
 mov r10,[r13+VR_BLOB]
 xor r11d,r11d
.parse_hash_find:
 lea rax,[parse_blob_ids]
 cmp [rax+r11*8],r10
 je .parse_hash_found
 inc r11
 cmp r11,[parse_blob_count]
 jb .parse_hash_find
 jmp .parse_corrupt
.parse_hash_found:
 lea rax,[parse_blob_ptrs]
 mov rsi,[rax+r11*8]
 lea rax,[parse_blob_sizes]
 mov rdx,[rax+r11*8]
 lea rdi,[bundle_hash]
 call sha256_update
 add r13,VR_ENTRY
 inc r15
 jmp .parse_hash_blob
.parse_hash_final:
 lea rdi,[bundle_hash]
 lea rsi,[bundle_hash_out]
 call sha256_final
 lea rdi,[bundle_hash_out]
 mov rsi,[bundle_digest]
 mov ecx,32
 repe cmpsb
 jne .parse_corrupt
 mov r13,[bundle_signature]
 mov rax,[rbp+VBH_FLAGS]
 test rax,VB_FLAG_SIGNED
 jz .parse_unsigned
 test r13,r13
 jz .parse_corrupt
 mov rax,VR_SIG_MAGIC
 cmp [r13],rax
 jne .parse_corrupt
 cmp qword [r13+8],1
 jne .parse_corrupt
 cmp [r13+16],r14
 jne .parse_corrupt
 lea rdi,[bundle_hash_out]
 lea rsi,[r13+64]
 lea rdx,[r13+32]
 call signing_verify
 test eax,eax
 jnz .parse_permission
 jmp .parse_ok
.parse_unsigned:
 test r13,r13
 jnz .parse_corrupt
.parse_ok:
 mov rdx,r14
 mov rcx,[rbp+VBH_PARENT]
 mov r8,[rbp+VBH_FLAGS]
 xor eax,eax
 jmp .parse_done
.parse_usage: mov eax,VCS_ERR_USAGE
 jmp .parse_done
.parse_corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .parse_done
.parse_permission: mov eax,VCS_ERR_PERM
.parse_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Publish an already transport-authenticated payload as an unmoving local
; commit. RDI=payload, RSI=length, RDX=optional local signing seed.
; HEAD and refs are unchanged. RAX=status, RDX=new local commit ID.
vcs_bundle_publish:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r14,rsi
 mov r15,rdx
 call vcs_bundle_validate
 test eax,eax
 jnz .publish_done
 cmp qword [uxv_ready],1
 jne .publish_io
 call vcs_repo_discover
 test eax,eax
 jnz .publish_done
 call vcs_signature_policy
 test eax,eax
 jnz .publish_done
 test rdx,rdx
 jz .publish_parent
 test r15,r15
 jz .publish_permission
.publish_parent:
 xor r12d,r12d
 cmp qword [rbp+VBH_PARENT],0
 je .publish_parent_ready
 mov r13d,1
.publish_parent_scan:
 cmp r13,[vcs_repo_last]
 ja .publish_missing
 mov rdi,r13
 call vcs_load_manifest
 test rax,rax
 jz .publish_corrupt
 mov rdi,r13
 mov sil,'h'
 call find_object
 test rax,rax
 jz .publish_corrupt
 lea rdi,[rax+UV_DATA]
 lea rsi,[rbp+VBH_PARENT_HASH]
 mov ecx,32
 repe cmpsb
 je .publish_parent_found
 mov rdi,r13
 mov sil,'m'
 call find_object
 test rax,rax
 jz .publish_parent_next
 cmp qword [rax+UV_SIZE],48
 jne .publish_corrupt
 mov rdx,VB_MAP_MAGIC
 cmp [rax+UV_DATA],rdx
 jne .publish_corrupt
 lea rdi,[rax+UV_DATA+16]
 lea rsi,[rbp+VBH_PARENT_HASH]
 mov ecx,32
 repe cmpsb
 je .publish_parent_found
.publish_parent_next:
 inc r13
 jmp .publish_parent_scan
.publish_parent_found:
 mov r12,r13
.publish_parent_ready:
 mov r13,[vcs_repo_last]
 inc r13
 cmp r13,VR_MAX_ID
 ja .publish_capacity
 mov rcx,[bundle_manifest_size]
 lea rdi,[publish_manifest]
 mov rsi,[bundle_manifest]
 rep movsb
 mov [publish_manifest+8],r13
 mov [publish_manifest+16],r12
 mov rbx,[parse_blob_count]
 lea r12,[publish_manifest+VR_HEADER]
 xor r14d,r14d
.publish_rewrite:
 cmp r14,rbx
 jae .publish_need
 mov rax,r13
 shl rax,8
 lea rcx,[r14+1]
 or rax,rcx
 mov [r12+VR_BLOB],rax
 add r12,VR_ENTRY
 inc r14
 jmp .publish_rewrite
.publish_need:
 mov r10,rbx
 add r10,3                    ; manifest, destination hash, source mapping
 test r15,r15
 jz .publish_find_free
 inc r10
.publish_find_free:
 mov [publish_node_count],r10
 xor r14d,r14d
 lea r12,[uxv_nodes+UV_NODE]
.publish_free_loop:
 cmp qword [r12+UV_TYPE],0
 jne .publish_free_next
 lea rax,[publish_nodes]
 mov [rax+r14*8],r12
 inc r14
 cmp r14,r10
 je .publish_names
.publish_free_next:
 add r12,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp r12,rax
 jb .publish_free_loop
 jmp .publish_capacity
.publish_names:
 ; Every destination name must be absent before touching reserved records.
 xor r14d,r14d
.publish_blob_name:
 cmp r14,rbx
 jae .publish_commit_names
 mov rdi,r13
 shl rdi,8
 lea rax,[r14+1]
 or rdi,rax
 mov sil,'b'
 call object_absent
 test eax,eax
 jnz .publish_corrupt
 inc r14
 jmp .publish_blob_name
.publish_commit_names:
 mov rdi,r13
 mov sil,'c'
 call object_absent
 test eax,eax
 jnz .publish_corrupt
 mov rdi,r13
 mov sil,'h'
 call object_absent
 test eax,eax
 jnz .publish_corrupt
 mov rdi,r13
 mov sil,'m'
 call object_absent
 test eax,eax
 jnz .publish_corrupt
 test r15,r15
 jz .publish_write
 mov rdi,r13
 mov sil,'s'
 call object_absent
 test eax,eax
 jnz .publish_corrupt
.publish_write:
 xor r14d,r14d
.publish_write_blob:
 cmp r14,rbx
 jae .publish_write_manifest
 lea rax,[publish_nodes]
 mov r12,[rax+r14*8]
 mov rdi,r12
 call clear_record
 mov rdi,r13
 shl rdi,8
 lea rax,[r14+1]
 or rdi,rax
 mov sil,'b'
 call vcs_object_name
 mov rdi,r12
 lea rsi,[vcs_object_path]
 mov ecx,240
 rep movsb
 mov qword [r12+UV_TYPE],1
 lea rax,[bundle_blob_sizes]
 mov rcx,[rax+r14*8]
 mov [r12+UV_SIZE],rcx
 lea rax,[bundle_blob_ptrs]
 mov rsi,[rax+r14*8]
 lea rdi,[r12+UV_DATA]
 rep movsb
 inc r14
 jmp .publish_write_blob
.publish_write_manifest:
 lea rax,[publish_nodes]
 mov r12,[rax+rbx*8]
 mov rdi,r12
 call clear_record
 mov rdi,r13
 mov sil,'c'
 call vcs_object_name
 mov rdi,r12
 lea rsi,[vcs_object_path]
 mov ecx,240
 rep movsb
 mov qword [r12+UV_TYPE],1
 mov rcx,[bundle_manifest_size]
 mov [r12+UV_SIZE],rcx
 lea rdi,[r12+UV_DATA]
 lea rsi,[publish_manifest]
 rep movsb
 ; Recompute the destination digest because IDs and parent were remapped.
 lea rdi,[bundle_hash]
 call sha256_init
 lea rdi,[bundle_hash]
 lea rsi,[hash_domain]
 mov edx,8
 call sha256_update
 lea rdi,[bundle_hash]
 lea rsi,[publish_manifest]
 mov rdx,[bundle_manifest_size]
 call sha256_update
 xor r14d,r14d
.publish_hash_blob:
 cmp r14,rbx
 jae .publish_hash_done
 lea rax,[bundle_blob_ptrs]
 mov rsi,[rax+r14*8]
 lea rax,[bundle_blob_sizes]
 mov rdx,[rax+r14*8]
 lea rdi,[bundle_hash]
 call sha256_update
 inc r14
 jmp .publish_hash_blob
.publish_hash_done:
 lea rdi,[bundle_hash]
 lea rsi,[bundle_hash_out]
 call sha256_final
 lea rax,[publish_nodes]
 mov r12,[rax+rbx*8+8]
 mov rdi,r12
 call clear_record
 mov rdi,r13
 mov sil,'h'
 call vcs_object_name
 mov rdi,r12
 lea rsi,[vcs_object_path]
 mov ecx,240
 rep movsb
 mov qword [r12+UV_TYPE],1
 mov qword [r12+UV_SIZE],32
 lea rdi,[r12+UV_DATA]
 lea rsi,[bundle_hash_out]
 mov ecx,32
 rep movsb
 ; Preserve the source digest so the next imported commit can resolve this
 ; remapped commit as its parent without trusting source sequence numbers.
 lea rax,[publish_nodes]
 mov r12,[rax+rbx*8+16]
 mov rdi,r12
 call clear_record
 mov rdi,r13
 mov sil,'m'
 call vcs_object_name
 mov rdi,r12
 lea rsi,[vcs_object_path]
 mov ecx,240
 rep movsb
 mov qword [r12+UV_TYPE],1
 mov qword [r12+UV_SIZE],48
 mov rax,VB_MAP_MAGIC
 mov [r12+UV_DATA],rax
 mov rax,[rbp+VBH_TIP]
 mov [r12+UV_DATA+8],rax
 mov rsi,[bundle_digest]
 lea rdi,[r12+UV_DATA+16]
 mov ecx,32
 rep movsb
 test r15,r15
 jz .publish_metadata
 lea rax,[publish_nodes]
 mov rcx,[rax+rbx*8+24]
 mov rdi,r13
 lea rsi,[bundle_hash_out]
 mov rdx,r15
 call vcs_signature_prepare
 test eax,eax
 jnz .publish_clear
.publish_metadata:
 mov rax,[vcs_repo_format]
 mov [rax+UV_DATA+16],r13
 call uxv_commit
 test rax,rax
 js .publish_io
 mov rdx,r13
 xor eax,eax
 jmp .publish_done
.publish_clear:
 ; Reserved nodes were free on entry; do not leave staged objects in memory.
 mov [bundle_capacity],rax
 xor r14d,r14d
.publish_clear_loop:
 cmp r14,[publish_node_count]
 jae .publish_clear_done
 lea rax,[publish_nodes]
 mov rdi,[rax+r14*8]
 call clear_record
 inc r14
 jmp .publish_clear_loop
.publish_clear_done:
 mov rax,[bundle_capacity]
 jmp .publish_done
.publish_permission: mov eax,VCS_ERR_PERM
 jmp .publish_done
.publish_missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .publish_done
.publish_capacity: mov eax,VCS_ERR_NO_MEM
 jmp .publish_done
.publish_corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .publish_done
.publish_io: mov eax,VCS_ERR_IO
.publish_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=id, SIL=kind. EAX=0 only when the generated object name is unused.
object_absent:
 call vcs_object_name
 test eax,eax
 jnz .object_bad
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 setnz al
 movzx eax,al
 ret
.object_bad:
 mov eax,1
 ret

clear_record:
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret

; SIL kind, RDI id -> node or zero.
find_object:
 call vcs_object_name
 test eax,eax
 jnz .missing
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .missing
 cmp qword [rax+UV_TYPE],1
 jne .missing
 ret
.missing:
 xor eax,eax
 ret

; EDI kind, RSI id, RDX bytes, RCX size. Preflight guarantees capacity.
append_record:
 mov r8,[bundle_cursor]
 mov [r8+VBR_KIND],rdi
 mov [r8+VBR_ID],rsi
 mov [r8+VBR_SIZE],rcx
 add r8,VB_RECORD
 mov rdi,r8
 mov rsi,rdx
 mov r9,rcx
 rep movsb
 add r8,r9
 mov [bundle_cursor],r8
 ret

; Strict repository-relative path, excluding dot and .vcs components.
valid_relative:
 xor ecx,ecx
 xor edx,edx
.path_component:
 mov r8d,ecx
.path_scan:
 cmp ecx,VR_PATH
 jae .path_bad
 mov al,[rdi+rcx]
 test al,al
 jz .path_component_end
 cmp al,'/'
 je .path_component_end
 cmp al,32
 jb .path_bad
 cmp al,127
 je .path_bad
 inc ecx
 jmp .path_scan
.path_component_end:
 mov edx,ecx
 sub edx,r8d
 jz .path_bad
 cmp edx,1
 jne .path_dotdot
 cmp byte [rdi+r8],'.'
 je .path_bad
.path_dotdot:
 cmp edx,2
 jne .path_metadata
 cmp word [rdi+r8],'..'
 je .path_bad
.path_metadata:
 cmp edx,4
 jne .path_continue
 cmp dword [rdi+r8],0x7363762e
 je .path_bad
.path_continue:
 test al,al
 jz .path_good
 inc ecx
 jmp .path_component
.path_good:
 mov eax,1
 ret
.path_bad:
 xor eax,eax
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
.name_no:
 xor eax,eax
 ret
.name_yes:
 mov eax,1
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
