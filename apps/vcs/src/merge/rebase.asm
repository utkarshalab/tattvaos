; Durable first-parent rebase using the shared three-way replay engine.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_find,uxv_free,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_merge_base,vcs_worktree_clean
extern vcs_threeway_replay,vcs_history_replay,vcs_history_replay_signed,vcs_checkout
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head
section .bss
rebase_writer: resq 1
rebase_seed: resq 1
rebase_node: resq 1
rebase_path: resb 240
active_path: resb 240
ref_path: resb 240
conflict_path: resb 240
index_path: resb 240
pick_path: resb 240
state: resb 592
chain: resq UV_NODES
section .rodata
rebase_suffix: db '/.vcs/rebase',0
active_suffix: db '/.vcs/active',0
ref_suffix: db '/.vcs/rh.',0
conflict_suffix: db '/.vcs/conflicts',0
index_suffix: db '/.vcs/index',0
pick_suffix: db '/.vcs/pick',0
magic: db 'UVCSRBS1'
paused: db 'Rebase paused; resolve listed paths, then run vcs rebase --continue',10
paused_len equ $-paused
finished: db 'Rebase complete',10
finished_len equ $-finished
aborted: db 'Rebase aborted',10
aborted_len equ $-aborted
newline: db 10
section .text
global vcs_rebase
; op 0 start(target ID), op 1 continue, op 2 abort. rdx=writer, rcx=seed32.
vcs_rebase:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,2
 ja .usage
 test rdx,rdx
 jz .usage
 mov rbp,rdi
 mov r12,rsi
 mov [rebase_writer],rdx
 mov [rebase_seed],rcx
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[rebase_path]
 call uxv_find
 mov [rebase_node],rax
 test rbp,rbp
 jz .start
 cmp rbp,2
 je .abort
 jmp .continue
.start:
 test rax,rax
 jnz .conflict
 test r12,r12
 jz .usage
 cmp qword [vcs_repo_head],0
 je .usage
 cmp r12,[vcs_repo_head]
 je .finish_message
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[index_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[pick_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 mov rdi,[vcs_repo_head]
 call vcs_worktree_clean
 test eax,eax
 jnz .done
 mov rdi,[vcs_repo_head]
 mov rsi,r12
 call vcs_merge_base
 test rax,rax
 jz .conflict
 mov r13,rax                       ; fork point
 cmp r13,r12
 je .finish_message                ; already based on the requested target
 ; Gather source first parents newest-first until the fork point.
 mov r14,[vcs_repo_head]
 xor r15d,r15d
.gather:
 cmp r14,r13
 je .gathered
 cmp r15,UV_NODES
 jae .corrupt
 lea rax,[chain]
 mov [rax+r15*8],r14
 inc r15
 mov rdi,r14
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r14,[rax+16]
 test r14,r14
 jnz .gather
 jmp .corrupt
.gathered:
 ; Capture the currently attached branch name, if any.
 lea rdi,[state]
 xor eax,eax
 mov ecx,74
 rep stosq
 lea rdi,[state]
 lea rsi,[magic]
 mov ecx,8
 rep movsb
 mov rax,[vcs_repo_head]
 mov [state+8],rax
 mov [state+16],r12
 mov [state+24],r15
 mov qword [state+32],0
 lea rdi,[active_path]
 call uxv_find
 test rax,rax
 jz .reverse
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 mov rcx,[rax+UV_SIZE]
 test rcx,rcx
 jz .corrupt
 cmp rcx,33
 ja .corrupt
 lea rsi,[rax+UV_DATA]
 lea rdi,[state+40]
 rep movsb
.reverse:
 ; Persist replay IDs oldest-first.
 xor r14d,r14d
.reverse_loop:
 cmp r14,r15
 jae .write_state
 mov rax,r15
 dec rax
 sub rax,r14
 lea rdx,[chain]
 mov rax,[rdx+rax*8]
 mov [state+80+r14*8],rax
 inc r14
 jmp .reverse_loop
.write_state:
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
 mov rdi,rbx
 call clear_node
 mov rdi,rbx
 lea rsi,[rebase_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov rcx,r15
 shl rcx,3
 add rcx,80
 mov [rbx+UV_SIZE],rcx
 lea rsi,[state]
 lea rdi,[rbx+UV_DATA]
 rep movsb
 call uxv_commit
 test rax,rax
 js .io
 ; Checkout target detached. The saved state retains branch ownership.
 mov rdi,r12
 mov rsi,[rebase_writer]
 xor edx,edx
 call vcs_checkout
 test eax,eax
 jnz .done
 call reload_state
 test eax,eax
 jnz .done
 jmp .advance
.continue:
 test rax,rax
 jz .usage
 call load_state
 test eax,eax
 jnz .done
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jz .advance
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],16
 jne .conflict
 cmp qword [rax+UV_DATA+8],0
 jne .conflict
 ; The paused patch is resolved: commit it with its original message.
 call commit_current
 test eax,eax
 jnz .done
 call increment_state
 test eax,eax
 jnz .done
.advance:
 mov rax,[state+32]
 cmp rax,[state+24]
 jae .finalize
 mov r14,[state+80+rax*8]
 mov rdi,r14
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r13,[rax+16]
 mov rdi,r13
 mov rsi,[vcs_repo_head]
 mov rdx,r14
 call vcs_threeway_replay
 test eax,eax
 jnz .done
 test rdx,rdx
 jnz .pause
 call commit_current
 test eax,eax
 jnz .done
 call increment_state
 test eax,eax
 jnz .done
 jmp .advance
.abort:
 test rax,rax
 jz .usage
 call load_state
 test eax,eax
 jnz .done
 mov rdi,[state+8]
 mov rsi,[rebase_writer]
 xor edx,edx
 cmp byte [state+40],0
 je .abort_checkout
 lea rdx,[state+40]
.abort_checkout:
 call vcs_checkout
 test eax,eax
 jnz .done
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[rebase_path]
 call clear_named
 lea rdi,[conflict_path]
 call clear_named
 lea rdi,[index_path]
 call clear_named
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[aborted]
 mov esi,aborted_len
 call emit
 jmp .ok
.pause:
 lea rdi,[paused]
 mov esi,paused_len
 call emit
 jmp .ok
.finalize:
 ; Restore the saved branch attachment and move that branch to rewritten HEAD.
 cmp byte [state+40],0
 je .clear_state
 call make_ref_path
 lea rdi,[ref_path]
 call uxv_find
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],8
 jne .corrupt
 mov rdx,[vcs_repo_head]
 mov [rax+UV_DATA],rdx
 lea rdi,[active_path]
 call uxv_find
 test rax,rax
 jnz .active_have
 call uxv_free
 test rax,rax
 jz .capacity
.active_have:
 mov rbx,rax
 mov rdi,rbx
 call clear_node
 mov rdi,rbx
 lea rsi,[active_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 xor ecx,ecx
.name_len:
 cmp byte [state+40+rcx],0
 je .name_ready
 inc ecx
 jmp .name_len
.name_ready:
 inc ecx
 mov [rbx+UV_SIZE],rcx
 lea rsi,[state+40]
 lea rdi,[rbx+UV_DATA]
 rep movsb
.clear_state:
 mov rdi,[rebase_node]
 call clear_node
 call uxv_commit
 test rax,rax
 js .io
.finish_message:
 lea rdi,[finished]
 mov esi,finished_len
 call emit
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

commit_current:
 mov rax,[state+32]
 cmp rax,[state+24]
 jae .bad
 mov rdi,[state+80+rax*8]
 call vcs_load_manifest
 test rax,rax
 jz .bad
 lea rdi,[rax+VR_MESSAGE]
 cmp qword [rebase_seed],0
 jne .signed
 mov rsi,[rebase_writer]
 call vcs_history_replay
 ret
.signed:
 mov rsi,[rebase_seed]
 mov rdx,[rebase_writer]
 call vcs_history_replay_signed
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret
increment_state:
 inc qword [state+32]
 mov rbx,[rebase_node]
 mov rax,[state+32]
 mov [rbx+UV_DATA+32],rax
 call uxv_commit
 test rax,rax
 js .bad
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_IO
 ret
reload_state:
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[rebase_path]
 call uxv_find
 mov [rebase_node],rax
 test rax,rax
 jz .bad
 jmp load_state
.bad: mov eax,VCS_ERR_CORRUPT
.done: ret
load_state:
 mov rbx,[rebase_node]
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 mov rcx,[rbx+UV_SIZE]
 cmp rcx,80
 jb .bad
 cmp rcx,592
 ja .bad
 mov rdx,rcx
 sub rdx,80
 test rdx,7
 jnz .bad
 shr rdx,3
 cmp [rbx+UV_DATA+24],rdx
 jne .bad
 cmp qword [rbx+UV_DATA+32],rdx
 ja .bad
 mov rax,0x3153425253435655
 cmp [rbx+UV_DATA],rax
 jne .bad
 lea rsi,[rbx+UV_DATA]
 lea rdi,[state]
 rep movsb
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret
make_paths:
 lea rdi,[rebase_path]
 lea rsi,[rebase_suffix]
 mov edx,13
 call make_path
 lea rdi,[active_path]
 lea rsi,[active_suffix]
 mov edx,13
 call make_path
 lea rdi,[conflict_path]
 lea rsi,[conflict_suffix]
 mov edx,16
 call make_path
 lea rdi,[index_path]
 lea rsi,[index_suffix]
 mov edx,12
 call make_path
 lea rdi,[pick_path]
 lea rsi,[pick_suffix]
 mov edx,11
 jmp make_path
make_ref_path:
 lea rdi,[ref_path]
 lea rsi,[ref_suffix]
 mov edx,10
 call make_path
 lea rdi,[ref_path]
.end:
 cmp byte [rdi],0
 je .append
 inc rdi
 jmp .end
.append:
 lea rsi,[state+40]
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 ret
make_path:
 push rdi
 xor eax,eax
 mov ecx,30
 rep stosq
 pop rdi
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .root
 xor ecx,ecx
.root:
 push rsi
 lea rsi,[vcs_repo_root]
 rep movsb
 pop rsi
 mov ecx,edx
 rep movsb
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
emit:
 jmp [rebase_writer]
section .note.GNU-stack noalloc noexec nowrite progbits
