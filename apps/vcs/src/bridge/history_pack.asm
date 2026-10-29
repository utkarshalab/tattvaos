; Complete bounded first-parent Git SHA-256 PACK construction.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/git_pack.inc"
%include "include/git_tree.inc"
%include "include/git_commit.inc"
%include "lib/storage/uxfs/volume.inc"
bits 64
default rel

extern vcs_load_manifest,vcs_object_name,vcs_object_path
extern uxv_find
extern git_first_parent_plan,git_object_hash
extern git_pack_begin_unique,git_pack_add,git_pack_finish
extern git_tree_plan,git_tree_file_parents,git_tree_emit_plan
extern git_commit_encode

section .bss
hp_ids: resq UV_NODES
hp_count: resq 1
hp_objects: resq 1
hp_manifest: resq 1
hp_node: resq 1
hp_plan: resb GIT_TREE_MAX*GIT_TREE_RECORD
hp_plan_count: resq 1
hp_file_parents: resb VR_FILES
hp_blob_hashes: resb VR_FILES*GIT_HASH_SIZE
hp_tree_hashes: resb GIT_TREE_MAX*GIT_TREE_HASH_SIZE
hp_entries: resb (VR_FILES+GIT_TREE_MAX)*GIT_TREE_ENTRY
hp_emit_request: resb GIT_TREE_EMIT_PLAN_REQUEST
hp_tree_buffer: resb 32768
hp_commit_request: resb git_commit_request_size
hp_commit: resb 512
hp_commit_size: resq 1
hp_commit_hash: resb GIT_HASH_SIZE
hp_commit_hashes: resb UV_NODES*GIT_HASH_SIZE
hp_parent_hash: resb GIT_HASH_SIZE
hp_tip_output: resq 1
hp_pack_mode: resb 1
hp_tip_scratch: resb GIT_HASH_SIZE
hp_cutoff: resq 1
hp_limit: resq 1
hp_parent_valid: resb 1
hp_filter_blobs: resb 1
hp_filter_trees: resb 1
hp_filter_limit: resb 1
hp_blob_limit: resq 1
hp_tree_depth: resq 1
hp_depth: resq 1
hp_shallow_valid: resb 1
hp_shallow_hash: resb GIT_HASH_SIZE
hp_unshallow_valid: resb 1
hp_unshallow_hash: resb GIT_HASH_SIZE

section .rodata
blob_type: db 'blob'

section .text
global git_history_pack,git_history_pack_cut,git_history_oid
global git_history_find_common,git_history_shallow
global git_history_set_unshallow,git_history_unshallow

; RDI=VCS tip, RSI=PACK output, RDX=capacity, RCX=32-byte Git tip OID output.
git_history_pack:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz history_usage
 test rsi,rsi
 jz history_usage
 test rcx,rcx
 jz history_usage
 mov byte [hp_pack_mode],1
 mov byte [hp_filter_blobs],0
 mov byte [hp_filter_trees],0
 mov byte [hp_filter_limit],0
 mov qword [hp_blob_limit],0
 mov qword [hp_tree_depth],0
 mov qword [hp_depth],0
 mov qword [hp_cutoff],-1
 mov byte [hp_unshallow_valid],0
 mov r12,rsi
 mov r13,rdx
 mov [hp_tip_output],rcx
 jmp history_encode

; RDI=tip, RSI=PACK, RDX=capacity, RCX=tip OID, R8=common index/-1,
; R9 flags (bit 6 blob:none, bit 7 tree filter, bit 9 blob:limit).
; A nonnegative index must come from git_history_find_common immediately prior.
git_history_pack_cut:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz history_usage
 test rsi,rsi
 jz history_usage
 test rcx,rcx
 jz history_usage
 cmp r8,-1
 je .cut_ready
 cmp r8,[hp_count]
 jae history_usage
.cut_ready:
 mov byte [hp_pack_mode],1
 xor eax,eax
 test r9,64
 setnz al
 mov [hp_filter_blobs],al
 xor eax,eax
 test r9,128
 setnz al
 mov [hp_filter_trees],al
 xor eax,eax
 test r9,512
 setnz al
 mov [hp_filter_limit],al
 mov rax,r9
 shr rax,32
 and eax,0x1ffff
 mov [hp_blob_limit],rax
 mov rax,r9
 shr rax,24
 and eax,255
 mov [hp_tree_depth],rax
 mov rax,r9
 shr rax,16
 and eax,255
 mov [hp_depth],rax
 mov [hp_cutoff],r8
 mov r12,rsi
 mov r13,rdx
 mov [hp_tip_output],rcx
 jmp history_encode

; RDI=VCS tip, RSI=32-byte Git tip OID output.
; Hashes blobs, trees, and parent-linked commits without constructing a PACK.
git_history_oid:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz history_usage
 test rsi,rsi
 jz history_usage
 mov byte [hp_pack_mode],0
 mov byte [hp_filter_blobs],0
 mov byte [hp_filter_trees],0
 mov byte [hp_filter_limit],0
 mov qword [hp_blob_limit],0
 mov qword [hp_tree_depth],0
 mov qword [hp_depth],0
 mov qword [hp_cutoff],-1
 mov [hp_tip_output],rsi
 xor r12d,r12d
 xor r13d,r13d

history_encode:
 lea rsi,[hp_ids]
 mov edx,UV_NODES
 call git_first_parent_plan
 test eax,eax
 jnz history_done
 mov [hp_count],rdx
 mov byte [hp_parent_valid],0
 mov byte [hp_shallow_valid],0
 mov rax,[hp_cutoff]
 cmp rax,-1
 je .full_history
 cmp rax,rdx
 jae history_usage
 mov [hp_limit],rax
 imul rax,GIT_HASH_SIZE
 lea rsi,[hp_commit_hashes+rax]
 lea rdi,[hp_parent_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 mov byte [hp_parent_valid],1
 jmp .history_limit_ready
.full_history:
 mov [hp_limit],rdx
.history_limit_ready:
 mov rax,[hp_depth]
 test rax,rax
 jz .depth_ready
 cmp [hp_limit],rax
 jbe .depth_ready
 mov [hp_limit],rax
 imul rax,GIT_HASH_SIZE
 lea rsi,[hp_commit_hashes+rax]
 lea rdi,[hp_parent_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 mov byte [hp_parent_valid],1
 mov rax,[hp_limit]
 dec rax
 imul rax,GIT_HASH_SIZE
 lea rsi,[hp_commit_hashes+rax]
 lea rdi,[hp_shallow_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 mov byte [hp_shallow_valid],1
.depth_ready:
 mov qword [hp_objects],0
 xor ebx,ebx
.preflight:
 cmp byte [hp_pack_mode],0
 je .begin_history
 cmp rbx,[hp_limit]
 jae .begin_pack
 lea rax,[hp_ids]
 mov rdi,[rax+rbx*8]
 call vcs_load_manifest
 test rax,rax
 jz history_corrupt
 mov rbp,rax
 mov rdi,rbp
 lea rsi,[hp_plan]
 mov edx,GIT_TREE_MAX
 call git_tree_plan
 test eax,eax
 jnz history_done
 mov rax,[rbp+24]
 add rax,rdx
 inc rax
 add [hp_objects],rax
 jc history_space
 cmp qword [hp_objects],0xffffffff
 ja history_space
 inc rbx
 jmp .preflight
.begin_pack:
 mov rdi,r12
 mov rsi,r13
 mov rdx,[hp_objects]
 call git_pack_begin_unique
 test eax,eax
 jnz history_done
.begin_history:
 cmp byte [hp_parent_valid],0
 jne .parent_ready
 lea rdi,[hp_parent_hash]
 xor eax,eax
 mov ecx,GIT_HASH_SIZE/8
 rep stosq
.parent_ready:
 mov r14,[hp_limit]
.snapshot:
 test r14,r14
 jz .finish_pack
 dec r14
 lea rax,[hp_ids]
 mov rdi,[rax+r14*8]
 call vcs_load_manifest
 test rax,rax
 jz history_corrupt
 mov rbp,rax
 mov [hp_manifest],rax
 mov rdi,rbp
 lea rsi,[hp_plan]
 mov edx,GIT_TREE_MAX
 call git_tree_plan
 test eax,eax
 jnz history_done
 mov [hp_plan_count],rdx
 xor ebx,ebx
.hash_blob:
 cmp rbx,[rbp+24]
 jae .map_files
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz history_corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz history_corrupt
 cmp qword [rax+UV_TYPE],1
 jne history_corrupt
 mov [hp_node],rax
 mov rdx,rbx
 shl rdx,8
 add rdx,rbp
 add rdx,VR_HEADER
 mov rcx,[rdx+VR_SIZE]
 cmp [rax+UV_SIZE],rcx
 jne history_corrupt
 mov rax,rbx
 imul rax,GIT_HASH_SIZE
 lea r8,[hp_blob_hashes]
 add r8,rax
 lea rdi,[blob_type]
 mov esi,4
 mov rax,[hp_node]
 lea rdx,[rax+UV_DATA]
 call git_object_hash
 test eax,eax
 jnz history_done
 inc rbx
 jmp .hash_blob
.map_files:
 mov rdi,rbp
 lea rsi,[hp_plan]
 mov rdx,[hp_plan_count]
 lea rcx,[hp_file_parents]
 call git_tree_file_parents
 test eax,eax
 jnz history_done
 xor ebx,ebx
.emit_blob:
 cmp rbx,[rbp+24]
 jae .emit_trees
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov r15,rax
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz history_corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz history_corrupt
 cmp byte [hp_pack_mode],0
 je .next_blob
 cmp byte [hp_filter_blobs],0
 jne .next_blob
 cmp byte [hp_filter_trees],0
 je .blob_limit_check
 movzx edx,byte [hp_file_parents+rbx]
 shl rdx,8
 lea rdx,[hp_plan+rdx]
 mov rdx,[rdx+GT_DEPTH]
 inc rdx
 cmp rdx,[hp_tree_depth]
 jae .next_blob
.blob_limit_check:
 cmp byte [hp_filter_limit],0
 je .emit_blob_object
 mov rdx,[hp_blob_limit]
 cmp [r15+VR_SIZE],rdx
 jae .next_blob
.emit_blob_object:
 mov edi,GIT_PACK_BLOB
 lea rsi,[rax+UV_DATA]
 mov rdx,[r15+VR_SIZE]
 call git_pack_add
 test eax,eax
 jnz history_done
.next_blob:
 inc rbx
 jmp .emit_blob
.emit_trees:
 lea rdi,[hp_emit_request]
 xor eax,eax
 mov ecx,GIT_TREE_EMIT_PLAN_REQUEST/8
 rep stosq
 mov [hp_emit_request+GTEP_MANIFEST],rbp
 lea rax,[hp_plan]
 mov [hp_emit_request+GTEP_PLAN],rax
 mov rax,[hp_plan_count]
 mov [hp_emit_request+GTEP_PLAN_COUNT],rax
 lea rax,[hp_file_parents]
 mov [hp_emit_request+GTEP_FILE_PARENTS],rax
 lea rax,[hp_blob_hashes]
 mov [hp_emit_request+GTEP_BLOB_HASHES],rax
 lea rax,[hp_tree_hashes]
 mov [hp_emit_request+GTEP_TREE_HASHES],rax
 lea rax,[hp_entries]
 mov [hp_emit_request+GTEP_ENTRIES],rax
 mov qword [hp_emit_request+GTEP_ENTRY_CAPACITY],VR_FILES+GIT_TREE_MAX
 lea rax,[hp_tree_buffer]
 mov [hp_emit_request+GTEP_BUFFER],rax
 mov qword [hp_emit_request+GTEP_BUFFER_CAPACITY],32768
 xor eax,eax
 cmp byte [hp_pack_mode],0
 setz al
 mov [hp_emit_request+GTEP_HASH_ONLY],rax
 cmp byte [hp_filter_trees],0
 je .tree_mode_ready
 mov rax,[hp_tree_depth]
 inc rax
 mov [hp_emit_request+GTEP_TREE_LIMIT],rax
.tree_mode_ready:
 lea rdi,[hp_emit_request]
 call git_tree_emit_plan
 test eax,eax
 jnz history_done
 lea rdi,[hp_commit_request]
 xor eax,eax
 mov ecx,git_commit_request_size/8
 rep stosq
 lea rax,[hp_tree_hashes]
 mov [hp_commit_request+git_commit_request.tree],rax
 cmp byte [hp_parent_valid],0
 je .root_commit
 lea rax,[hp_parent_hash]
 mov [hp_commit_request+git_commit_request.parent],rax
.root_commit:
 lea rax,[rbp+VR_MESSAGE]
 mov [hp_commit_request+git_commit_request.message],rax
 mov rax,[rbp+32]
 btr rax,63
 mov [hp_commit_request+git_commit_request.message_len],rax
 lea rax,[hp_commit]
 mov [hp_commit_request+git_commit_request.output],rax
 mov qword [hp_commit_request+git_commit_request.capacity],512
 lea rax,[hp_commit_hash]
 mov [hp_commit_request+git_commit_request.hash],rax
 lea rdi,[hp_commit_request]
 call git_commit_encode
 test eax,eax
 jnz history_done
 mov [hp_commit_size],rdx
 cmp byte [hp_pack_mode],0
 je .commit_hashed
 mov edi,GIT_PACK_COMMIT
 lea rsi,[hp_commit]
 mov rdx,[hp_commit_size]
 call git_pack_add
 test eax,eax
 jnz history_done
.commit_hashed:
 mov rax,r14
 imul rax,GIT_HASH_SIZE
 lea rdi,[hp_commit_hashes+rax]
 lea rsi,[hp_commit_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 lea rsi,[hp_commit_hash]
 lea rdi,[hp_parent_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 mov byte [hp_parent_valid],1
 test r14,r14
 jnz .snapshot
.finish_pack:
 lea rsi,[hp_commit_hashes]
 mov rdi,[hp_tip_output]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 cmp byte [hp_pack_mode],0
 je .finish_oid
 cmp byte [hp_shallow_valid],0
 je .finish_pack_write
 cmp byte [hp_unshallow_valid],0
 je .finish_pack_write
 lea rdi,[hp_shallow_hash]
 lea rsi,[hp_unshallow_hash]
 mov ecx,GIT_HASH_SIZE
 repe cmpsb
 jne .finish_pack_write
 mov byte [hp_shallow_valid],0
 mov byte [hp_unshallow_valid],0
.finish_pack_write:
 call git_pack_finish
 jmp history_done
.finish_oid:
 mov edx,GIT_HASH_SIZE
 xor eax,eax
 jmp history_done
history_usage:
 mov eax,VCS_ERR_USAGE
 jmp history_done
history_space:
 mov eax,VCS_ERR_NO_MEM
 jmp history_done
history_corrupt:
 mov eax,VCS_ERR_CORRUPT
history_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=VCS tip, RSI=packed 32-byte have OIDs, RDX=count (0..64).
; Returns RAX=status and RDX=newest matching first-parent index, or -1.
git_history_find_common:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .common_usage
 test rdx,rdx
 jz .common_none
 test rsi,rsi
 jz .common_usage
 cmp rdx,64
 ja .common_usage
 mov r12,rsi
 mov r13,rdx
 lea rsi,[hp_tip_scratch]
 call git_history_oid
 test eax,eax
 jnz .common_done
 xor ebx,ebx
.common_history:
 cmp rbx,[hp_count]
 jae .common_none
 xor r14d,r14d
.common_have:
 cmp r14,r13
 jae .common_next_history
 mov rax,rbx
 imul rax,GIT_HASH_SIZE
 lea rdi,[hp_commit_hashes+rax]
 mov rax,r14
 imul rax,GIT_HASH_SIZE
 lea rsi,[r12+rax]
 mov ecx,GIT_HASH_SIZE
 repe cmpsb
 je .common_found
 inc r14
 jmp .common_have
.common_next_history:
 inc rbx
 jmp .common_history
.common_found:
 mov rdx,rbx
 xor eax,eax
 jmp .common_done
.common_none:
 mov rdx,-1
 xor eax,eax
 jmp .common_done
.common_usage:
 mov eax,VCS_ERR_USAGE
.common_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Return the shallow boundary OID from the most recent pack, or null.
git_history_shallow:
 xor eax,eax
 cmp byte [hp_shallow_valid],0
 je .shallow_done
 lea rax,[hp_shallow_hash]
.shallow_done:
 ret

; Set or clear the client boundary to report as unshallow for the next
; bridge-generated pack. RDI=32-byte OID or null.
git_history_set_unshallow:
 mov byte [hp_unshallow_valid],0
 test rdi,rdi
 jz .set_unshallow_done
 lea rsi,[rdi]
 lea rdi,[hp_unshallow_hash]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 mov byte [hp_unshallow_valid],1
.set_unshallow_done:
 ret

; Return the client boundary associated with the most recent relative pack.
git_history_unshallow:
 xor eax,eax
 cmp byte [hp_unshallow_valid],0
 je .unshallow_done
 lea rax,[hp_unshallow_hash]
.unshallow_done:
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
