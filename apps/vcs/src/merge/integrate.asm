; Conservative whole-file three-way merge with durable conflict state.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/diff.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_find,uxv_free,uxv_commit,uxv_normalize
extern diff_files
extern vcs_repo_discover,vcs_load_manifest,vcs_merge_base,vcs_history_merge,vcs_history_merge_signed
extern vcs_checkout
extern vcs_object_name,vcs_path_ignored
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head,vcs_object_path
%define ME_SIZE 288
%define ME_BASE 240
%define ME_OURS 248
%define ME_THEIRS 256
%define ME_RESULT 264
%define ME_NODE 272
%define ME_MERGED 280
section .bss
merge_writer: resq 1
merge_seed: resq 1
merge_target: resq 1
merge_base_id: resq 1
state_kind: resq 1
merge_count: resq 1
merge_entries: resb VR_FILES*ME_SIZE
stage_count: resq 1
stage_paths: resb VR_FILES*240
conflict_count: resq 1
conflict_paths: resb VR_FILES*240
merge_path: resb 240
conflict_path: resb 240
index_path: resb 240
rebase_path: resb 240
pick_path: resb 240
active_path: resb 240
canonical: resb 240
parent_path: resb 240
merged_data: resb VR_FILES*4096
lm_bp: resq 1
lm_op: resq 1
lm_tp: resq 1
lm_br: resq 1
lm_or: resq 1
lm_tr: resq 1
lm_bl: resq 1
lm_ol: resq 1
lm_tl: resq 1
lm_out: resq 1
lm_size: resq 1
diff_request: resb vcs_diff_request_size
diff_scratch: resb VCS_DIFF_SCRATCH
diff_records: resb 512*vcs_diff_record_size
ours_hunks: resb VCS_DIFF_LINES*32
theirs_hunks: resb VCS_DIFF_LINES*32
ours_hcount: resq 1
theirs_hcount: resq 1
merge_base_ptr: resq 1
merge_base_size: resq 1
empty_manifest: resb VR_HEADER
section .rodata
merge_suffix: db '/.vcs/merge',0
conflict_suffix: db '/.vcs/conflicts',0
index_suffix: db '/.vcs/index',0
rebase_suffix: db '/.vcs/rebase',0
pick_suffix: db '/.vcs/pick',0
active_suffix: db '/.vcs/active',0
merge_magic: db 'UVCSMRG1'
conflict_magic: db 'UVCSCNF1'
index_magic: db 'UVCSIDX1'
ready_text: db 'Merge prepared; run vcs conflicts, resolve paths, then vcs merge --continue MESSAGE',10
ready_len equ $-ready_text
clean_text: db 'Merge prepared without conflicts; run vcs merge --continue MESSAGE',10
clean_len equ $-clean_text
resolved_text: db 'Resolved '
resolved_len equ $-resolved_text
none_text: db 'No unresolved conflicts',10
none_len equ $-none_text
aborted_text: db 'Merge aborted',10
aborted_len equ $-aborted_text
newline: db 10
section .text
global vcs_merge
; op 0 prepare(target id), 1 list conflicts, 2 resolve(canonical path),
; 3 continue(message), 4 abort. rdx=output callback, rcx=optional seed32.
vcs_merge:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,4
 ja .usage
 test rdx,rdx
 jz .usage
 mov rbp,rdi
 mov r12,rsi
 mov [merge_writer],rdx
 mov [merge_seed],rcx
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 cmp rbp,0
 je .prepare
 call load_state
 test eax,eax
 jnz .done
 cmp rbp,4
 je .abort
 cmp rbp,1
 je .list
 cmp rbp,2
 je .resolve
 cmp qword [conflict_count],0
 jne .conflict
 test r12,r12
 jz .usage
 mov rdi,[merge_target]
 mov rsi,r12
 cmp qword [merge_seed],0
 jne .continue_signed
 mov rdx,[merge_writer]
 call vcs_history_merge
 jmp .done
.continue_signed:
 mov rdx,[merge_seed]
 mov rcx,[merge_writer]
 call vcs_history_merge_signed
 jmp .done
.abort:
 lea rdi,[active_path]
 call uxv_find
 xor edx,edx
 test rax,rax
 jz .abort_checkout
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 lea rdx,[rax+UV_DATA]
.abort_checkout:
 mov rdi,[vcs_repo_head]
 mov rsi,[merge_writer]
 call vcs_checkout
 test eax,eax
 jnz .done
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[merge_path]
 call clear_named
 lea rdi,[conflict_path]
 call clear_named
 lea rdi,[index_path]
 call clear_named
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[aborted_text]
 mov esi,aborted_len
 call emit
 jmp .ok
.prepare:
 test r12,r12
 jz .usage
 mov [merge_target],r12
 mov qword [state_kind],0
 cmp qword [vcs_repo_head],0
 je .usage
 cmp r12,[vcs_repo_head]
 je .conflict
 lea rdi,[merge_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[index_path]
 call uxv_find
 test rax,rax
 jnz .conflict                    ; do not mix an existing staged operation
 lea rdi,[pick_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[rebase_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r15,rax
 mov rdi,[vcs_repo_head]
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r14,rax
 mov rdi,[vcs_repo_head]
 mov rsi,r12
 call vcs_merge_base
 test rax,rax
 jz .conflict
 mov [merge_base_id],rax
 mov rdi,rax
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r13,rax
 mov qword [merge_count],0
 lea rdi,[merge_entries]
 xor eax,eax
 mov ecx,(VR_FILES*ME_SIZE)/8
 rep stosq
 mov rdi,r13
 mov esi,ME_BASE
 call add_manifest
 test eax,eax
 jnz .done
 mov rdi,r14
 mov esi,ME_OURS
 call add_manifest
 test eax,eax
 jnz .done
 mov rdi,r15
 mov esi,ME_THEIRS
 call add_manifest
 test eax,eax
 jnz .done
 call require_clean
 test eax,eax
 jnz .done
 call choose_results
 test eax,eax
 jnz .done
 call preflight_capacity
 test eax,eax
 jnz .done
 call publish_merge
 test eax,eax
 jnz .done
 cmp qword [conflict_count],0
 je .clean_ready
 lea rdi,[ready_text]
 mov esi,ready_len
 call emit
 jmp .ok
.clean_ready:
 lea rdi,[clean_text]
 mov esi,clean_len
 call emit
 jmp .ok
.list:
 mov r14,[conflict_count]
 test r14,r14
 jnz .list_rows
 lea rdi,[none_text]
 mov esi,none_len
 call emit
 jmp .ok
.list_rows:
 lea r15,[conflict_paths]
.list_row:
 mov rdi,r15
 call print_string
 call print_newline
 add r15,240
 dec r14
 jnz .list_row
 jmp .ok
.resolve:
 test r12,r12
 jz .usage
 mov rdi,r12
 lea rsi,[canonical]
 call uxv_normalize
 test rax,rax
 js .usage
 lea rdi,[canonical]
 call relative_path
 test rax,rax
 jz .usage
 mov r15,rax
 xor r14d,r14d
.resolve_find:
 cmp r14,[conflict_count]
 jae .usage
 mov rax,r14
 imul rax,240
 lea rsi,[conflict_paths+rax]
 mov rdi,r15
 call same_name
 test eax,eax
 jnz .resolve_erase
 inc r14
 jmp .resolve_find
.resolve_erase:
 mov rax,[conflict_count]
 dec rax
 sub rax,r14
 imul rcx,rax,240
 mov rdi,rsi
 add rsi,240
 rep movsb
 dec qword [conflict_count]
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 mov rbx,rax
 mov rcx,[conflict_count]
 imul rcx,240
 add rcx,16
 mov [rbx+UV_SIZE],rcx
 mov rax,[conflict_count]
 mov [rbx+UV_DATA+8],rax
 lea rsi,[conflict_paths]
 lea rdi,[rbx+UV_DATA+16]
 sub rcx,16
 rep movsb
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[resolved_text]
 mov esi,resolved_len
 call emit
 mov rdi,r15
 call print_string
 call print_newline
 jmp .ok
.ok: xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .done
.capacity: mov eax,VCS_ERR_NO_MEM
 jmp .done
.corrupt: mov eax,VCS_ERR_CORRUPT
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

global vcs_worktree_clean,vcs_threeway_replay
; rdi=manifest ID -> VCS status. Read-only exact clean-tree gate.
vcs_worktree_clean:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 call vcs_repo_discover
 test eax,eax
 jnz .clean_done
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .clean_corrupt
 mov r14,rax
 mov qword [merge_count],0
 lea rdi,[merge_entries]
 xor eax,eax
 mov ecx,(VR_FILES*ME_SIZE)/8
 rep stosq
 mov rdi,r14
 mov esi,ME_OURS
 call add_manifest
 test eax,eax
 jnz .clean_done
 call require_clean
 jmp .clean_done
.clean_corrupt: mov eax,VCS_ERR_CORRUPT
.clean_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; Apply one old commit as a three-way patch: rdi=old parent/base,
; rsi=current rewritten HEAD/ours, rdx=old commit/theirs. Writes the ordinary
; index and conflict list in one transaction. Returns conflict count in rdx.
vcs_threeway_replay:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r12,rsi
 mov rbx,rdx
 call vcs_repo_discover
 test eax,eax
 jnz .replay_done
 call make_paths
 lea rdi,[merge_path]
 call uxv_find
 test rax,rax
 jnz .replay_conflict
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jnz .replay_conflict
 lea rdi,[index_path]
 call uxv_find
 test rax,rax
 jnz .replay_conflict
 test rbp,rbp
 jz .replay_empty_base
 mov rdi,rbp
 call vcs_load_manifest
 test rax,rax
 jz .replay_corrupt
 mov r13,rax
 jmp .replay_ours
.replay_empty_base:
 lea r13,[empty_manifest]
.replay_ours:
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .replay_corrupt
 mov r14,rax
 test rbx,rbx
 jz .replay_empty_theirs
 mov rdi,rbx
 call vcs_load_manifest
 test rax,rax
 jz .replay_corrupt
 mov r15,rax
 jmp .replay_manifests
.replay_empty_theirs:
 lea r15,[empty_manifest]
.replay_manifests:
 mov qword [state_kind],1
 mov qword [merge_count],0
 lea rdi,[merge_entries]
 xor eax,eax
 mov ecx,(VR_FILES*ME_SIZE)/8
 rep stosq
 mov rdi,r13
 mov esi,ME_BASE
 call add_manifest
 test eax,eax
 jnz .replay_done
 mov rdi,r14
 mov esi,ME_OURS
 call add_manifest
 test eax,eax
 jnz .replay_done
 mov rdi,r15
 mov esi,ME_THEIRS
 call add_manifest
 test eax,eax
 jnz .replay_done
 call require_clean
 test eax,eax
 jnz .replay_done
 call choose_results
 test eax,eax
 jnz .replay_done
 call preflight_capacity
 test eax,eax
 jnz .replay_done
 call publish_merge
 test eax,eax
 jnz .replay_done
 mov rdx,[conflict_count]
 jmp .replay_done
.replay_conflict: mov eax,VCS_ERR_CONFLICT
 jmp .replay_done
.replay_corrupt: mov eax,VCS_ERR_CORRUPT
.replay_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; Add all manifest paths and remember the manifest entry at field offset esi.
add_manifest:
 push rbx
 push r12
 push r13
 push r14
 mov r12,rdi
 mov r13,rsi
 mov r14,[r12+24]
 add r12,VR_HEADER
.loop:
 test r14,r14
 jz .ok
 mov rdi,r12
 call find_entry
 test rax,rax
 jnz .set
 mov rax,[merge_count]
 cmp rax,VR_FILES
 jae .full
 imul rax,ME_SIZE
 lea rbx,[merge_entries+rax]
 mov rdi,rbx
 mov rsi,r12
 mov ecx,240
 rep movsb
 inc qword [merge_count]
 mov rax,rbx
.set:
 mov [rax+r13],r12
 add r12,VR_ENTRY
 dec r14
 jmp .loop
.ok: xor eax,eax
 jmp .done
.full: mov eax,VCS_ERR_NO_MEM
.done:
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

find_entry:
 push rbx
 mov rbx,rdi
 xor ecx,ecx
.loop:
 cmp rcx,[merge_count]
 jae .no
 mov rax,rcx
 imul rax,ME_SIZE
 lea rsi,[merge_entries+rax]
 mov rdi,rbx
 call same_name
 test eax,eax
 jnz .yes
 inc rcx
 jmp .loop
.yes: mov rax,rsi
 pop rbx
 ret
.no: xor eax,eax
 pop rbx
 ret

require_clean:
 xor r12d,r12d
.tracked:
 cmp r12,[merge_count]
 jae .scan_extra
 mov rax,r12
 imul rax,ME_SIZE
 lea r13,[merge_entries+rax]
 mov rdi,r13
 call absolute_path
 test eax,eax
 jnz .bad
 lea rdi,[canonical]
 call uxv_find
 mov [r13+ME_NODE],rax
 mov rsi,[r13+ME_OURS]
 test rsi,rsi
 jz .must_absent
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rdi,rax
 call node_equals_entry
 test eax,eax
 jz .bad
 jmp .next
.must_absent:
 test rax,rax
 jnz .bad
.next:
 inc r12
 jmp .tracked
.scan_extra:
 lea rbx,[uxv_nodes+UV_NODE]
.node:
 cmp qword [rbx+UV_TYPE],1
 jne .node_next
 mov rdi,rbx
 call working_relative
 test rax,rax
 jz .node_next
 mov rdi,rax
 call vcs_path_ignored
 test eax,eax
 jnz .node_next
 mov rdi,rbx
 call working_relative
 mov rdi,rax
 call find_entry
 test rax,rax
 jz .bad
 cmp qword [rax+ME_OURS],0
 je .bad
.node_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .node
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CONFLICT
 ret

choose_results:
 mov qword [stage_count],0
 mov qword [conflict_count],0
 xor r12d,r12d
.loop:
 cmp r12,[merge_count]
 jae .ok
 mov rax,r12
 imul rax,ME_SIZE
 lea r13,[merge_entries+rax]
 mov rdi,[r13+ME_OURS]
 mov rsi,[r13+ME_THEIRS]
 call entries_equal
 test eax,eax
 jnz .ours
 mov rdi,[r13+ME_BASE]
 mov rsi,[r13+ME_OURS]
 call entries_equal
 test eax,eax
 jnz .theirs
 mov rdi,[r13+ME_BASE]
 mov rsi,[r13+ME_THEIRS]
 call entries_equal
 test eax,eax
 jnz .ours
 mov rdi,[r13+ME_BASE]
 test rdi,rdi
 jz .file_conflict
 mov rsi,[r13+ME_OURS]
 test rsi,rsi
 jz .file_conflict
 mov rdx,[r13+ME_THEIRS]
 test rdx,rdx
 jz .file_conflict
 mov rcx,r12
 call try_diff_merge
 test eax,eax
 jnz .line_merged
 mov rdi,[r13+ME_BASE]
 mov rsi,[r13+ME_OURS]
 mov rdx,[r13+ME_THEIRS]
 mov rcx,r12
 call try_line_merge
 test eax,eax
 jz .file_conflict
.line_merged:
 inc rdx
 mov [r13+ME_MERGED],rdx
 mov rax,[r13+ME_OURS]
 mov [r13+ME_RESULT],rax
 jmp .stage
.file_conflict:
 mov rax,[r13+ME_OURS]
 mov [r13+ME_RESULT],rax
 mov rdi,r13
 lea rsi,[conflict_paths]
 mov rax,[conflict_count]
 imul rax,240
 add rsi,rax
 call copy_path
 inc qword [conflict_count]
 jmp .stage
.theirs:
 mov rax,[r13+ME_THEIRS]
 mov [r13+ME_RESULT],rax
 jmp .stage
.ours:
 mov rax,[r13+ME_OURS]
 mov [r13+ME_RESULT],rax
 jmp .next
.stage:
 mov rdi,r13
 lea rsi,[stage_paths]
 mov rax,[stage_count]
 imul rax,240
 add rsi,rax
 call copy_path
 inc qword [stage_count]
.next:
 inc r12
 jmp .loop
.ok: xor eax,eax
 ret

preflight_capacity:
 xor r12d,r12d                    ; available free/deleted nodes
 lea rbx,[uxv_nodes+UV_NODE]
.free:
 cmp qword [rbx+UV_TYPE],0
 jne .free_next
 inc r12
.free_next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .free
 xor r13d,r13d                    ; required additions plus metadata
 mov r14d,2
 cmp qword [stage_count],0
 je .paths
 inc r14
.paths:
 cmp r13,[merge_count]
 jae .check
 mov rax,r13
 imul rax,ME_SIZE
 lea r15,[merge_entries+rax]
 cmp qword [r15+ME_NODE],0
 je .missing
 cmp qword [r15+ME_RESULT],0
 jne .next
 inc r12                           ; deleted node is recyclable
 jmp .next
.missing:
 cmp qword [r15+ME_RESULT],0
 je .next
 mov rdi,r15
 call absolute_path
 test eax,eax
 jnz .path_bad
 call parent_exists
 test eax,eax
 jz .path_bad
 inc r14
.next:
 inc r13
 jmp .paths
.check:
 cmp r12,r14
 jb .full
 xor eax,eax
 ret
.full: mov eax,VCS_ERR_NO_MEM
 ret
.path_bad: mov eax,VCS_ERR_CONFLICT
 ret

publish_merge:
 ; Clear deletions first so uxv_free can recycle them.
 xor r12d,r12d
.delete:
 cmp r12,[merge_count]
 jae .write
 mov rax,r12
 imul rax,ME_SIZE
 lea r13,[merge_entries+rax]
 cmp qword [r13+ME_RESULT],0
 jne .delete_next
 mov rdi,[r13+ME_NODE]
 test rdi,rdi
 jz .delete_next
 call clear_node
.delete_next:
 inc r12
 jmp .delete
.write:
 xor r12d,r12d
.write_loop:
 cmp r12,[merge_count]
 jae .metadata
 mov rax,r12
 imul rax,ME_SIZE
 lea r13,[merge_entries+rax]
 mov r15,[r13+ME_RESULT]
 test r15,r15
 jz .write_next
 cmp qword [r13+ME_MERGED],0
 jne .write_merged
 mov rdi,r15
 mov rsi,[r13+ME_OURS]
 call entries_equal
 test eax,eax
 jnz .write_next
 mov rbx,[r13+ME_NODE]
 test rbx,rbx
 jnz .have
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
.have:
 mov rdi,rbx
 call clear_node
 mov rdi,r13
 call absolute_path
 mov rdi,rbx
 lea rsi,[canonical]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,[r15+VR_SIZE]
 mov [rbx+UV_SIZE],rcx
 mov rdi,r15
 call entry_blob
 test rax,rax
 jz .corrupt
 mov rcx,[r15+VR_SIZE]
 lea rsi,[rax+UV_DATA]
 lea rdi,[rbx+UV_DATA]
 rep movsb
 jmp .write_next
.write_merged:
 mov rbx,[r13+ME_NODE]
 test rbx,rbx
 jnz .merged_have
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
.merged_have:
 mov rdi,rbx
 call clear_node
 mov rdi,r13
 call absolute_path
 mov rdi,rbx
 lea rsi,[canonical]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,[r13+ME_MERGED]
 dec rcx
 mov [rbx+UV_SIZE],rcx
 mov rax,r12
 shl rax,12
 lea rsi,[merged_data+rax]
 lea rdi,[rbx+UV_DATA]
 rep movsb
.write_next:
 inc r12
 jmp .write_loop
.metadata:
 cmp qword [state_kind],1
 je .conflict_metadata
 lea rdi,[merge_path]
 lea rsi,[merge_magic]
 mov edx,24
 call new_metadata
 test rax,rax
 jz .capacity
 mov rbx,rax
 mov rax,[merge_target]
 mov [rbx+UV_DATA+8],rax
 mov rax,[merge_base_id]
 mov [rbx+UV_DATA+16],rax
.conflict_metadata:
 lea rdi,[conflict_path]
 lea rsi,[conflict_magic]
 mov rdx,[conflict_count]
 imul rdx,240
 add rdx,16
 call new_metadata
 test rax,rax
 jz .capacity
 mov rbx,rax
 mov rax,[conflict_count]
 mov [rbx+UV_DATA+8],rax
 mov rcx,rax
 imul rcx,240
 lea rsi,[conflict_paths]
 lea rdi,[rbx+UV_DATA+16]
 rep movsb
 cmp qword [stage_count],0
 je .commit
 lea rdi,[index_path]
 lea rsi,[index_magic]
 mov rdx,[stage_count]
 imul rdx,240
 add rdx,16
 call new_metadata
 test rax,rax
 jz .capacity
 mov rbx,rax
 mov rax,[stage_count]
 mov [rbx+UV_DATA+8],rax
 mov rcx,rax
 imul rcx,240
 lea rsi,[stage_paths]
 lea rdi,[rbx+UV_DATA+16]
 rep movsb
.commit:
 call uxv_commit
 test rax,rax
 js .io
 xor eax,eax
 ret
.capacity: mov eax,VCS_ERR_NO_MEM
 ret
.corrupt: mov eax,VCS_ERR_CORRUPT
 ret
.io: mov eax,VCS_ERR_IO
 ret

load_state:
 lea rdi,[merge_path]
 call uxv_find
 test rax,rax
 jnz .merge_state
 cmp rbp,2
 ja .missing
 lea rdi,[rebase_path]
 call uxv_find
 test rax,rax
 jnz .operation_state
 lea rdi,[pick_path]
 call uxv_find
 test rax,rax
 jz .missing
 cmp qword [rax+UV_SIZE],32
 jne .bad
 mov rdx,0x314b435053435655
 cmp [rax+UV_DATA],rdx
 jne .bad
.operation_state:
 cmp qword [rax+UV_TYPE],1
 jne .bad
 jmp .conflicts
.merge_state:
 cmp qword [rax+UV_TYPE],1
 jne .bad
 cmp qword [rax+UV_SIZE],24
 jne .bad
 mov rdx,0x3147524d53435655
 cmp [rax+UV_DATA],rdx
 jne .bad
 mov rdx,[rax+UV_DATA+8]
 mov [merge_target],rdx
 mov rdx,[rax+UV_DATA+16]
 mov [merge_base_id],rdx
.conflicts:
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 cmp rcx,16
 jb .bad
 cmp rcx,3616
 ja .bad
 mov rdx,rcx
 sub rdx,16
 mov rax,rdx
 xor edx,edx
 mov r8,240
 div r8
 test rdx,rdx
 jnz .bad
 cmp rax,VR_FILES
 ja .bad
 mov rbx,rax
 lea rdi,[conflict_path]
 call uxv_find
 mov rdx,0x31464e4353435655
 cmp [rax+UV_DATA],rdx
 jne .bad
 cmp [rax+UV_DATA+8],rbx
 jne .bad
 mov [conflict_count],rbx
 imul rcx,rbx,240
 lea rsi,[rax+UV_DATA+16]
 lea rdi,[conflict_paths]
 rep movsb
 xor eax,eax
 ret
.missing: mov eax,VCS_ERR_NOT_FOUND
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

make_paths:
 lea rdi,[merge_path]
 lea rsi,[merge_suffix]
 mov edx,12
 call make_metadata_path
 lea rdi,[conflict_path]
 lea rsi,[conflict_suffix]
 mov edx,16
 call make_metadata_path
 lea rdi,[index_path]
 lea rsi,[index_suffix]
 mov edx,12
 call make_metadata_path
 lea rdi,[rebase_path]
 lea rsi,[rebase_suffix]
 mov edx,13
 call make_metadata_path
 lea rdi,[pick_path]
 lea rsi,[pick_suffix]
 mov edx,11
 call make_metadata_path
 lea rdi,[active_path]
 lea rsi,[active_suffix]
 mov edx,13
 jmp make_metadata_path
make_metadata_path:
 push rdi
 xor eax,eax
 mov ecx,30
 rep stosq
 pop rdi
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 push rsi
 lea rsi,[vcs_repo_root]
 rep movsb
 pop rsi
 mov ecx,edx
 rep movsb
 ret

absolute_path:
 push rdi
 xor r8d,r8d
.measure:
 cmp byte [rdi+r8],0
 je .measured
 inc r8
 cmp r8,239
 ja .bad
 jmp .measure
.measured:
 mov rax,[vcs_repo_root_size]
 add rax,r8
 cmp qword [vcs_repo_root_size],1
 je .bound
 inc rax
.bound:
 cmp rax,239
 ja .bad
 lea rdi,[canonical]
 xor eax,eax
 mov ecx,30
 rep stosq
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 lea rsi,[vcs_repo_root]
 lea rdi,[canonical]
 rep movsb
 cmp qword [vcs_repo_root_size],1
 je .relative
 mov byte [rdi],'/'
 inc rdi
.relative:
 pop rsi
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 xor eax,eax
 ret
.bad:
 pop rdi
 mov eax,VCS_ERR_USAGE
 ret

parent_exists:
 lea rsi,[canonical]
 lea rdi,[parent_path]
 mov ecx,240
 rep movsb
 lea rdi,[parent_path+239]
.trim:
 cmp byte [rdi],'/'
 je .found
 dec rdi
 lea rax,[parent_path]
 cmp rdi,rax
 jae .trim
 xor eax,eax
 ret
.found:
 lea rax,[parent_path]
 cmp rdi,rax
 jne .zero
 inc rdi
.zero:
 mov byte [rdi],0
 lea rdi,[parent_path]
 call uxv_find
 test rax,rax
 jz .no
 cmp qword [rax+UV_TYPE],2
 jne .no
 mov eax,1
 ret
.no: xor eax,eax
 ret

; Exact diff3 over two LCS scripts. Non-overlapping insert/delete/replace hunks
; are combined; overlapping non-identical hunks remain conflicts.
; rdi=base entry, rsi=ours, rdx=theirs, rcx=slot. eax=1, rdx=size on success.
try_diff_merge:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 mov r15,rcx
 mov rdi,r12
 call entry_blob
 test rax,rax
 jz .fail
 lea rbx,[rax+UV_DATA]
 mov [merge_base_ptr],rbx
 mov rax,[r12+VR_SIZE]
 mov [merge_base_size],rax
 mov rdi,r13
 call entry_blob
 test rax,rax
 jz .fail
 lea rdx,[rax+UV_DATA]
 mov rcx,[r13+VR_SIZE]
 mov rdi,rbx
 mov rsi,[merge_base_size]
 lea r8,[ours_hunks]
 call build_hunks
 test rax,rax
 js .fail
 mov [ours_hcount],rax
 mov rdi,r14
 call entry_blob
 test rax,rax
 jz .fail
 lea rdx,[rax+UV_DATA]
 mov rcx,[r14+VR_SIZE]
 mov rdi,[merge_base_ptr]
 mov rsi,[merge_base_size]
 lea r8,[theirs_hunks]
 call build_hunks
 test rax,rax
 js .fail
 mov [theirs_hcount],rax
 mov rax,r15
 shl rax,12
 lea rdi,[merged_data+rax]
 mov [lm_out],rdi
 mov qword [lm_size],0
 xor r12d,r12d                    ; ours hunk index
 xor r13d,r13d                    ; theirs hunk index
 xor r14d,r14d                    ; consumed base byte offset
.next:
 cmp r12,[ours_hcount]
 jb .have_ours
 cmp r13,[theirs_hcount]
 jae .tail
 mov eax,2
 jmp .select
.have_ours:
 cmp r13,[theirs_hcount]
 jb .both
 mov eax,1
 jmp .select
.both:
 mov rax,r12
 shl rax,5
 lea rbx,[ours_hunks+rax]
 mov rax,r13
 shl rax,5
 lea r15,[theirs_hunks+rax]
 mov rax,[rbx]
 cmp rax,[r15]
 jb .ours_first
 ja .theirs_first
 ; Same start: only identical hunk ranges and replacement bytes commute.
 mov rax,[rbx+8]
 cmp rax,[r15+8]
 jne .fail
 mov rax,[rbx+24]
 cmp rax,[r15+24]
 jne .fail
 mov rcx,rax
 mov rdi,[rbx+16]
 mov rsi,[r15+16]
 repe cmpsb
 jne .fail
 mov eax,3
 jmp .select
.ours_first:
 mov rax,[rbx+8]
 cmp rax,[r15]
 ja .fail
 mov eax,1
 jmp .select
.theirs_first:
 mov rax,[r15+8]
 cmp rax,[rbx]
 ja .fail
 mov eax,2
.select:
 cmp eax,2
 je .take_theirs
 mov rdx,r12
 shl rdx,5
 lea rbx,[ours_hunks+rdx]
 inc r12
 cmp eax,3
 jne .apply
 inc r13
 jmp .apply
.take_theirs:
 mov rdx,r13
 shl rdx,5
 lea rbx,[theirs_hunks+rdx]
 inc r13
.apply:
 cmp [rbx],r14
 jb .fail
 mov rcx,[rbx]
 sub rcx,r14
 mov rsi,[merge_base_ptr]
 add rsi,r14
 call append_output
 test eax,eax
 jz .fail
 mov rcx,[rbx+24]
 mov rsi,[rbx+16]
 call append_output
 test eax,eax
 jz .fail
 mov r14,[rbx+8]
 jmp .next
.tail:
 mov rcx,[merge_base_size]
 sub rcx,r14
 mov rsi,[merge_base_ptr]
 add rsi,r14
 call append_output
 test eax,eax
 jz .fail
 mov rdx,[lm_size]
 mov eax,1
 jmp .done
.fail: xor eax,eax
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; Convert diff records to base-range/replacement-span hunks.
; rdi/rsi=base, rdx/rcx=side, r8=256-entry output. rax=count or -1.
build_hunks:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,r8
 lea rax,[diff_scratch]
 mov [diff_request+vcs_diff_request.scratch],rax
 mov qword [diff_request+vcs_diff_request.scratch_size],VCS_DIFF_SCRATCH
 lea rax,[diff_records]
 mov [diff_request+vcs_diff_request.output],rax
 mov qword [diff_request+vcs_diff_request.capacity],512
 mov [diff_request+vcs_diff_request.old],rdi
 mov [diff_request+vcs_diff_request.old_size],rsi
 mov [diff_request+vcs_diff_request.new],rdx
 mov [diff_request+vcs_diff_request.new_size],rcx
 lea rdi,[diff_request]
 call diff_files
 test eax,eax
 jnz .bad
 mov r13,rdx                      ; records remaining
 lea r14,[diff_records]
 xor r15d,r15d                   ; hunk count
.record:
 test r13,r13
 jz .ok
 cmp qword [r14+vcs_diff_record.kind],VCS_DIFF_EQUAL
 jne .hunk
 add r14,vcs_diff_record_size
 dec r13
 jmp .record
.hunk:
 cmp r15,VCS_DIFF_LINES
 jae .bad
 mov rax,r15
 shl rax,5
 lea rbx,[r12+rax]
 mov rax,[r14+vcs_diff_record.old_offset]
 mov [rbx],rax
 mov [rbx+8],rax
 mov rax,[r14+vcs_diff_record.new_offset]
 mov [rbx+16],rax                 ; temporarily replacement offset
 mov [rbx+24],rax                 ; replacement end
.hunk_record:
 test r13,r13
 jz .hunk_done
 mov rax,[r14+vcs_diff_record.kind]
 cmp rax,VCS_DIFF_EQUAL
 je .hunk_done
 cmp rax,VCS_DIFF_DELETE
 jne .insert
 mov rax,[r14+vcs_diff_record.length]
 add [rbx+8],rax
 jmp .consume
.insert:
 cmp rax,VCS_DIFF_INSERT
 jne .bad
 mov rax,[r14+vcs_diff_record.length]
 add [rbx+24],rax
.consume:
 add r14,vcs_diff_record_size
 dec r13
 jmp .hunk_record
.hunk_done:
 mov rax,[rbx+16]
 mov rcx,[diff_request+vcs_diff_request.new]
 add rcx,rax
 mov [rbx+16],rcx
 mov rcx,[rbx+24]
 sub rcx,rax
 mov [rbx+24],rcx
 inc r15
 jmp .record
.ok: mov rax,r15
 jmp .done
.bad: mov rax,-1
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

append_output:
 mov rax,[lm_size]
 add rax,rcx
 cmp rax,4096
 ja .bad
 mov rdi,[lm_out]
 add rdi,[lm_size]
 rep movsb
 mov [lm_size],rax
 mov eax,1
 ret
.bad: xor eax,eax
 ret

; Exact corresponding-line three-way merge. Insert/delete shape changes remain
; conflicts; independent replacements are copied into the indexed output slot.
; rdi=base entry, rsi=ours, rdx=theirs, rcx=slot. eax=1 and rdx=size on success.
try_line_merge:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 mov rax,rcx
 shl rax,12
 lea r15,[merged_data+rax]
 mov [lm_out],r15
 mov qword [lm_size],0
 mov rdi,r12
 call entry_blob
 test rax,rax
 jz .fail
 lea rcx,[rax+UV_DATA]
 mov [lm_bp],rcx
 mov rcx,[r12+VR_SIZE]
 mov [lm_br],rcx
 mov rdi,r13
 call entry_blob
 test rax,rax
 jz .fail
 lea rcx,[rax+UV_DATA]
 mov [lm_op],rcx
 mov rcx,[r13+VR_SIZE]
 mov [lm_or],rcx
 mov rdi,r14
 call entry_blob
 test rax,rax
 jz .fail
 lea rcx,[rax+UV_DATA]
 mov [lm_tp],rcx
 mov rcx,[r14+VR_SIZE]
 mov [lm_tr],rcx
 xor ebx,ebx
.line:
 mov rax,[lm_br]
 or rax,[lm_or]
 or rax,[lm_tr]
 jz .success
 cmp qword [lm_br],0
 je .fail
 cmp qword [lm_or],0
 je .fail
 cmp qword [lm_tr],0
 je .fail
 inc ebx
 cmp ebx,256
 ja .fail
 mov rdi,[lm_bp]
 mov rsi,[lm_br]
 call line_length
 mov [lm_bl],rax
 mov rdi,[lm_op]
 mov rsi,[lm_or]
 call line_length
 mov [lm_ol],rax
 mov rdi,[lm_tp]
 mov rsi,[lm_tr]
 call line_length
 mov [lm_tl],rax
 ; ours == theirs
 mov rdi,[lm_op]
 mov rsi,[lm_ol]
 mov rdx,[lm_tp]
 mov rcx,[lm_tl]
 call span_equal
 test eax,eax
 jnz .take_ours
 ; base == ours -> theirs
 mov rdi,[lm_bp]
 mov rsi,[lm_bl]
 mov rdx,[lm_op]
 mov rcx,[lm_ol]
 call span_equal
 test eax,eax
 jnz .take_theirs
 ; base == theirs -> ours
 mov rdi,[lm_bp]
 mov rsi,[lm_bl]
 mov rdx,[lm_tp]
 mov rcx,[lm_tl]
 call span_equal
 test eax,eax
 jz .fail
.take_ours:
 mov rsi,[lm_op]
 mov rcx,[lm_ol]
 jmp .copy
.take_theirs:
 mov rsi,[lm_tp]
 mov rcx,[lm_tl]
.copy:
 mov rax,[lm_size]
 add rax,rcx
 cmp rax,4096
 ja .fail
 mov rdi,[lm_out]
 add rdi,[lm_size]
 rep movsb
 mov [lm_size],rax
 mov rax,[lm_bl]
 add [lm_bp],rax
 sub [lm_br],rax
 mov rax,[lm_ol]
 add [lm_op],rax
 sub [lm_or],rax
 mov rax,[lm_tl]
 add [lm_tp],rax
 sub [lm_tr],rax
 jmp .line
.success:
 mov rdx,[lm_size]
 mov eax,1
 jmp .done
.fail:
 xor eax,eax
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

line_length:
 xor eax,eax
.loop:
 cmp rax,rsi
 jae .done
 inc rax
 cmp byte [rdi+rax-1],10
 jne .loop
.done: ret

; rdi/esi span A, rdx/rcx span B.
span_equal:
 cmp rsi,rcx
 jne .no
 xchg rsi,rdx
 repe cmpsb
 sete al
 movzx eax,al
 ret
.no: xor eax,eax
 ret

entries_equal:
 test rdi,rdi
 jnz .left
 test rsi,rsi
 setz al
 movzx eax,al
 ret
.left:
 test rsi,rsi
 jz .no
 mov r8,rdi
 mov r9,rsi
 mov rcx,[r8+VR_SIZE]
 cmp rcx,[r9+VR_SIZE]
 jne .no
 sub rsp,24
 mov [rsp],r9
 mov [rsp+8],rcx
 mov rdi,r8
 call entry_blob
 mov [rsp+16],rax
 mov rdi,[rsp]
 call entry_blob
 mov r10,[rsp+16]
 mov rcx,[rsp+8]
 add rsp,24
 test r10,r10
 jz .no
 test rax,rax
 jz .no
 lea rsi,[r10+UV_DATA]
 lea rdi,[rax+UV_DATA]
 repe cmpsb
 sete al
 movzx eax,al
 ret
.no: xor eax,eax
 ret
node_equals_entry:
 mov r8,rdi
 mov r9,rsi
 mov rcx,[r8+UV_SIZE]
 cmp rcx,[r9+VR_SIZE]
 jne .no
 sub rsp,24
 mov [rsp],r8
 mov [rsp+8],rcx
 mov rdi,r9
 call entry_blob
 mov rcx,[rsp+8]
 mov r8,[rsp]
 add rsp,24
 test rax,rax
 jz .no
 lea rsi,[r8+UV_DATA]
 lea rdi,[rax+UV_DATA]
 repe cmpsb
 sete al
 movzx eax,al
 ret
.no: xor eax,eax
 ret
entry_blob:
 push rbp
 mov rbp,rsp
 and rsp,-16
 mov rdi,[rdi+VR_BLOB]
 mov sil,'b'
 call vcs_object_name
 lea rdi,[vcs_object_path]
 call uxv_find
 mov rsp,rbp
 pop rbp
 ret

new_metadata:
 push r12
 push r13
 push r14
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 call uxv_free
 test rax,rax
 jz .done
 mov rbx,rax
 mov rdi,rbx
 call clear_node
 mov rdi,rbx
 mov rsi,r12
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov [rbx+UV_SIZE],r14
 lea rdi,[rbx+UV_DATA]
 mov rsi,r13
 mov ecx,8
 rep movsb
 mov rax,rbx
.done:
 pop r14
 pop r13
 pop r12
 ret
copy_path:
 xchg rdi,rsi
 mov ecx,240
 rep movsb
 ret
relative_path:
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 lea rsi,[vcs_repo_root]
 repe cmpsb
 jne .no
 cmp byte [rdi],'/'
 jne .no
 inc rdi
 jmp .yes
.root:
 cmp byte [rdi],'/'
 jne .no
 inc rdi
.yes: mov rax,rdi
 ret
.no: xor eax,eax
 ret
working_relative:
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 je .root
 lea rsi,[vcs_repo_root]
 repe cmpsb
 jne .no
 cmp byte [rdi],'/'
 jne .no
 inc rdi
 jmp .check
.root:
 cmp byte [rdi],'/'
 jne .no
 inc rdi
.check:
 cmp dword [rdi],0x7363762e
 jne .yes
 cmp byte [rdi+4],0
 je .no
 cmp byte [rdi+4],'/'
 je .no
.yes: mov rax,rdi
 ret
.no: xor eax,eax
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
clear_node:
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret
clear_named:
 call uxv_find
 test rax,rax
 jz .done
 mov rdi,rax
 call clear_node
.done: ret
print_string:
 xor esi,esi
.length:
 cmp byte [rdi+rsi],0
 je emit
 inc rsi
 jmp .length
print_newline:
 lea rdi,[newline]
 mov esi,1
emit:
 jmp [merge_writer]
section .note.GNU-stack noalloc noexec nowrite progbits
