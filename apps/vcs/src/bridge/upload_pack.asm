; Bounded Git SHA-256 snapshot object graph and PACK construction.
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
extern git_object_hash,git_pack_begin,git_pack_add,git_pack_finish
extern git_tree_plan,git_tree_file_parents,git_tree_emit_plan
extern git_commit_encode

section .bss
up_manifest: resq 1
up_count: resq 1
up_indices: resb VR_FILES
up_blob_hashes: resb VR_FILES*GIT_HASH_SIZE
up_tree: resb 8192
up_tree_size: resq 1
up_tree_hash: resb GIT_HASH_SIZE
up_commit: resb 512
up_commit_size: resq 1
up_commit_hash: resb GIT_HASH_SIZE
up_commit_request: resb git_commit_request_size
up_decimal: resb 20
up_output: resq 1
up_capacity: resq 1
up_oid_output: resq 1
up_entry: resq 1
up_sort_key: resb 1
up_tree_plan: resb GIT_TREE_MAX*GIT_TREE_RECORD
up_plan_count: resq 1
up_file_parents: resb VR_FILES
up_tree_hashes: resb GIT_TREE_MAX*GIT_TREE_HASH_SIZE
up_tree_entries: resb (VR_FILES+GIT_TREE_MAX)*GIT_TREE_ENTRY
up_emit_request: resb GIT_TREE_EMIT_PLAN_REQUEST
up_recursive_tree: resb 32768
up_recursive_started: resq 1

section .rodata
blob_type: db 'blob'
tree_type: db 'tree'
mode: db '100644 '
mode_len equ $-mode

section .text
global git_snapshot_pack
; RDI=VCS commit ID, RSI=pack output, RDX=capacity, RCX=32-byte Git commit OID.
git_snapshot_pack:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .usage
 test rsi,rsi
 jz .usage
 test rcx,rcx
 jz .usage
 mov [up_output],rsi
 mov [up_capacity],rdx
 mov [up_oid_output],rcx
 mov qword [up_recursive_started],0
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov [up_manifest],rax
 mov rbp,rax
 mov r15,[rbp+24]
 mov [up_count],r15
 ; The shared planner is the sole path-validation and hierarchy authority.
 mov rdi,rbp
 lea rsi,[up_tree_plan]
 mov edx,GIT_TREE_MAX
 call git_tree_plan
 test eax,eax
 jnz .done
 mov [up_plan_count],rdx
 xor ebx,ebx
.initialize_indices:
 cmp rbx,r15
 jae .hash_blobs
 mov byte [up_indices+rbx],bl
 inc rbx
 jmp .initialize_indices
.hash_blobs:
 xor ebx,ebx
.blob:
 cmp rbx,r15
 jae .recursive_pack
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov [up_entry],rax
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov rcx,rbx
 shl rcx,8
 add rcx,rbp
 add rcx,VR_HEADER
 mov rdx,[rcx+VR_SIZE]
 cmp [rax+UV_SIZE],rdx
 jne .corrupt
 mov rax,rbx
 imul rax,GIT_HASH_SIZE
 lea r8,[up_blob_hashes+rax]
 lea rdi,[blob_type]
 mov esi,4
 lea rcx,[rax+UV_DATA]
 xchg rdx,rcx
 call git_object_hash
 test eax,eax
 jnz .done
 inc rbx
 jmp .blob
.recursive_pack:
 mov rdi,rbp
 lea rsi,[up_tree_plan]
 mov rdx,[up_plan_count]
 lea rcx,[up_file_parents]
 call git_tree_file_parents
 test eax,eax
 jnz .done
 mov rdi,[up_output]
 mov rsi,[up_capacity]
 mov rdx,r15
 add rdx,[up_plan_count]
 inc rdx
 call git_pack_begin
 test eax,eax
 jnz .done
 mov qword [up_recursive_started],1
 xor ebx,ebx
.recursive_blob_pack:
 cmp rbx,r15
 jae .recursive_trees
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov [up_entry],rax
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov rcx,[up_entry]
 mov edi,GIT_PACK_BLOB
 lea rsi,[rax+UV_DATA]
 mov rdx,[rcx+VR_SIZE]
 call git_pack_add
 test eax,eax
 jnz .done
 inc rbx
 jmp .recursive_blob_pack
.recursive_trees:
 lea rdi,[up_emit_request]
 xor eax,eax
 mov ecx,GIT_TREE_EMIT_PLAN_REQUEST/8
 rep stosq
 mov [up_emit_request+GTEP_MANIFEST],rbp
 lea rax,[up_tree_plan]
 mov [up_emit_request+GTEP_PLAN],rax
 mov rax,[up_plan_count]
 mov [up_emit_request+GTEP_PLAN_COUNT],rax
 lea rax,[up_file_parents]
 mov [up_emit_request+GTEP_FILE_PARENTS],rax
 lea rax,[up_blob_hashes]
 mov [up_emit_request+GTEP_BLOB_HASHES],rax
 lea rax,[up_tree_hashes]
 mov [up_emit_request+GTEP_TREE_HASHES],rax
 lea rax,[up_tree_entries]
 mov [up_emit_request+GTEP_ENTRIES],rax
 mov qword [up_emit_request+GTEP_ENTRY_CAPACITY],VR_FILES+GIT_TREE_MAX
 lea rax,[up_recursive_tree]
 mov [up_emit_request+GTEP_BUFFER],rax
 mov qword [up_emit_request+GTEP_BUFFER_CAPACITY],32768
 lea rdi,[up_emit_request]
 call git_tree_emit_plan
 test eax,eax
 jnz .done
 lea rsi,[up_tree_hashes]
 lea rdi,[up_tree_hash]
 mov ecx,GIT_TREE_HASH_SIZE
 rep movsb
 jmp .recursive_commit
.sort:
 ; Stable insertion sort by raw path bytes.
 mov ebx,1
.sort_outer:
 cmp rbx,r15
 jae .build_tree
 mov al,[up_indices+rbx]
 mov [up_sort_key],al
 mov r13,rbx
.sort_inner:
 test r13,r13
 jz .sort_place
 movzx edi,byte [up_indices+r13-1]
 movzx esi,byte [up_sort_key]
 call compare_paths
 cmp eax,0
 jle .sort_place
 mov al,[up_indices+r13-1]
 mov [up_indices+r13],al
 dec r13
 jmp .sort_inner
.sort_place:
 mov al,[up_sort_key]
 mov [up_indices+r13],al
 inc rbx
 jmp .sort_outer
.build_tree:
 lea rdi,[up_tree]
 xor ebx,ebx
.tree_entry:
 cmp rbx,r15
 jae .tree_ready
 lea rsi,[mode]
 mov ecx,mode_len
 rep movsb
 movzx eax,byte [up_indices+rbx]
 mov rdx,rax
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov rsi,rax
.tree_path:
 lodsb
 stosb
 test al,al
 jnz .tree_path
 imul rdx,GIT_HASH_SIZE
 lea rsi,[up_blob_hashes+rdx]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 inc rbx
 jmp .tree_entry
.tree_ready:
 lea rax,[up_tree]
 sub rdi,rax
 mov [up_tree_size],rdi
 lea rdi,[tree_type]
 mov esi,4
 lea rdx,[up_tree]
 mov rcx,[up_tree_size]
 lea r8,[up_tree_hash]
 call git_object_hash
 test eax,eax
 jnz .done
.recursive_commit:
 lea rdi,[up_commit_request]
 xor eax,eax
 mov ecx,git_commit_request_size/8
 rep stosq
 lea rax,[up_tree_hash]
 mov [up_commit_request+git_commit_request.tree],rax
 lea rax,[rbp+VR_MESSAGE]
 mov [up_commit_request+git_commit_request.message],rax
 mov rax,[rbp+32]
 btr rax,63
 mov [up_commit_request+git_commit_request.message_len],rax
 lea rax,[up_commit]
 mov [up_commit_request+git_commit_request.output],rax
 mov qword [up_commit_request+git_commit_request.capacity],512
 lea rax,[up_commit_hash]
 mov [up_commit_request+git_commit_request.hash],rax
 lea rdi,[up_commit_request]
 call git_commit_encode
 test eax,eax
 jnz .done
 mov [up_commit_size],rdx
 lea rsi,[up_commit_hash]
 mov rdi,[up_oid_output]
 mov ecx,GIT_HASH_SIZE
 rep movsb
 cmp qword [up_recursive_started],0
 jne .recursive_commit_pack
 ; Emit every object exactly once.
 mov rdi,[up_output]
 mov rsi,[up_capacity]
 mov rdx,r15
 add edx,2
 call git_pack_begin
 test eax,eax
 jnz .done
 xor ebx,ebx
.pack_blob:
 cmp rbx,r15
 jae .pack_tree
 mov rax,rbx
 shl rax,8
 add rax,rbp
 add rax,VR_HEADER
 mov [up_entry],rax
 mov rdi,[rax+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov edi,GIT_PACK_BLOB
 lea rsi,[rax+UV_DATA]
 mov rcx,[up_entry]
 mov rdx,[rcx+VR_SIZE]
 call git_pack_add
 test eax,eax
 jnz .done
 inc rbx
 jmp .pack_blob
.pack_tree:
 mov edi,GIT_PACK_TREE
 lea rsi,[up_tree]
 mov rdx,[up_tree_size]
 call git_pack_add
 test eax,eax
 jnz .done
 mov edi,GIT_PACK_COMMIT
 lea rsi,[up_commit]
 mov rdx,[up_commit_size]
 call git_pack_add
 test eax,eax
 jnz .done
 call git_pack_finish
 jmp .done
.recursive_commit_pack:
 mov edi,GIT_PACK_COMMIT
 lea rsi,[up_commit]
 mov rdx,[up_commit_size]
 call git_pack_add
 test eax,eax
 jnz .done
 call git_pack_finish
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.unsupported: mov eax,VCS_ERR_UNSUPPORTED
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; EDI/ESI are manifest entry indices. EAX signed lexical comparison.
compare_paths:
 mov rax,rdi
 shl rax,8
 add rax,[up_manifest]
 add rax,VR_HEADER
 mov rdx,rsi
 shl rdx,8
 add rdx,[up_manifest]
 add rdx,VR_HEADER
 xor ecx,ecx
.compare:
 movzx edi,byte [rax+rcx]
 movzx esi,byte [rdx+rcx]
 cmp edi,esi
 jne .different
 test edi,edi
 jz .equal
 inc ecx
 cmp ecx,VR_PATH
 jb .compare
.equal: xor eax,eax
 ret
.different:
 mov eax,edi
 sub eax,esi
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
