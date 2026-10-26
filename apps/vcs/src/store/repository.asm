; UXFS v2 repository initialization. Serialized with the owning volume/console.
%include "include/vcs.inc"
%include "include/repository.inc"
%include "storage/uxfs/volume.inc"
bits 64
default rel
extern uxv_ready,uxv_nodes,uxv_normalize,uxv_find,uxv_commit
section .bss
repo_path: resb 240
format_path: resb 240
section .rodata
suffix: db '/.vcs',0
format_suffix: db '/format',0
format_bytes: db 'UVCSREP1'
 dq VR_REPO_VERSION,0,0           ; version, last allocated ID, unborn HEAD
section .text
global vcs_repo_init
; rdi=existing directory path; rax=VCS status, rdx=1 already initialized / 0 new.
; No writes before validation/capacity checks. Publish both nodes in one commit.
vcs_repo_init:
 push rbx
 push r12
 push r13
 test rdi,rdi
 jz .usage
 cmp qword [uxv_ready],1
 jne .io
 mov rbx,rdi
 lea rdi,[repo_path]
 xor eax,eax
 mov ecx,480
 rep stosb
 mov rdi,rbx
 lea rsi,[repo_path]
 call uxv_normalize
 test rax,rax
 js .usage
 lea rdi,[repo_path]
 call uxv_find
 test rax,rax
 jz .missing
 cmp qword [rax+UV_TYPE],2
 jne .usage
 lea rdi,[repo_path]
 xor ecx,ecx
.length:
 cmp byte [rdi+rcx],0
 je .length_done
 inc ecx
 jmp .length
.length_done:
 cmp ecx,1
 jne .bound
 xor ecx,ecx                      ; root '/' -> '/.vcs'
.bound:
 cmp ecx,227                      ; '/.vcs/format' + NUL must fit 240
 ja .usage
 add rdi,rcx
 lea rsi,[suffix]
 mov ecx,6
 rep movsb
 lea rsi,[repo_path]
 lea rdi,[format_path]
.copy_path:
 lodsb
 stosb
 test al,al
 jnz .copy_path
 dec rdi
 lea rsi,[format_suffix]
 mov ecx,8
 rep movsb
 lea rdi,[repo_path]
 call uxv_find
 test rax,rax
 jz .allocate
 cmp qword [rax+UV_TYPE],2
 jne .conflict
 lea rdi,[format_path]
 call uxv_find
 test rax,rax
 jz .conflict
 cmp qword [rax+UV_TYPE],1
 jne .conflict
 cmp qword [rax+UV_SIZE],32
 jne .conflict
 lea rdi,[rax+UV_DATA]
 lea rsi,[format_bytes]
 mov ecx,16
 repe cmpsb
 jne .conflict
 mov rdx,[rax+UV_DATA+16]
 mov rcx,[rax+UV_DATA+24]
 test rdx,rdx
 jnz .known_last
 mov rdx,rcx
.known_last:
 cmp rcx,rdx
 ja .conflict
 cmp rdx,VR_MAX_ID
 ja .conflict
 xor eax,eax
 mov edx,1
 jmp .done
.allocate:
 ; Reserve two distinct free slots without modifying either until both exist.
 xor r12d,r12d
 xor r13d,r13d
 lea rbx,[uxv_nodes+UV_NODE]
.scan:
 cmp qword [rbx+UV_TYPE],0
 jne .next
 test r12,r12
 jnz .second
 mov r12,rbx
 jmp .next
.second:
 mov r13,rbx
 jmp .create
.next:
 add rbx,UV_NODE
 lea rax,[uxv_nodes+UV_BYTES]
 cmp rbx,rax
 jb .scan
 mov eax,VCS_ERR_NO_MEM
 jmp .failure
.create:
 mov rdi,r12
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 mov rdi,r13
 mov ecx,UV_NODE/8
 rep stosq
 mov rdi,r12
 lea rsi,[repo_path]
 mov ecx,240
 rep movsb
 mov qword [r12+UV_TYPE],2
 mov rdi,r13
 lea rsi,[format_path]
 mov ecx,240
 rep movsb
 mov qword [r13+UV_TYPE],1
 mov qword [r13+UV_SIZE],32
 lea rdi,[r13+UV_DATA]
 lea rsi,[format_bytes]
 mov ecx,32
 rep movsb
 call uxv_commit
 test rax,rax
 js .io
 xor eax,eax
 jmp .failure
.usage: mov eax,VCS_ERR_USAGE
 jmp .failure
.missing: mov eax,VCS_ERR_NOT_FOUND
 jmp .failure
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .failure
.io: mov eax,VCS_ERR_IO
.failure: xor edx,edx
.done:
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
