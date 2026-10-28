; Persistent bounded first-parent binary search over repository history.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "lib/storage/uxfs/volume.inc"
bits 64
default rel

extern uxv_ready,uxv_find,uxv_free,uxv_commit
extern vcs_repo_discover,vcs_load_manifest,vcs_checkout,vcs_worktree_clean
extern vcs_repo_root,vcs_repo_root_size,vcs_repo_head

%define BISECT_SIZE 80
%define BS_ORIGINAL 8
%define BS_GOOD 16
%define BS_BAD 24
%define BS_CURRENT 32
%define BS_ACTIVE 40

section .bss
bisect_writer: resq 1
bisect_node: resq 1
bisect_path: resb 240
operation_path: resb 240
chain: resq UV_NODES
chain_count: resq 1
number: resb 16

section .rodata
bisect_magic: db 'UVCSBIS1'
bisect_suffix: db '/.vcs/bisect',0
active_suffix: db '/.vcs/active',0
index_suffix: db '/.vcs/index',0
merge_suffix: db '/.vcs/merge',0
rebase_suffix: db '/.vcs/rebase',0
pick_suffix: db '/.vcs/pick',0
conflict_suffix: db '/.vcs/conflicts',0
testing_text: db 'Bisect testing '
testing_text_len equ $-testing_text
first_bad_text: db 'First bad commit '
first_bad_text_len equ $-first_bad_text
good_text: db 'good '
good_text_len equ $-good_text
bad_text: db 'bad '
bad_text_len equ $-bad_text
current_text: db 'current '
current_text_len equ $-current_text
reset_text: db 'Bisect reset',10
reset_text_len equ $-reset_text
newline: db 10
hex: db '0123456789abcdef'

section .text
global vcs_bisect
; RDI=op: 0 start, 1 mark good, 2 mark bad, 3 status, 4 reset.
; RSI=start good, RDX=start bad, RCX=writer.
vcs_bisect:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 cmp rdi,4
 ja .usage
 test rcx,rcx
 jz .usage
 cmp qword [uxv_ready],1
 jne .io
 mov rbp,rdi
 mov r12,rsi
 mov r13,rdx
 mov [bisect_writer],rcx
 call vcs_repo_discover
 test eax,eax
 jnz .done
 call make_bisect_path
 lea rdi,[bisect_path]
 call uxv_find
 mov [bisect_node],rax
 test rbp,rbp
 jz .start
 test rax,rax
 jz .missing
 call validate_state
 test eax,eax
 jnz .done
 cmp rbp,1
 je .mark_good
 cmp rbp,2
 je .mark_bad
 cmp rbp,3
 je .status
 jmp .reset

.start:
 cmp qword [bisect_node],0
 jne .conflict
 test r12,r12
 jz .usage
 test r13,r13
 jz .usage
 cmp r12,r13
 je .usage
 call operations_clear
 test eax,eax
 jnz .conflict
 mov rdi,[vcs_repo_head]
 test rdi,rdi
 jz .conflict
 call vcs_worktree_clean
 test eax,eax
 jnz .done
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rdi,r13
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov rdi,r12
 mov rsi,r13
 call build_chain
 test eax,eax
 jnz .done
 call uxv_free
 test rax,rax
 jz .capacity
 mov [bisect_node],rax
 mov rbx,rax
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 mov rdi,rbx
 lea rsi,[bisect_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov qword [rbx+UV_SIZE],BISECT_SIZE
 mov rax,[bisect_magic]
 mov [rbx+UV_DATA],rax
 mov rax,[vcs_repo_head]
 mov [rbx+UV_DATA+BS_ORIGINAL],rax
 mov [rbx+UV_DATA+BS_GOOD],r12
 mov [rbx+UV_DATA+BS_BAD],r13
 call capture_active
 test eax,eax
 jnz .done
 call schedule
 jmp .done

.mark_good:
 call require_current
 test eax,eax
 jnz .done
 mov rbx,[bisect_node]
 mov rax,[rbx+UV_DATA+BS_CURRENT]
 cmp rax,[rbx+UV_DATA+BS_BAD]
 je .conflict
 mov [rbx+UV_DATA+BS_GOOD],rax
 call schedule
 jmp .done

.mark_bad:
 call require_current
 test eax,eax
 jnz .done
 mov rbx,[bisect_node]
 mov rax,[rbx+UV_DATA+BS_CURRENT]
 cmp rax,[rbx+UV_DATA+BS_GOOD]
 je .conflict
 mov [rbx+UV_DATA+BS_BAD],rax
 call schedule
 jmp .done

.status:
 mov rbx,[bisect_node]
 lea rdi,[good_text]
 mov esi,good_text_len
 call emit
 mov rdi,[rbx+UV_DATA+BS_GOOD]
 call emit_line_id
 lea rdi,[bad_text]
 mov esi,bad_text_len
 call emit
 mov rdi,[rbx+UV_DATA+BS_BAD]
 call emit_line_id
 lea rdi,[current_text]
 mov esi,current_text_len
 call emit
 mov rdi,[rbx+UV_DATA+BS_CURRENT]
 call emit_line_id
 xor eax,eax
 jmp .done

.reset:
 mov rbx,[bisect_node]
 mov rdi,[rbx+UV_DATA+BS_ORIGINAL]
 lea rsi,[silent]
 lea rdx,[rbx+UV_DATA+BS_ACTIVE]
 cmp byte [rdx],0
 jne .reset_checkout
 xor edx,edx
.reset_checkout:
 call vcs_checkout
 test eax,eax
 jnz .done
 mov rbx,[bisect_node]
 mov rdi,rbx
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 call uxv_commit
 test eax,eax
 jnz .io
 lea rdi,[reset_text]
 mov esi,reset_text_len
 call emit
 xor eax,eax
 jmp .done

.usage: mov eax,VCS_ERR_USAGE
 jmp .done
.missing: mov eax,VCS_ERR_NOT_FOUND
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

; Build bad-to-good-exclusive first-parent chain. RDI=good, RSI=bad.
build_chain:
 push rbx
 push r12
 push r13
 mov r12,rdi
 mov r13,rsi
 mov qword [chain_count],0
.walk:
 cmp r13,r12
 je .found
 mov rax,[chain_count]
 cmp rax,UV_NODES
 jae .bad
 lea rdx,[chain]
 mov [rdx+rax*8],r13
 inc qword [chain_count]
 mov rdi,r13
 call vcs_load_manifest
 test rax,rax
 jz .bad
 mov r13,[rax+16]
 test r13,r13
 jnz .walk
.bad: mov eax,VCS_ERR_CONFLICT
 jmp .done
.found:
 cmp qword [chain_count],0
 je .bad
 xor eax,eax
.done:
 pop r13
 pop r12
 pop rbx
 ret

; Persist the next midpoint before checking it out detached.
schedule:
 push rbx
 push r14
 sub rsp,8
 mov rbx,[bisect_node]
 mov rdi,[rbx+UV_DATA+BS_GOOD]
 mov rsi,[rbx+UV_DATA+BS_BAD]
 call build_chain
 test eax,eax
 jnz .done
 mov rax,[chain_count]
 cmp rax,1
 je .first_bad
 shr rax,1
 lea rdx,[chain]
 mov r14,[rdx+rax*8]
 mov [rbx+UV_DATA+BS_CURRENT],r14
 call uxv_commit
 test eax,eax
 jnz .io
 mov rdi,r14
 lea rsi,[silent]
 xor edx,edx
 call vcs_checkout
 test eax,eax
 jnz .done
 lea rdi,[testing_text]
 mov esi,testing_text_len
 call emit
 mov rdi,r14
 call emit_line_id
 xor eax,eax
 jmp .done
.first_bad:
 mov r14,[rbx+UV_DATA+BS_BAD]
 mov [rbx+UV_DATA+BS_CURRENT],r14
 call uxv_commit
 test eax,eax
 jnz .io
 cmp r14,[vcs_repo_head]
 je .report_bad
 mov rdi,r14
 lea rsi,[silent]
 xor edx,edx
 call vcs_checkout
 test eax,eax
 jnz .done
.report_bad:
 lea rdi,[first_bad_text]
 mov esi,first_bad_text_len
 call emit
 mov rdi,r14
 call emit_line_id
 xor eax,eax
 jmp .done
.io: mov eax,VCS_ERR_IO
.done:
 add rsp,8
 pop r14
 pop rbx
 ret

require_current:
 push rbx
 mov rbx,[bisect_node]
 mov rax,[rbx+UV_DATA+BS_CURRENT]
 cmp rax,[vcs_repo_head]
 jne .bad
 mov rdi,rax
 call vcs_worktree_clean
 pop rbx
 ret
.bad:
 mov eax,VCS_ERR_CONFLICT
 pop rbx
 ret

validate_state:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,[bisect_node]
 cmp qword [rbx+UV_TYPE],1
 jne .bad
 cmp qword [rbx+UV_SIZE],BISECT_SIZE
 jne .bad
 mov rax,[bisect_magic]
 cmp [rbx+UV_DATA],rax
 jne .bad
 mov r12,[rbx+UV_DATA+BS_ORIGINAL]
 mov r13,[rbx+UV_DATA+BS_GOOD]
 mov r14,[rbx+UV_DATA+BS_BAD]
 mov r15,[rbx+UV_DATA+BS_CURRENT]
 test r12,r12
 jz .bad
 test r13,r13
 jz .bad
 test r14,r14
 jz .bad
 test r15,r15
 jz .bad
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .bad
 mov rdi,r15
 call vcs_load_manifest
 test rax,rax
 jz .bad
 mov rdi,r13
 mov rsi,r14
 call build_chain
 test eax,eax
 jnz .bad
 xor ecx,ecx
.current_scan:
 cmp rcx,[chain_count]
 jae .bad
 lea rax,[chain]
 cmp [rax+rcx*8],r15
 je .valid
 inc rcx
 jmp .current_scan
.valid:
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

operations_clear:
 sub rsp,8
 lea rsi,[index_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[merge_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[rebase_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[pick_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 lea rsi,[conflict_suffix]
 call metadata_exists
 test eax,eax
 jnz .busy
 xor eax,eax
 jmp .done
.busy: mov eax,1
.done:
 add rsp,8
 ret

metadata_exists:
 sub rsp,8
 lea rdi,[operation_path]
 call make_path
 lea rdi,[operation_path]
 call uxv_find
 test rax,rax
 setnz al
 movzx eax,al
 add rsp,8
 ret

capture_active:
 push rbx
 mov rbx,[bisect_node]
 lea rdi,[rbx+UV_DATA+BS_ACTIVE]
 xor eax,eax
 mov ecx,5
 rep stosq
 lea rsi,[active_suffix]
 lea rdi,[operation_path]
 call make_path
 lea rdi,[operation_path]
 call uxv_find
 test rax,rax
 jz .none
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 cmp rcx,2
 jb .bad
 cmp rcx,33
 ja .bad
 cmp byte [rax+UV_DATA+rcx-1],0
 jne .bad
 lea rsi,[rax+UV_DATA]
 mov rbx,[bisect_node]
 lea rdi,[rbx+UV_DATA+BS_ACTIVE]
 rep movsb
.none: xor eax,eax
 jmp .done
.bad: mov eax,VCS_ERR_CORRUPT
.done:
 pop rbx
 ret

make_bisect_path:
 lea rdi,[bisect_path]
 lea rsi,[bisect_suffix]
 jmp make_path

make_path:
 push rbx
 mov rbx,rsi
 push rdi
 xor eax,eax
 mov ecx,30
 rep stosq
 pop rdi
 lea rsi,[vcs_repo_root]
 mov rcx,[vcs_repo_root_size]
 cmp rcx,1
 jne .copy_root
 xor ecx,ecx
.copy_root:
 rep movsb
 mov rsi,rbx
.suffix:
 lodsb
 stosb
 test al,al
 jnz .suffix
 pop rbx
 ret

emit_line_id:
 sub rsp,8
 call emit_id
 lea rdi,[newline]
 mov esi,1
 call emit
 add rsp,8
 ret

emit_id:
 mov rax,rdi
 lea rdi,[number]
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
 lea rdi,[number]
 mov esi,16
 jmp emit

silent:
 ret

emit:
 jmp [bisect_writer]

section .note.GNU-stack noalloc noexec nowrite progbits
