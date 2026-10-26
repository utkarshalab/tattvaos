; Durable single-commit cherry-pick and revert using the shared replay engine.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_find,uxv_free,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_threeway_replay,vcs_worktree_clean,vcs_checkout
extern vcs_history_replay,vcs_history_replay_signed
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head

section .bss
pick_writer: resq 1
pick_seed: resq 1
pick_path: resb 240
conflict_path: resb 240
index_path: resb 240
active_path: resb 240
merge_path: resb 240
rebase_path: resb 240
revert_message: resb 32

section .rodata
pick_suffix: db '/.vcs/pick',0
conflict_suffix: db '/.vcs/conflicts',0
index_suffix: db '/.vcs/index',0
active_suffix: db '/.vcs/active',0
merge_suffix: db '/.vcs/merge',0
rebase_suffix: db '/.vcs/rebase',0
pick_magic: db 'UVCSPCK1'
paused: db 'Operation paused; resolve paths, then run vcs cherry-pick|revert --continue',10
paused_len equ $-paused
finished: db 'Operation complete',10
finished_len equ $-finished
aborted: db 'Operation aborted',10
aborted_len equ $-aborted
revert_prefix: db 'Revert '
hex: db '0123456789abcdef'

section .text
global vcs_pick
; op 0 cherry-pick start, 1 revert start, 2 continue, 3 abort.
; rsi=source ID for start, rdx=writer, rcx=optional seed32.
vcs_pick:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 cmp rdi,3
 ja .usage
 test rdx,rdx
 jz .usage
 mov rbp,rdi
 mov r12,rsi
 mov [pick_writer],rdx
 mov [pick_seed],rcx
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[pick_path]
 call uxv_find
 mov rbx,rax
 cmp rbp,2
 je .continue
 cmp rbp,3
 je .abort
 test rbx,rbx
 jnz .conflict
 test r12,r12
 jz .usage
 cmp qword [vcs_repo_head],0
 je .usage
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[index_path]
 call uxv_find
 test rax,rax
 jnz .conflict
 lea rdi,[merge_path]
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
 mov r13,rax
 mov r14,[r13+16]
 mov rdi,[vcs_repo_head]
 call vcs_worktree_clean
 test eax,eax
 jnz .done
 call uxv_free
 test rax,rax
 jz .capacity
 mov rbx,rax
 mov rdi,rbx
 call clear_node
 mov rdi,rbx
 lea rsi,[pick_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],32
 mov rax,0x314b435053435655
 mov [rbx+UV_DATA],rax
 mov [rbx+UV_DATA+8],rbp
 mov [rbx+UV_DATA+16],r12
 mov rax,[vcs_repo_head]
 mov [rbx+UV_DATA+24],rax
 call uxv_commit
 test rax,rax
 js .io
 cmp rbp,0
 jne .start_revert
 mov rdi,r14
 mov rsi,[vcs_repo_head]
 mov rdx,r12
 jmp .replay
.start_revert:
 mov rdi,r12
 mov rsi,[vcs_repo_head]
 mov rdx,r14
.replay:
 call vcs_threeway_replay
 test eax,eax
 jnz .done
 test rdx,rdx
 jnz .pause
 jmp .commit

.continue:
 test rbx,rbx
 jz .usage
 call load_state
 test eax,eax
 jnz .done
 mov rax,[rbx+UV_DATA+24]
 cmp [vcs_repo_head],rax
 jne .finish_stale
 lea rdi,[conflict_path]
 call uxv_find
 test rax,rax
 jz .conflict
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],16
 jne .conflict
 cmp qword [rax+UV_DATA+8],0
 jne .conflict
.commit:
 mov rdi,[rbx+UV_DATA+16]
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 cmp qword [rbx+UV_DATA+8],0
 jne .revert_msg
 lea rdi,[rax+VR_MESSAGE]
 jmp .commit_message
.revert_msg:
 mov rdi,[rbx+UV_DATA+16]
 call make_revert_message
 lea rdi,[revert_message]
.commit_message:
 cmp qword [pick_seed],0
 jne .commit_signed
 mov rsi,[pick_writer]
 call vcs_history_replay
 jmp .committed
.commit_signed:
 mov rsi,[pick_seed]
 mov rdx,[pick_writer]
 call vcs_history_replay_signed
.committed:
 test eax,eax
 jnz .done
 call reload_pick
 test eax,eax
 jnz .done
 mov rdi,rbx
 call clear_node
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[finished]
 mov esi,finished_len
 call emit
 jmp .ok
.finish_stale:
 mov rdi,rbx
 call clear_node
 call uxv_commit
 test rax,rax
 js .io
 lea rdi,[finished]
 mov esi,finished_len
 call emit
 jmp .ok

.abort:
 test rbx,rbx
 jz .usage
 call load_state
 test eax,eax
 jnz .done
 lea rdi,[active_path]
 call uxv_find
 xor edx,edx
 test rax,rax
 jz .abort_checkout
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 lea rdx,[rax+UV_DATA]
.abort_checkout:
 mov rdi,[rbx+UV_DATA+24]
 mov rsi,[pick_writer]
 call vcs_checkout
 test eax,eax
 jnz .done
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[pick_path]
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

load_state:
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 cmp qword [rbx+UV_SIZE],32
 jne .bad
 mov rax,0x314b435053435655
 cmp [rbx+UV_DATA],rax
 jne .bad
 cmp qword [rbx+UV_DATA+8],1
 ja .bad
 xor eax,eax
 ret
.bad: mov eax,VCS_ERR_CORRUPT
 ret

reload_pick:
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_paths
 lea rdi,[pick_path]
 call uxv_find
 mov rbx,rax
 test rbx,rbx
 jz .bad
 jmp load_state
.bad: mov eax,VCS_ERR_CORRUPT
.done: ret

make_revert_message:
 mov rax,rdi
 lea rdi,[revert_message]
 lea rsi,[revert_prefix]
 mov ecx,7
 rep movsb
 mov ecx,16
 lea r8,[hex]
.digit:
 rol rax,4
 mov rdx,rax
 and edx,15
 mov dl,[r8+rdx]
 mov [rdi],dl
 inc rdi
 loop .digit
 mov byte [rdi],0
 ret

make_paths:
 lea rdi,[pick_path]
 lea rsi,[pick_suffix]
 mov edx,11
 call make_path
 lea rdi,[conflict_path]
 lea rsi,[conflict_suffix]
 mov edx,16
 call make_path
 lea rdi,[index_path]
 lea rsi,[index_suffix]
 mov edx,12
 call make_path
 lea rdi,[active_path]
 lea rsi,[active_suffix]
 mov edx,13
 call make_path
 lea rdi,[merge_path]
 lea rsi,[merge_suffix]
 mov edx,12
 call make_path
 lea rdi,[rebase_path]
 lea rsi,[rebase_suffix]
 mov edx,13
 jmp make_path

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

clear_named:
 call uxv_find
 test rax,rax
 jz .done
 mov rdi,rax
 call clear_node
.done: ret

clear_node:
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret

emit:
 jmp [pick_writer]

section .note.GNU-stack noalloc noexec nowrite progbits
