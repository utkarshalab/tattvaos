; First-parent transfer planning by integrity digest.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "include/bundle.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_find
extern vcs_repo_discover,vcs_load_manifest,vcs_object_name,vcs_ref
extern vcs_repo_head,vcs_repo_last,vcs_object_path

section .bss
global vcs_sync_plan_head_digest
vcs_sync_plan_head_digest: resb 32
plan_ids: resq 64
plan_count: resq 1

section .text
global vcs_sync_plan

; RDI=have digest32 (zero pointer or all-zero means no history), RSI=ref or zero,
; RDX=output IDs, RCX=capacity (1..64).
; RAX=status, RDX=count, R8=target ID, R9=head digest pointer.
vcs_sync_plan:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 test r13,r13
 jz .usage
 test r14,r14
 jz .usage
 cmp r14,64
 ja .usage
 cmp qword [uxv_ready],1
 jne .io
 call vcs_repo_discover
 test eax,eax
 jnz .done
 mov r15,[vcs_repo_head]
 test r12,r12
 jz .target_ready
 mov edi,5
 mov rsi,r12
 xor edx,edx
 lea rcx,[discard]
 call vcs_ref
 test eax,eax
 jnz .done
 mov r15,rdx
.target_ready:
 lea rdi,[vcs_sync_plan_head_digest]
 xor eax,eax
 mov ecx,4
 rep stosq
 test r15,r15
 jz .empty_target
 mov rdi,r15
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rdi,r15
 mov sil,'h'
 call find_object
 test rax,rax
 jz .corrupt
 cmp qword [rax+UV_SIZE],32
 jne .corrupt
 lea rsi,[rax+UV_DATA]
 lea rdi,[vcs_sync_plan_head_digest]
 mov ecx,32
 rep movsb
 ; Imported tips advertise their signed source digest, not the remapped local
 ; digest, so the source repository can recognize its own ancestry.
 mov rdi,r15
 mov sil,'m'
 call vcs_object_name
 test eax,eax
 jnz .corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .head_digest_ready
 cmp qword [rax+UV_TYPE],1
 jne .corrupt
 cmp qword [rax+UV_SIZE],48
 jne .corrupt
 mov rdx,VB_MAP_MAGIC
 cmp [rax+UV_DATA],rdx
 jne .corrupt
 lea rsi,[rax+UV_DATA+16]
 lea rdi,[vcs_sync_plan_head_digest]
 mov ecx,32
 rep movsb
.head_digest_ready:
 ; A null or all-zero have digest requests the complete first-parent chain.
 xor ebx,ebx
 test rbp,rbp
 jz .walk
 mov rax,[rbp]
 or rax,[rbp+8]
 or rax,[rbp+16]
 or rax,[rbp+24]
 jz .walk
 mov ebx,1
.walk:
 mov r12,r15
 mov qword [plan_count],0
.walk_loop:
 test r12,r12
 jz .walk_root
 test ebx,ebx
 jz .append
 mov rdi,r12
 mov rsi,rbp
 call digest_matches
 cmp eax,1
 je .reverse
 cmp eax,-1
 je .corrupt
.append:
 mov rcx,[plan_count]
 cmp rcx,r14
 jae .capacity
 lea rax,[plan_ids]
 mov [rax+rcx*8],r12
 inc qword [plan_count]
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r12,[rax+16]
 jmp .walk_loop
.walk_root:
 test ebx,ebx
 jnz .missing
.reverse:
 xor ecx,ecx
.reverse_loop:
 cmp rcx,[plan_count]
 jae .success
 mov rax,[plan_count]
 dec rax
 sub rax,rcx
 lea rdx,[plan_ids]
 mov rdx,[rdx+rax*8]
 mov [r13+rcx*8],rdx
 inc rcx
 jmp .reverse_loop
.success:
 mov rdx,[plan_count]
 mov r8,r15
 lea r9,[vcs_sync_plan_head_digest]
 xor eax,eax
 jmp .done
.empty_target:
 ; A nonzero have digest cannot be an ancestor of an unborn target.
 test rbp,rbp
 jz .empty_ok
 mov rax,[rbp]
 or rax,[rbp+8]
 or rax,[rbp+16]
 or rax,[rbp+24]
 jnz .missing
.empty_ok:
 xor edx,edx
 xor r8d,r8d
 lea r9,[vcs_sync_plan_head_digest]
 xor eax,eax
 jmp .done
.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
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

; RDI=local commit ID, RSI=digest. EAX=1 match, 0 no match, -1 corrupt.
digest_matches:
 push rbx
 push r12
 mov rbx,rdi
 mov r12,rsi
 mov sil,'h'
 call find_object
 test rax,rax
 jz .match_corrupt
 cmp qword [rax+UV_SIZE],32
 jne .match_corrupt
 lea rdi,[rax+UV_DATA]
 mov rsi,r12
 mov ecx,32
 repe cmpsb
 je .match_yes
 mov rdi,rbx
 mov sil,'m'
 call vcs_object_name
 test eax,eax
 jnz .match_corrupt
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .match_no
 cmp qword [rax+UV_TYPE],1
 jne .match_corrupt
 cmp qword [rax+UV_SIZE],48
 jne .match_corrupt
 mov rdx,VB_MAP_MAGIC
 cmp [rax+UV_DATA],rdx
 jne .match_corrupt
 lea rdi,[rax+UV_DATA+16]
 mov rsi,r12
 mov ecx,32
 repe cmpsb
 je .match_yes
.match_no:
 xor eax,eax
 jmp .match_done
.match_yes:
 mov eax,1
 jmp .match_done
.match_corrupt:
 mov eax,-1
.match_done:
 pop r12
 pop rbx
 ret

find_object:
 call vcs_object_name
 test eax,eax
 jnz .find_missing
 lea rdi,[vcs_object_path]
 call uxv_find
 test rax,rax
 jz .find_missing
 cmp qword [rax+UV_TYPE],1
 jne .find_missing
 ret
.find_missing:
 xor eax,eax
 ret

discard:
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
