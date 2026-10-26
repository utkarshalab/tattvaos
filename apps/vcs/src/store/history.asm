; Serialized UXFS history commands; all mutation follows complete preflight.
; vcs_history(rdi=0 status / 1 commit / 2 log / 3 oneline log / 4 show /
;             5 restore tracked path from HEAD, 6 cryptographic integrity check,
;             rsi=message, zero for HEAD, or numeric commit ID,
;             rdx=write(bytes,length) callback) -> VCS status.
; Caller owns console/volume serialization. No syscalls, heap, or C runtime.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
%include "lib/crypto/uhash/sha256/sha256.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_cwd,uxv_find,uxv_commit
extern sha256_init,sha256_update,sha256_final
extern vcs_signature_policy,vcs_signature_prepare
section .bss
alignb 8
mode: resq 1
writer: resq 1
message: resb 216
global vcs_repo_root,vcs_object_path,vcs_repo_root_size,vcs_repo_format
global vcs_repo_head,vcs_repo_last
vcs_repo_root:
root: resb 240
vcs_object_path:
object_path: resb 240
vcs_repo_root_size:
root_size: resq 1
vcs_repo_format:
format_node: resq 1
ignore_node: resq 1
global vcs_active_ref_node
vcs_active_ref_node:
active_ref_node: resq 1
vcs_repo_head:
head: resq 1
vcs_repo_last:
last_id: resq 1
old_manifest: resq 1
work_count: resq 1
changes: resq 1
blob_count: resq 1
new_id: resq 1
requested_id: resq 1
second_parent: resq 1
replay_request: resq 1
free_count: resq 1
free_nodes: resq 18
signed_seed: resq 1
; Working entry: relative name[240], node pointer, matched previous entry.
work: resb VR_FILES*VR_ENTRY
current: resb VR_FILES*VR_ENTRY
current_count: resq 1
index_node: resq 1
merge_node: resq 1
conflict_node: resq 1
snapshot: resb 4096
escaped: resb 2048
number: resb 16
ancestor_stack: resq UV_NODES
ancestor_seen: resq UV_NODES
ancestor_other: resq UV_NODES
alignb 16
hash_ctx: resb sha256_ctx_t_size
hash_digest: resb SHA256_DIGEST_SIZE
section .rodata
meta_suffix: db '/.vcs',0
format_suffix: db '/format',0
ignore_suffix: db '/.vcsignore',0
active_suffix: db '/.vcs/active',0
branch_suffix: db '/.vcs/rh.',0
index_suffix: db '/.vcs/index',0
merge_suffix: db '/.vcs/merge',0
conflict_suffix: db '/.vcs/conflicts',0
rebase_suffix: db '/.vcs/rebase',0
pick_suffix: db '/.vcs/pick',0
digits: db '0123456789abcdef'
newline: db 10
added: db 'A '
modified: db 'M '
deleted: db 'D '
clean: db 'Working tree clean',10
clean_len equ $-clean
unborn: db 'No commits yet',10
unborn_len equ $-unborn
nothing: db 'Nothing to commit',10
nothing_len equ $-nothing
commit_label: db 'commit '
commit_label_len equ $-commit_label
files_label: db 'files:',10
files_label_len equ $-files_label
file_label: db '  '
restored_label: db 'Restored '
restored_label_len equ $-restored_label
saved: db 'Committed '
saved_len equ $-saved
space: db ' '
hash_domain: db 'UVCSCHK1'
integrity_ok: db 'Integrity OK',10
integrity_ok_len equ $-integrity_ok
section .text
global vcs_history,vcs_history_signed,vcs_history_merge,vcs_history_merge_signed
global vcs_history_replay,vcs_history_replay_signed,vcs_is_ancestor,vcs_merge_base
vcs_history:
 mov qword [signed_seed],0
 mov qword [second_parent],0
 mov qword [replay_request],0
.entry:
 cmp qword [second_parent],0
 jne .entry_ready
 mov qword [merge_node],0
 mov qword [conflict_node],0
.entry_ready:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,6
 ja .usage
 test rdx,rdx
 jz .usage
 mov [mode],rdi
 mov [writer],rdx
 mov [requested_id],rsi
 cmp qword [uxv_ready],1
 jne .io
 cmp rdi,1
 jne .discover
 test rsi,rsi
 jz .usage
 lea rdi,[message]
 xor ecx,ecx
.message:
 mov al,[rsi+rcx]
 mov [rdi+rcx],al
 test al,al
 jz .message_done
 inc ecx
 cmp ecx,216
 jb .message
 jmp .usage
.message_done:
 test ecx,ecx
 jz .usage
.discover:
 call discover
 test eax,eax
 jnz .done
 cmp qword [mode],6
 je .check
 cmp qword [mode],1
 jne .operation
 cmp qword [second_parent],0
 jne .merge_operation
 cmp qword [replay_request],0
 jne .operation_replay
 lea rsi,[merge_suffix]
 mov edx,12
 call metadata_node
 test rax,rax
 jnz .conflict
 lea rsi,[rebase_suffix]
 mov edx,13
 call metadata_node
 test rax,rax
 jnz .conflict
 lea rsi,[pick_suffix]
 mov edx,11
 call metadata_node
 test rax,rax
 jnz .conflict
 lea rsi,[conflict_suffix]
 mov edx,16
 call metadata_node
 test rax,rax
 jnz .conflict
 jmp .operation
.merge_operation:
 cmp qword [second_parent],0
 je .operation_replay
 call prepare_merge_state
 test eax,eax
 jnz .done
.operation_replay:
 cmp qword [replay_request],0
 je .operation
 call prepare_replay_state
 test eax,eax
 jnz .done
.operation:
 cmp qword [mode],5
 je .restore
 cmp qword [mode],4
 je .show
 cmp qword [mode],2
 jae .log
 mov qword [old_manifest],0
 mov r12,[head]
 xor r15d,r15d
.validate_history:
 test r12,r12
 jz .collect
 inc r15
 cmp r15,UV_NODES
 ja .corrupt
 mov rdi,r12
 call load_manifest
 test rax,rax
 jz .corrupt
 cmp r12,[head]
 jne .older
 mov [old_manifest],rax
.older:
 mov r12,[rax+16]
 jmp .validate_history
.collect:
 call collect
 test eax,eax
 jnz .done
 cmp qword [mode],1
 jne .match_ready
 call apply_index
 test eax,eax
 jnz .done
.match_ready:
 ; Match every working file and compare exact bytes with its previous blob.
 mov qword [changes],0
 mov qword [blob_count],0
 xor r12d,r12d
.match:
 cmp r12,[work_count]
 jae .deletions
 mov rbx,r12
 shl rbx,8
 lea rax,[work]
 add rbx,rax
 mov qword [rbx+248],0
 mov r13,[old_manifest]
 test r13,r13
 jz .new_file
 mov r14,[r13+24]
 add r13,VR_HEADER
.find_old:
 test r14,r14
 jz .new_file
 mov rdi,rbx
 mov rsi,r13
 call same_name
 test eax,eax
 jnz .matched
 add r13,VR_ENTRY
 dec r14
 jmp .find_old
.matched:
 mov [rbx+248],r13
 mov rdi,[r13+VR_BLOB]
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov rdx,[rbx+240]
 mov rcx,[rdx+UV_SIZE]
 cmp rcx,[rax+UV_SIZE]
 jne .changed_file
 lea rsi,[rax+UV_DATA]
 lea rdi,[rdx+UV_DATA]
 repe cmpsb
 je .next_work
.changed_file:
 inc qword [changes]
 inc qword [blob_count]
 jmp .next_work
.new_file:
 inc qword [changes]
 inc qword [blob_count]
.next_work:
 inc r12
 jmp .match
.deletions:
 mov r13,[old_manifest]
 test r13,r13
 jz .operate
 mov r14,[r13+24]
 add r13,VR_HEADER
.deleted_loop:
 test r14,r14
 jz .operate
 mov rdi,r13
 call find_work
 test rax,rax
 jnz .deleted_next
 inc qword [changes]
.deleted_next:
 add r13,VR_ENTRY
 dec r14
 jmp .deleted_loop
.operate:
 cmp qword [mode],1
 je .commit
 ; Complete validation above precedes any status output.
 cmp qword [head],0
 jne .status_rows
 lea rdi,[unborn]
 mov esi,unborn_len
 call emit
.status_rows:
 xor r12d,r12d
.status_loop:
 cmp r12,[work_count]
 jae .status_deleted
 mov rbx,r12
 shl rbx,8
 lea rax,[work]
 add rbx,rax
 mov r13,[rbx+248]
 test r13,r13
 jz .status_added
 mov rdi,[r13+VR_BLOB]
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 mov rdx,[rbx+240]
 mov rcx,[rdx+UV_SIZE]
 cmp rcx,[rax+UV_SIZE]
 jne .status_modified
 lea rsi,[rax+UV_DATA]
 lea rdi,[rdx+UV_DATA]
 repe cmpsb
 je .status_next
.status_modified:
 lea rdi,[modified]
 jmp .status_prefix
.status_added:
 lea rdi,[added]
.status_prefix:
 mov esi,2
 call emit
 mov rdi,rbx
 call print_string
 call print_newline
.status_next:
 inc r12
 jmp .status_loop
.status_deleted:
 mov r13,[old_manifest]
 test r13,r13
 jz .status_end
 mov r14,[r13+24]
 add r13,VR_HEADER
.status_delete_loop:
 test r14,r14
 jz .status_end
 mov rdi,r13
 call find_work
 test rax,rax
 jnz .status_delete_next
 lea rdi,[deleted]
 mov esi,2
 call emit
 mov rdi,r13
 call print_string
 call print_newline
.status_delete_next:
 add r13,VR_ENTRY
 dec r14
 jmp .status_delete_loop
.status_end:
 cmp qword [changes],0
 jne .ok
 cmp qword [head],0
 je .ok
 lea rdi,[clean]
 mov esi,clean_len
 call emit
 jmp .ok
.commit:
 cmp qword [changes],0
 jne .build
 cmp qword [second_parent],0
 jne .build
 cmp qword [replay_request],0
 jne .build
 cmp qword [head],0
 je .build                       ; an initial empty snapshot is meaningful
 lea rdi,[nothing]
 mov esi,nothing_len
 call emit
 jmp .ok
.build:
 call vcs_signature_policy
 test eax,eax
 jnz .done
 test rdx,rdx
 jz .policy_ready
 cmp qword [signed_seed],0
 je .permission
.policy_ready:
 mov rax,[last_id]
 mov rdx,VR_MAX_ID
 cmp rax,rdx
 jae .capacity
 inc rax
 mov [new_id],rax
 lea rdi,[snapshot]
 xor eax,eax
 mov ecx,512
 rep stosq
 mov rax,VR_COM_MAGIC
 mov [snapshot],rax
 mov rax,[new_id]
 mov [snapshot+8],rax
 mov rax,[head]
 mov [snapshot+16],rax
 mov rax,[work_count]
 mov [snapshot+24],rax
 lea rsi,[message]
 lea rdi,[snapshot+VR_MESSAGE]
 xor ecx,ecx
.copy_message:
 lodsb
 stosb
 test al,al
 jz .message_copied
 inc ecx
 jmp .copy_message
.message_copied:
 mov rax,[second_parent]
 test rax,rax
 jz .plain_message
 cmp rcx,VR_MERGE_MESSAGE_MAX
 ja .usage
 mov r14,rcx
 cmp rax,[new_id]
 jae .corrupt
 mov rdi,rax
 call load_manifest
 test rax,rax
 jz .corrupt
 mov rcx,r14
 mov rax,[second_parent]
 mov [snapshot+VR_SECOND_PARENT],rax
 mov rax,VR_MERGE_FLAG
 or rcx,rax
.plain_message:
 mov [snapshot+32],rcx
 ; Find all free nodes without changing the live tree.
 mov qword [free_count],0
 lea rbx,[uxv_nodes+UV_NODE]
.free_loop:
 cmp qword [rbx+UV_TYPE],0
 jne .free_next
 mov rax,[free_count]
 lea rdx,[free_nodes]
 mov [rdx+rax*8],rbx
 inc qword [free_count]
 mov rdx,[blob_count]
 add rdx,2                       ; manifest plus SHA-256 integrity record
 cmp qword [signed_seed],0
 je .free_needed
 inc rdx                         ; atomic Ed25519 signature record
.free_needed:
 cmp [free_count],rdx
 jae .preflight
.free_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .free_loop
 jmp .capacity
.preflight:
 mov rdi,[new_id]
 mov sil,'c'
 call object_name
 test eax,eax
 jnz .usage
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jnz .corrupt
 mov rdi,[new_id]
 mov sil,'h'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jnz .corrupt
 cmp qword [signed_seed],0
 je .preflight_objects_ready
 mov rdi,[new_id]
 mov sil,'s'
 call object_name
 test eax,eax
 jnz .usage
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jnz .corrupt
.preflight_objects_ready:
 xor r12d,r12d
.manifest_loop:
 cmp r12,[work_count]
 jae .publish
 mov rbx,r12
 shl rbx,8
 lea rax,[work]
 add rbx,rax
 mov r13,r12
 shl r13,8
 lea rax,[snapshot+VR_HEADER]
 add r13,rax
 mov rdi,r13
 mov rsi,rbx
 mov ecx,240
 rep movsb
 mov rdx,[rbx+240]
 mov rcx,[rdx+UV_SIZE]
 mov [r13+VR_SIZE],rcx
 mov r14,[rbx+248]
 test r14,r14
 jz .fresh_blob
 mov rdi,[r14+VR_BLOB]
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 mov rdx,[rbx+240]
 mov rcx,[rdx+UV_SIZE]
 cmp rcx,[rax+UV_SIZE]
 jne .fresh_blob
 lea rsi,[rax+UV_DATA]
 lea rdi,[rdx+UV_DATA]
 repe cmpsb
 jne .fresh_blob
 mov rax,[r14+VR_BLOB]
 mov [r13+VR_BLOB],rax
 jmp .manifest_next
.fresh_blob:
 mov rdi,[new_id]
 shl rdi,8
 lea rax,[r12+1]
 or rdi,rax
 mov [r13+VR_BLOB],rdi
 mov sil,'b'
 call object_name
 test eax,eax
 jnz .usage
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jnz .corrupt
.manifest_next:
 inc r12
 jmp .manifest_loop
.publish:
 ; No remaining path/capacity/content validation can fail from this point.
 xor r12d,r12d
 xor r15d,r15d
.publish_loop:
 cmp r12,[work_count]
 jae .publish_manifest
 mov r13,r12
 shl r13,8
 lea rax,[snapshot+VR_HEADER]
 add r13,rax
 mov rdi,[r13+VR_BLOB]
 mov rax,rdi
 shr rax,8
 cmp rax,[new_id]
 jne .publish_next
 mov sil,'b'
 call object_name
 lea rax,[free_nodes]
 mov rbx,[rax+r15*8]
 inc r15
 call clear_node
 mov rdi,rbx
 lea rsi,[object_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,[r13+VR_SIZE]
 mov [rbx+UV_SIZE],rcx
 mov rax,r12
 shl rax,8
 lea rdx,[work]
 mov rsi,[rdx+rax+240]
 add rsi,UV_DATA
 lea rdi,[rbx+UV_DATA]
 rep movsb
.publish_next:
 inc r12
 jmp .publish_loop
.publish_manifest:
 mov rdi,[new_id]
 mov sil,'c'
 call object_name
 lea rax,[free_nodes]
 mov rbx,[rax+r15*8]
 call clear_node
 mov rdi,rbx
 lea rsi,[object_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,[work_count]
 inc rcx
 shl rcx,8
 mov [rbx+UV_SIZE],rcx
 lea rdi,[rbx+UV_DATA]
 lea rsi,[snapshot]
 rep movsb
 lea rdi,[rbx+UV_DATA]
 mov rsi,[rbx+UV_SIZE]
 lea rdx,[hash_digest]
 call hash_manifest
 test eax,eax
 jnz .corrupt
 mov rdi,[new_id]
 mov sil,'h'
 call object_name
 inc r15
 lea rax,[free_nodes]
 mov rbx,[rax+r15*8]
 call clear_node
 mov rdi,rbx
 lea rsi,[object_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],SHA256_DIGEST_SIZE
 lea rdi,[rbx+UV_DATA]
 lea rsi,[hash_digest]
 mov ecx,SHA256_DIGEST_SIZE
 rep movsb
 cmp qword [signed_seed],0
 je .update_head
 mov rdi,[new_id]
 mov sil,'s'
 call object_name
 test eax,eax
 jnz .usage
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jnz .corrupt
 inc r15
 lea rax,[free_nodes]
 mov rcx,[rax+r15*8]
 mov rdi,[new_id]
 lea rsi,[hash_digest]
 mov rdx,[signed_seed]
 call vcs_signature_prepare
 test eax,eax
 jnz .done
.update_head:
 mov rax,[format_node]
 mov rdx,[new_id]
 mov [rax+UV_DATA+16],rdx
 mov [rax+UV_DATA+24],rdx
 mov rax,[active_ref_node]
 test rax,rax
 jz .commit_volume
 mov [rax+UV_DATA],rdx
.commit_volume:
 mov rbx,[merge_node]
 test rbx,rbx
 jz .clear_conflicts
 call clear_node
.clear_conflicts:
 mov rbx,[conflict_node]
 test rbx,rbx
 jz .clear_index
 call clear_node
.clear_index:
 mov rbx,[index_node]
 test rbx,rbx
 jz .commit_write
 call clear_node
.commit_write:
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[saved]
 mov esi,saved_len
 call emit
 mov rdi,[new_id]
 call print_id
 call print_newline
 jmp .ok
.check:
 mov r12d,1
.check_loop:
 cmp r12,[last_id]
 ja .check_ok
 mov rdi,r12
 call load_manifest
 test rax,rax
 jz .corrupt
 inc r12
 jmp .check_loop
.check_ok:
 lea rdi,[integrity_ok]
 mov esi,integrity_ok_len
 call emit
 jmp .ok
.log:
 ; Validate the entire chain before emitting partial history.
 mov r12,[head]
 xor r15d,r15d
.validate_log:
 test r12,r12
 jz .print_log
 inc r15
 cmp r15,UV_NODES
 ja .corrupt
 mov rdi,r12
 call load_manifest
 test rax,rax
 jz .corrupt
 mov r12,[rax+16]
 jmp .validate_log
.print_log:
 mov r12,[head]
 test r12,r12
 jnz .log_loop
 lea rdi,[unborn]
 mov esi,unborn_len
 call emit
 jmp .ok
.log_loop:
 mov rdi,r12
 mov sil,'c'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 lea r13,[rax+UV_DATA]
 lea rdi,[commit_label]
 mov esi,commit_label_len
 call emit
 mov rdi,r12
 call print_id
 cmp qword [mode],3
 jne .log_message
 lea rdi,[space]
 mov esi,1
 call emit
 lea rdi,[r13+VR_MESSAGE]
 call print_string
 call print_newline
 jmp .log_next
.log_message:
 call print_newline
 lea rdi,[r13+VR_MESSAGE]
 call print_message
 call print_newline
.log_next:
 mov r12,[r13+16]
 jnz .log_loop
 jmp .ok
.show:
 mov r12,[requested_id]
 test r12,r12
 jnz .show_id
 mov r12,[head]
.show_id:
 test r12,r12
 jz .usage
 cmp r12,[last_id]
 ja .usage
 mov rdi,r12
 call load_manifest
 test rax,rax
 jz .corrupt
 mov r13,rax
 lea rdi,[commit_label]
 mov esi,commit_label_len
 call emit
 mov rdi,r12
 call print_id
 call print_newline
 lea rdi,[r13+VR_MESSAGE]
 call print_message
 lea rdi,[files_label]
 mov esi,files_label_len
 call emit
 mov r14,[r13+24]
 add r13,VR_HEADER
.show_file:
 test r14,r14
 jz .ok
 lea rdi,[file_label]
 mov esi,2
 call emit
 mov rdi,[r13+VR_SIZE]
 call print_decimal
 lea rdi,[space]
 mov esi,1
 call emit
 mov rdi,r13
 call print_string
 call print_newline
 add r13,VR_ENTRY
 dec r14
 jmp .show_file
.restore:
 cmp qword [head],0
 je .usage
 mov rdi,[head]
 call load_manifest
 test rax,rax
 jz .corrupt
 mov r13,rax
 mov r14,[requested_id]            ; canonical absolute path pointer
 test r14,r14
 jz .usage
 ; Convert canonical absolute path to a repository-relative name.
 mov rcx,[root_size]
 cmp rcx,1
 je .restore_root
 lea rdi,[root]
 mov rsi,r14
 repe cmpsb
 jne .usage
 cmp byte [rsi],'/'
 jne .usage
 inc rsi
 jmp .restore_relative
.restore_root:
 cmp byte [r14],'/'
 jne .usage
 lea rsi,[r14+1]
.restore_relative:
 cmp byte [rsi],0
 je .usage
 mov r12,rsi
 mov r15,[r13+24]
 add r13,VR_HEADER
.restore_find:
 test r15,r15
 jz .missing
 mov rdi,r12
 mov rsi,r13
 call same_name
 test eax,eax
 jnz .restore_entry
 add r13,VR_ENTRY
 dec r15
 jmp .restore_find
.restore_entry:
 mov rdi,[r13+VR_BLOB]
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov r15,rax                      ; source blob node
 mov rdi,r14
 call uxv_find
 test rax,rax
 jz .restore_allocate
 cmp qword [rax+UV_TYPE],1
 jne .usage
 mov rbx,rax
 jmp .restore_write
.restore_allocate:
 call free_node
 test rax,rax
 jz .capacity
 mov rbx,rax
.restore_write:
 call clear_node
 mov rdi,rbx
 mov rsi,r14
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,[r15+UV_SIZE]
 mov [rbx+UV_SIZE],rcx
 lea rsi,[r15+UV_DATA]
 lea rdi,[rbx+UV_DATA]
 rep movsb
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[restored_label]
 mov esi,restored_label_len
 call emit
 mov rdi,r12
 call print_string
 call print_newline
 jmp .ok
.missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .done
.ok: xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.permission: mov eax,VCS_ERR_PERM
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.io: mov eax,VCS_ERR_IO
.done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

prepare_merge_state:
 mov qword [merge_node],0
 mov qword [conflict_node],0
 lea rsi,[merge_suffix]
 mov edx,12
 call metadata_node
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 cmp qword [rax+UV_SIZE],24
 jne .bad
 mov rcx,0x3147524d53435655
 cmp [rax+UV_DATA],rcx
 jne .bad
 mov rcx,[second_parent]
 cmp [rax+UV_DATA+8],rcx
 jne .bad
 mov [merge_node],rax
 lea rsi,[conflict_suffix]
 mov edx,16
 call metadata_node
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 cmp qword [rax+UV_SIZE],16
 jne .bad                         ; continue only after every conflict is resolved
 mov rcx,0x31464e4353435655
 cmp [rax+UV_DATA],rcx
 jne .bad
 cmp qword [rax+UV_DATA+8],0
 jne .conflict
 mov [conflict_node],rax
 xor eax,eax
 ret

prepare_replay_state:
 mov qword [conflict_node],0
 lea rsi,[conflict_suffix]
 mov edx,16
 call metadata_node
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 cmp qword [rax+UV_SIZE],16
 jne .conflict
 mov rcx,0x31464e4353435655
 cmp [rax+UV_DATA],rcx
 jne .bad
 cmp qword [rax+UV_DATA+8],0
 jne .conflict
 mov [conflict_node],rax
 xor eax,eax
 ret
.conflict: mov eax,VCS_ERR_CONFLICT
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret
.conflict: mov eax,VCS_ERR_CONFLICT
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

; rsi=suffix, edx=bytes including NUL -> rax=node or zero.
metadata_node:
 push rdx
 push rsi
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,30
 rep stosq
 mov rcx,[root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[root]
 lea rdi,[object_path]
 rep movsb
 pop rsi
 pop rcx
 rep movsb
 lea rdi,[object_path]
 jmp uxv_find

; Merge commit entry: rdi=second parent, rsi=message, rdx=writer.
; The ordinary history ABI remains unchanged.
vcs_history_merge:
 mov qword [signed_seed],0
 mov [second_parent],rdi
 mov qword [replay_request],0
 mov edi,1
 jmp vcs_history.entry

; Signed ordinary commit: rdi=message, rsi=seed32, rdx=writer.
vcs_history_signed:
 mov [signed_seed],rsi
 mov qword [second_parent],0
 mov qword [replay_request],0
 mov rsi,rdi
 mov edi,1
 jmp vcs_history.entry

; Signed merge: rdi=second parent, rsi=message, rdx=seed32, rcx=writer.
vcs_history_merge_signed:
 mov [signed_seed],rdx
 mov [second_parent],rdi
 mov qword [replay_request],0
 mov rdx,rcx
 mov edi,1
 jmp vcs_history.entry

; Replay commit: rdi=message, rsi=writer. Clears the empty conflict record but
; retains durable rebase state for the orchestrator to advance.
vcs_history_replay:
 mov qword [signed_seed],0
 mov qword [second_parent],0
 mov qword [replay_request],1
 mov rdx,rsi
 mov rsi,rdi
 mov edi,1
 jmp vcs_history.entry

; Signed replay: rdi=message, rsi=seed32, rdx=writer.
vcs_history_replay_signed:
 mov [signed_seed],rsi
 mov qword [second_parent],0
 mov qword [replay_request],1
 mov rsi,rdi
 mov edi,1
 jmp vcs_history.entry

; rdi=possible ancestor, rsi=descendant -> eax=1/0. Every visited manifest is
; validated and the bounded stack prevents malformed ancestry from looping.
vcs_is_ancestor:
 push rbx
 push r12
 push r13
 push r14
 push r15
 test rdi,rdi
 jz .no
 test rsi,rsi
 jz .no
 mov r12,rdi
 mov qword [ancestor_stack],rsi
 mov r13d,1
 xor r14d,r14d
.walk:
 test r13,r13
 jz .no
 dec r13
 lea rax,[ancestor_stack]
 mov r15,[rax+r13*8]
 cmp r15,r12
 je .yes
 xor ebx,ebx
.seen:
 cmp rbx,r14
 jae .new
 lea rax,[ancestor_seen]
 cmp [rax+rbx*8],r15
 je .walk
 inc rbx
 jmp .seen
.new:
 cmp r14,UV_NODES
 jae .no
 lea rax,[ancestor_seen]
 mov [rax+r14*8],r15
 inc r14
 mov rdi,r15
 call load_manifest
 test rax,rax
 jz .no
 mov rbx,rax
 mov rdx,[rbx+16]
 test rdx,rdx
 jz .second
 cmp r13,UV_NODES
 jae .no
 lea rax,[ancestor_stack]
 mov [rax+r13*8],rdx
 inc r13
.second:
 bt qword [rbx+32],63
 jnc .walk
 mov rdx,[rbx+VR_SECOND_PARENT]
 test rdx,rdx
 jz .no
 cmp r13,UV_NODES
 jae .no
 lea rax,[ancestor_stack]
 mov [rax+r13*8],rdx
 inc r13
 jmp .walk
.yes: mov eax,1
 jmp .ancestor_done
.no: xor eax,eax
.ancestor_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; rdi=left, rsi=right -> rax=nearest common commit from the right walk, or 0.
; This bounded deterministic base is sufficient for the local DAG and rejects
; malformed parents through load_manifest.
vcs_merge_base:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 test rdi,rdi
 jz .base_no
 test rsi,rsi
 jz .base_no
 mov rbp,rsi
 mov qword [ancestor_stack],rdi
 mov r13d,1
 xor r14d,r14d
.left_walk:
 test r13,r13
 jz .right_start
 dec r13
 lea rax,[ancestor_stack]
 mov r15,[rax+r13*8]
 xor ebx,ebx
.left_seen:
 cmp rbx,r14
 jae .left_new
 lea rax,[ancestor_seen]
 cmp [rax+rbx*8],r15
 je .left_walk
 inc rbx
 jmp .left_seen
.left_new:
 cmp r14,UV_NODES
 jae .base_no
 lea rax,[ancestor_seen]
 mov [rax+r14*8],r15
 inc r14
 mov rdi,r15
 call load_manifest
 test rax,rax
 jz .base_no
 mov rbx,rax
 mov rdx,[rbx+16]
 test rdx,rdx
 jz .left_second
 lea rcx,[ancestor_stack]
 mov [rcx+r13*8],rdx
 inc r13
.left_second:
 bt qword [rbx+32],63
 jnc .left_walk
 cmp r13,UV_NODES
 jae .base_no
 mov rdx,[rbx+VR_SECOND_PARENT]
 lea rax,[ancestor_stack]
 mov [rax+r13*8],rdx
 inc r13
 jmp .left_walk
.right_start:
 mov [ancestor_stack],rbp
 mov r13d,1
 xor r12d,r12d
.right_walk:
 test r13,r13
 jz .base_no
 dec r13
 lea rax,[ancestor_stack]
 mov r15,[rax+r13*8]
 xor ebx,ebx
.common:
 cmp rbx,r14
 jae .right_seen_start
 lea rax,[ancestor_seen]
 cmp [rax+rbx*8],r15
 je .base_yes
 inc rbx
 jmp .common
.right_seen_start:
 xor ebx,ebx
.right_seen:
 cmp rbx,r12
 jae .right_new
 lea rax,[ancestor_other]
 cmp [rax+rbx*8],r15
 je .right_walk
 inc rbx
 jmp .right_seen
.right_new:
 cmp r12,UV_NODES
 jae .base_no
 lea rax,[ancestor_other]
 mov [rax+r12*8],r15
 inc r12
 mov rdi,r15
 call load_manifest
 test rax,rax
 jz .base_no
 mov rbx,rax
 mov rdx,[rbx+16]
 test rdx,rdx
 jz .right_second
 cmp r13,UV_NODES
 jae .base_no
 lea rax,[ancestor_stack]
 mov [rax+r13*8],rdx
 inc r13
.right_second:
 bt qword [rbx+32],63
 jnc .right_walk
 cmp r13,UV_NODES
 jae .base_no
 mov rdx,[rbx+VR_SECOND_PARENT]
 lea rax,[ancestor_stack]
 mov [rax+r13*8],rdx
 inc r13
 jmp .right_walk
.base_yes: mov rax,r15
 jmp .base_done
.base_no: xor eax,eax
.base_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Discover nearest repository from cwd, stopping at malformed metadata.
global vcs_repo_discover
vcs_repo_discover:
discover:
 push rbx
 lea rdi,[root]
 xor eax,eax
 mov ecx,240
 rep stosb
 lea rsi,[uxv_cwd]
 lea rdi,[root]
 mov ecx,240
 rep movsb
.search:
 lea rdi,[root]
 xor ecx,ecx
.length:
 cmp byte [rdi+rcx],0
 je .length_done
 inc ecx
 jmp .length
.length_done:
 mov [root_size],rcx
 cmp ecx,227
 ja .parent
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 lea rsi,[root]
 lea rdi,[object_path]
 mov rcx,[root_size]
 cmp rcx,1
 jne .copy
 xor ecx,ecx
.copy:
 rep movsb
 lea rsi,[meta_suffix]
 mov ecx,6
 rep movsb
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .parent
 cmp qword [rax+UV_TYPE],2
 jne .corrupt
 lea rdi,[object_path]
.length_meta:
 cmp byte [rdi],0
 je .append_format
 inc rdi
 jmp .length_meta
.append_format:
 lea rsi,[format_suffix]
 mov ecx,8
 rep movsb
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],32
 jne .corrupt
 mov rdx,VR_REPO_MAGIC
 cmp [rax+UV_DATA],rdx
 jne .corrupt
 cmp qword [rax+UV_DATA+8],VR_REPO_VERSION
 jne .corrupt
 mov rdx,[rax+UV_DATA+16]
 mov rcx,[rax+UV_DATA+24]
 test rdx,rdx
 jnz .last_present
 mov rdx,rcx                     ; legacy linear repository
.last_present:
 cmp rcx,rdx
 ja .corrupt
 cmp rdx,VR_MAX_ID
 ja .corrupt
 mov [format_node],rax
 mov [last_id],rdx
 mov [head],rcx
 ; Optional repository-root ignore file. It remains trackable itself.
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 lea rsi,[root]
 lea rdi,[object_path]
 mov rcx,[root_size]
 cmp rcx,1
 jne .ignore_copy
 xor ecx,ecx
.ignore_copy:
 rep movsb
 lea rsi,[ignore_suffix]
 mov ecx,12
 rep movsb
 lea rdi,[object_path]
 call uxv_find
 mov [ignore_node],rax
 test rax,rax
 jz .found
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov rcx,[rax+UV_SIZE]
 cmp rcx,4096
 ja .corrupt
 lea rsi,[rax+UV_DATA]
 xor edx,edx
.validate_ignore:
 test rcx,rcx
 jz .found
 lodsb
 test al,al
 jz .corrupt
 cmp al,9
 je .ignore_valid
 cmp al,10
 je .ignore_newline
 cmp al,13
 je .ignore_valid
 cmp al,32
 jb .corrupt
 cmp al,127
 je .corrupt
.ignore_valid:
 inc edx
 cmp edx,239
 ja .corrupt
 dec rcx
 jmp .validate_ignore
.ignore_newline:
 xor edx,edx
 dec rcx
 jmp .validate_ignore
.found:
 ; Optional active branch must name a valid ref that equals current HEAD.
 mov qword [active_ref_node],0
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 lea rsi,[root]
 lea rdi,[object_path]
 mov rcx,[root_size]
 cmp rcx,1
 jne .active_root
 xor ecx,ecx
.active_root:
 rep movsb
 lea rsi,[active_suffix]
 mov ecx,13
 rep movsb
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .discover_done
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov rcx,[rax+UV_SIZE]
 cmp rcx,2
 jb .corrupt
 cmp rcx,33
 ja .corrupt
 cmp byte [rax+UV_DATA+rcx-1],0
 jne .corrupt
 lea r8,[rax+UV_DATA]
 mov r9,rcx
 dec r9
 xor edx,edx
.active_validate:
 cmp rdx,r9
 jae .active_valid
 mov al,[r8+rdx]
 test al,al
 jz .corrupt
 cmp al,'-'
 je .active_char
 cmp al,'.'
 je .active_char
 cmp al,'_'
 je .active_char
 cmp al,'0'
 jb .corrupt
 cmp al,'9'
 jbe .active_char
 or al,32
 cmp al,'a'
 jb .corrupt
 cmp al,'z'
 ja .corrupt
.active_char:
 inc edx
 jmp .active_validate
.active_valid:
 cmp byte [r8],'.'
 je .corrupt
 ; Build the matching branch ref path.
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 lea rsi,[root]
 lea rdi,[object_path]
 mov rcx,[root_size]
 cmp rcx,1
 jne .active_ref_root
 xor ecx,ecx
.active_ref_root:
 rep movsb
 lea rsi,[branch_suffix]
 mov ecx,10
 rep movsb
 dec rdi
.active_ref_name:
 mov al,[r8]
 stosb
 inc r8
 test al,al
 jnz .active_ref_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],8
 jne .corrupt
 mov rdx,[head]
 cmp [rax+UV_DATA],rdx
 jne .corrupt
 mov [active_ref_node],rax
.discover_done:
 xor eax,eax
 pop rbx
 ret
.parent:
 mov rcx,[root_size]
 cmp rcx,1
 jbe .missing
 lea rdi,[root]
.trim:
 dec rcx
 cmp byte [rdi+rcx],'/'
 jne .trim
 test rcx,rcx
 jnz .truncate
 inc rcx
.truncate:
 mov byte [rdi+rcx],0
 jmp .search
.missing: mov eax,VCS_ERR_NOT_FOUND
 pop rbx
 ret
.corrupt: mov eax,VCS_ERR_CORRUPT
 pop rbx
 ret

; rdi=id, sil=object kind. Fixed width names avoid aliasing. rax=0 or usage.
global vcs_object_name
vcs_object_name:
object_name:
 mov r8,rdi
 mov r9b,sil
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[root_size]
 cmp rcx,216
 ja .bad
 cmp rcx,1
 jne .copy
 xor ecx,ecx
.copy:
 lea rsi,[root]
 lea rdi,[object_path]
 rep movsb
 lea rsi,[meta_suffix]
 mov ecx,5
 rep movsb
 mov byte [rdi],'/'
 mov [rdi+1],r9b
 add rdi,2
 mov ecx,16
 lea r10,[digits]
.hex:
 rol r8,4
 mov rax,r8
 and eax,15
 mov al,[r10+rax]
 stosb
 loop .hex
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_USAGE
 ret

; Strict full manifest/blob validation, rdi=expected id -> rax=data or NULL.
global vcs_load_manifest
vcs_load_manifest:
load_manifest:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r15,rdi
 mov sil,'c'
 call object_name
 test eax,eax
 jnz .bad
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rbx,rax
 add rbx,UV_DATA
 mov rdx,VR_COM_MAGIC
 cmp [rbx],rdx
 jne .bad
 cmp [rbx+8],r15
 jne .bad
 mov rdx,[rbx+16]
 cmp rdx,r15
 jae .bad
 mov r12,[rbx+24]
 cmp r12,VR_FILES
 ja .bad
 mov rdx,r12
 inc rdx
 shl rdx,8
 cmp [rax+UV_SIZE],rdx
 jne .bad
 mov rcx,[rbx+32]
 btr rcx,63
 jnc .plain_parent
 mov rdx,[rbx+VR_SECOND_PARENT]
 test rdx,rdx
 jz .bad
 cmp rdx,r15
 jae .bad
.plain_parent:
 test rcx,rcx
 jz .bad
 cmp rcx,VR_MESSAGE_MAX
 ja .bad
 cmp byte [rbx+VR_MESSAGE+rcx],0
 jne .bad
 xor edx,edx
.message:
 cmp rdx,rcx
 jae .entries
 cmp byte [rbx+VR_MESSAGE+rdx],0
 je .bad
 inc rdx
 jmp .message
.entries:
 lea r13,[rbx+VR_HEADER]
.entry:
 test r12,r12
 jz .good
 mov rdi,r13
 call valid_relative
 test eax,eax
 jz .bad
 ; Relative names must be unique within the snapshot.
 lea r14,[rbx+VR_HEADER]
.unique:
 cmp r14,r13
 jae .blob
 mov rdi,r13
 mov rsi,r14
 call same_name
 test eax,eax
 jnz .bad
 add r14,VR_ENTRY
 jmp .unique
.blob:
 mov rdi,[r13+VR_BLOB]
 mov rax,rdi
 shr rax,8
 test rax,rax
 jz .bad
 cmp rax,r15
 ja .bad
 movzx eax,dil
 test eax,eax
 jz .bad
 cmp eax,VR_FILES
 ja .bad
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rdx,[r13+VR_SIZE]
 cmp rdx,4096
 ja .bad
 cmp [rax+UV_SIZE],rdx
 jne .bad
 add r13,VR_ENTRY
 dec r12
 jmp .entry
.good:
 mov rax,[rbx+24]
 inc rax
 shl rax,8
 mov rdi,rbx
 mov rsi,rax
 lea rdx,[hash_digest]
 call hash_manifest
 test eax,eax
 jnz .bad
 mov rdi,r15
 mov sil,'h'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 cmp qword [rax+UV_SIZE],SHA256_DIGEST_SIZE
 jne .bad
 xor rdx,rdx
 mov rcx,[hash_digest]
 xor rcx,[rax+UV_DATA]
 or rdx,rcx
 mov rcx,[hash_digest+8]
 xor rcx,[rax+UV_DATA+8]
 or rdx,rcx
 mov rcx,[hash_digest+16]
 xor rcx,[rax+UV_DATA+16]
 or rdx,rcx
 mov rcx,[hash_digest+24]
 xor rcx,[rax+UV_DATA+24]
 or rdx,rcx
 jnz .bad
 mov rax,rbx
 jmp .done
.bad: xor eax,eax
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; SHA-256("UVCSCHK1" || manifest || blob bytes in manifest order).
; rdi=manifest, rsi=exact manifest bytes, rdx=32-byte output.
hash_manifest:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 lea rdi,[hash_ctx]
 call sha256_init
 lea rdi,[hash_ctx]
 lea rsi,[hash_domain]
 mov edx,8
 call sha256_update
 lea rdi,[hash_ctx]
 mov rsi,r12
 mov rdx,r13
 call sha256_update
 mov r15,[r12+24]
 add r12,VR_HEADER
.blob:
 test r15,r15
 jz .final
 mov rdi,[r12+VR_BLOB]
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rdx,[r12+VR_SIZE]
 cmp [rax+UV_SIZE],rdx
 jne .bad
 lea rdi,[hash_ctx]
 lea rsi,[rax+UV_DATA]
 call sha256_update
 add r12,VR_ENTRY
 dec r15
 jmp .blob
.final:
 lea rdi,[hash_ctx]
 mov rsi,r14
 call sha256_final
 xor eax,eax
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; Gather regular files recursively, excluding every component named .vcs.
collect:
 push rbx
 push r12
 push r13
 mov qword [work_count],0
 lea rdi,[work]
 xor eax,eax
 mov ecx,VR_FILES*VR_ENTRY/8
 rep stosq
 lea rbx,[uxv_nodes+UV_NODE]
.node:
 cmp qword [rbx+UV_TYPE],1
 jne .next
 mov r12,rbx
 mov rcx,[root_size]
 cmp rcx,1
 je .root
 lea rdi,[root]
 mov rsi,rbx
 repe cmpsb
 jne .next
 cmp byte [rsi],'/'
 jne .next
 lea r12,[rsi+1]
 jmp .relative
.root:
 inc r12
.relative:
 mov rdi,r12
 call valid_relative
 test eax,eax
 jz .next
 mov rdi,r12
 call ignored
 test eax,eax
 jnz .next
 mov r13,[work_count]
 cmp r13,VR_FILES
 jae .capacity
 shl r13,8
 lea rax,[work]
 add r13,rax
 mov rdi,r13
 mov rsi,r12
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 mov [r13+240],rbx
 inc qword [work_count]
.next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .node
 xor eax,eax
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
.done:
 pop r13
 pop r12
 pop rbx
 ret

; Validate a bounded relative path; no empty/dot/dotdot/.vcs components.
valid_relative:
 xor ecx,ecx
 xor edx,edx
.component:
 mov r8d,ecx
.scan:
 cmp ecx,240
 jae .bad
 mov al,[rdi+rcx]
 test al,al
 jz .end_component
 cmp al,'/'
 je .end_component
 cmp al,32
 jb .bad
 cmp al,127
 je .bad
 inc ecx
 jmp .scan
.end_component:
 mov edx,ecx
 sub edx,r8d
 jz .bad
 cmp edx,1
 jne .dotdot
 cmp byte [rdi+r8],'.'
 je .bad
.dotdot:
 cmp edx,2
 jne .metadata
 cmp word [rdi+r8],'..'
 je .bad
.metadata:
 cmp edx,4
 jne .continue
 cmp dword [rdi+r8],0x7363762e ; .vcs
 je .bad
.continue:
 test al,al
 jz .good
 inc ecx
 jmp .component
.good: mov eax,1
 ret
.bad: xor eax,eax
 ret
same_name:
 push rcx
 xor ecx,ecx
.loop:
 mov al,[rdi+rcx]
 cmp al,[rsi+rcx]
 jne .no
 test al,al
 jz .yes
 inc ecx
 jmp .loop
.yes: mov eax,1
 pop rcx
 ret
.no: xor eax,eax
 pop rcx
 ret
find_work:
 push rbx
 mov r9,rdi
 xor ebx,ebx
.loop:
 cmp rbx,[work_count]
 jae .no
 mov rsi,rbx
 shl rsi,8
 lea rax,[work]
 add rsi,rax
 mov rdi,r9
 call same_name
 test eax,eax
 jnz .yes
 inc rbx
 jmp .loop
.yes: mov rax,rsi
 pop rbx
 ret

; If .vcs/index exists, build the prospective snapshot from staged paths and
; retain HEAD blobs for every unstaged path. Without an index, commit-all remains.
apply_index:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov qword [index_node],0
 ; Build index path.
 lea rdi,[object_path]
 xor eax,eax
 mov ecx,240
 rep stosb
 mov rcx,[root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[root]
 lea rdi,[object_path]
 rep movsb
 lea rsi,[index_suffix]
 mov ecx,12
 rep movsb
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .all
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov rbx,rax
 mov rcx,[rbx+UV_SIZE]
 cmp rcx,16
 jb .corrupt
 cmp rcx,3616
 ja .corrupt
 mov rax,rcx
 sub rax,16
 xor edx,edx
 mov r8,240
 div r8
 test rdx,rdx
 jnz .corrupt
 cmp rax,VR_FILES
 ja .corrupt
 cmp [rbx+UV_DATA+8],rax
 jne .corrupt
 mov rdx,0x3158444953435655
 cmp [rbx+UV_DATA],rdx
 jne .corrupt
 test rax,rax
 jz .corrupt
 mov [index_node],rbx
 ; Validate indexed paths and uniqueness.
 mov r14,rax
 lea r15,[rbx+UV_DATA+16]
.validate:
 mov rdi,r15
 call valid_relative
 test eax,eax
 jz .corrupt
 lea r12,[rbx+UV_DATA+16]
.unique:
 cmp r12,r15
 jae .validated
 mov rdi,r12
 mov rsi,r15
 call same_name
 test eax,eax
 jnz .corrupt
 add r12,240
 jmp .unique
.validated:
 add r15,240
 dec r14
 jnz .validate
 ; Preserve the current working view before rebuilding work as staged snapshot.
 mov rax,[work_count]
 mov [current_count],rax
 lea rsi,[work]
 lea rdi,[current]
 mov ecx,VR_FILES*VR_ENTRY/8
 rep movsq
 lea rdi,[work]
 xor eax,eax
 mov ecx,VR_FILES*VR_ENTRY/8
 rep stosq
 mov qword [work_count],0
 ; Begin with each HEAD entry: staged selects working/deletion, unstaged reuses blob.
 mov r13,[old_manifest]
 test r13,r13
 jz .current_additions
 mov r14,[r13+24]
 add r13,VR_HEADER
.old:
 test r14,r14
 jz .current_additions
 mov rdi,r13
 call indexed
 test eax,eax
 jz .keep_old
 mov rdi,r13
 call find_current
 test rax,rax
 jz .old_next                    ; staged deletion
 mov rsi,rax
 call append_work
 test eax,eax
 jnz .finish
 jmp .old_next
.keep_old:
 mov rdi,r13
 call append_old
 test eax,eax
 jnz .finish
.old_next:
 add r13,VR_ENTRY
 dec r14
 jmp .old
.current_additions:
 xor r12d,r12d
.current_loop:
 cmp r12,[current_count]
 jae .ok
 mov rax,r12
 shl rax,8
 lea r13,[current+rax]
 mov rdi,r13
 call find_old
 test rax,rax
 jnz .current_next
 mov rdi,r13
 call indexed
 test eax,eax
 jz .current_next
 mov rsi,r13
 call append_work
 test eax,eax
 jnz .finish
.current_next:
 inc r12
 jmp .current_loop
.all:
 xor eax,eax
 jmp .finish
.ok: xor eax,eax
 jmp .finish
.corrupt: mov eax,VCS_ERR_CORRUPT
.finish:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

indexed:
 mov r9,rdi
 mov rax,[index_node]
 mov rcx,[rax+UV_DATA+8]
 lea rsi,[rax+UV_DATA+16]
.loop:
 test rcx,rcx
 jz .no
 mov rdi,r9
 call same_name
 test eax,eax
 jnz .yes
 add rsi,240
 dec rcx
 jmp .loop
.yes: mov eax,1
 ret
.no: xor eax,eax
 ret
find_current:
 mov r9,rdi
 xor ecx,ecx
.loop:
 cmp rcx,[current_count]
 jae .no
 mov rax,rcx
 shl rax,8
 lea rsi,[current+rax]
 mov rdi,r9
 call same_name
 test eax,eax
 jnz .yes
 inc rcx
 jmp .loop
.yes: mov rax,rsi
 ret
.no: xor eax,eax
 ret
find_old:
 mov r9,rdi
 mov rax,[old_manifest]
 test rax,rax
 jz .no
 mov rcx,[rax+24]
 add rax,VR_HEADER
.loop:
 test rcx,rcx
 jz .no
 mov rdi,r9
 mov rsi,rax
 call same_name
 test eax,eax
 jnz .yes
 add rax,VR_ENTRY
 dec rcx
 jmp .loop
.yes: ret
.no: xor eax,eax
 ret
append_work:
 mov rcx,[work_count]
 cmp rcx,VR_FILES
 jae .full
 shl rcx,8
 lea rdi,[work+rcx]
 mov ecx,VR_ENTRY/8
 rep movsq
 inc qword [work_count]
 xor eax,eax
 ret
.full: mov eax,VCS_ERR_NO_MEM
 ret
append_old:
 push rbx
 mov rbx,rdi
 mov rcx,[work_count]
 cmp rcx,VR_FILES
 jae .full
 shl rcx,8
 lea rdi,[work+rcx]
 mov rsi,rbx
 mov ecx,240
 rep movsb
 mov rdi,[rbx+VR_BLOB]
 mov sil,'b'
 call object_name
 lea rdi,[object_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov rcx,[work_count]
 shl rcx,8
 lea rdx,[work+rcx]
 mov [rdx+240],rax
 mov [rdx+248],rbx
 inc qword [work_count]
 xor eax,eax
 pop rbx
 ret
.full: mov eax,VCS_ERR_NO_MEM
 pop rbx
 ret
.corrupt: mov eax,VCS_ERR_CORRUPT
 pop rbx
 ret
.no: xor eax,eax
 pop rbx
 ret
; Literal .vcsignore: exact paths, or directory prefixes ending in '/'.
; Blank lines and lines beginning '#' are comments. CR before LF is stripped.
global vcs_path_ignored
vcs_path_ignored:
ignored:
 push rbx
 push r12
 push r13
 push r14
 mov r14,rdi
 ; Always keep the rules file itself in snapshots.
 lea rsi,[ignore_suffix+1]
 call same_name
 test eax,eax
 jnz .no
 mov rbx,[ignore_node]
 test rbx,rbx
 jz .no
 mov r13,[rbx+UV_SIZE]
 lea r12,[rbx+UV_DATA]
.line:
 test r13,r13
 jz .no
 cmp byte [r12],10
 je .consume_empty
 cmp byte [r12],13
 je .consume_empty
 cmp byte [r12],'#'
 je .skip_line
 xor ecx,ecx
.length:
 cmp rcx,r13
 jae .compare
 mov al,[r12+rcx]
 cmp al,10
 je .trim
 cmp al,13
 je .trim
 inc ecx
 cmp ecx,239
 jbe .length
 jmp .skip_line
.trim:
.compare:
 test ecx,ecx
 jz .skip_line
 xor edx,edx
.bytes:
 cmp edx,ecx
 jae .pattern_end
 mov al,[r12+rdx]
 cmp al,[r14+rdx]
 jne .skip_line
 inc edx
 jmp .bytes
.pattern_end:
 cmp byte [r14+rcx],0
 je .yes
 cmp byte [r12+rcx-1],'/'
 je .yes
.skip_line:
 cmp byte [r12],10
 je .consume_empty
 inc r12
 dec r13
 jnz .skip_line
 jmp .no
.consume_empty:
 inc r12
 dec r13
 jmp .line
.yes: mov eax,1
 jmp .done
.no: xor eax,eax
.done:
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
clear_node:
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret
free_node:
 lea rax,[uxv_nodes+UV_NODE]
 mov ecx,UV_NODES-1
.scan:
 cmp qword [rax+UV_TYPE],0
 je .done
 add rax,UV_NODE
 loop .scan
 xor eax,eax
.done: ret
; Helpers are called with rsp % 16 == 8. Tail calls preserve callback alignment.
emit:
 jmp [writer]
print_newline:
 lea rdi,[newline]
 mov esi,1
 jmp emit
print_id:
 mov r8,rdi
 lea rdi,[number]
 lea r10,[digits]
 mov ecx,16
.loop:
 rol r8,4
 mov rax,r8
 and eax,15
 mov al,[r10+rax]
 stosb
 loop .loop
 lea rdi,[number]
 mov esi,16
 jmp emit
print_decimal:
 lea rsi,[number+16]
 mov rax,rdi
 mov ecx,10
.digit:
 xor edx,edx
 div rcx
 add dl,'0'
 dec rsi
 mov [rsi],dl
 test rax,rax
 jnz .digit
 lea rax,[number+16]
 sub rax,rsi
 mov rdi,rsi
 mov rsi,rax
 jmp emit
; Escape all non-ASCII/control/backslash bytes, including hostile messages.
print_string:
 mov rsi,rdi
 lea rdi,[escaped]
 lea r8,[digits]
.loop:
 lodsb
 test al,al
 jz .done
 cmp al,32
 jb .escape
 cmp al,126
 ja .escape
 cmp al,92
 je .escape
 stosb
 jmp .loop
.escape:
 mov byte [rdi],92
 mov byte [rdi+1],'x'
 movzx edx,al
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi+2],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+3],al
 add rdi,4
 jmp .loop
.done:
 mov rsi,rdi
 lea rdi,[escaped]
 sub rsi,rdi
 jmp emit
; Preserve message LF boundaries and indent each line; escape other controls.
; Max 215 message bytes expand to at most 1080 bytes, within escaped[2048].
print_message:
 mov rsi,rdi
 lea rdi,[escaped]
 lea r8,[digits]
 mov dword [rdi],0x20202020
 add rdi,4
.loop:
 lodsb
 test al,al
 jz .done
 cmp al,10
 je .newline
 cmp al,32
 jb .escape
 cmp al,126
 ja .escape
 cmp al,92
 je .escape
 stosb
 jmp .loop
.newline:
 stosb
 cmp byte [rsi],0
 je .loop
 mov dword [rdi],0x20202020
 add rdi,4
 jmp .loop
.escape:
 mov byte [rdi],92
 mov byte [rdi+1],'x'
 movzx edx,al
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi+2],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+3],al
 add rdi,4
 jmp .loop
.done:
 mov byte [rdi],10
 inc rdi
 mov rsi,rdi
 lea rdi,[escaped]
 sub rsi,rdi
 jmp emit
section .note.GNU-stack noalloc noexec nowrite progbits
