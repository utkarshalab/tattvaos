; Canonical bounded Git SHA-256 commit object encoder.
%include "include/vcs.inc"
%include "include/git_commit.inc"
bits 64
default rel

extern git_object_hash

section .rodata
commit_type: db 'commit'
tree_prefix: db 'tree '
tree_prefix_len equ $-tree_prefix
parent_prefix: db 'parent '
parent_prefix_len equ $-parent_prefix
identity: db 'author Tattva VCS <vcs@tattva.local> 0 +0000',10,'committer Tattva VCS <vcs@tattva.local> 0 +0000',10,10
identity_len equ $-identity
hex: db '0123456789abcdef'

section .text
global git_commit_encode

; RDI=git_commit_request. RAX=status, RDX=encoded body length.
git_commit_encode:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 test rbx,rbx
 jz .usage
 mov r12,[rbx+git_commit_request.tree]
 mov r13,[rbx+git_commit_request.parent]
 mov r14,[rbx+git_commit_request.message]
 mov r15,[rbx+git_commit_request.message_len]
 test r12,r12
 jz .usage
 test r14,r14
 jz .usage
 test r15,r15
 jz .usage
 cmp r15,GIT_COMMIT_MESSAGE_MAX
 ja .usage
 mov rax,tree_prefix_len+64+1+identity_len
 test r13,r13
 jz .size_ready
 add rax,parent_prefix_len+64+1
.size_ready:
 add rax,r15
 cmp [rbx+git_commit_request.capacity],rax
 jb .space
 mov rdi,[rbx+git_commit_request.output]
 test rdi,rdi
 jz .usage
 cmp qword [rbx+git_commit_request.hash],0
 je .usage
 lea rsi,[tree_prefix]
 mov ecx,tree_prefix_len
 rep movsb
 mov rsi,r12
 call append_hash
 mov byte [rdi],10
 inc rdi
 test r13,r13
 jz .identity
 lea rsi,[parent_prefix]
 mov ecx,parent_prefix_len
 rep movsb
 mov rsi,r13
 call append_hash
 mov byte [rdi],10
 inc rdi
.identity:
 lea rsi,[identity]
 mov ecx,identity_len
 rep movsb
 mov rsi,r14
 mov rcx,r15
 rep movsb
 mov rdx,rdi
 sub rdx,[rbx+git_commit_request.output]
 mov r15,rdx
 lea rdi,[commit_type]
 mov esi,6
 mov rdx,[rbx+git_commit_request.output]
 mov rcx,r15
 mov r8,[rbx+git_commit_request.hash]
 call git_object_hash
 mov rdx,r15
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RSI=32-byte hash, RDI=output cursor -> advanced RDI.
append_hash:
 lea r8,[hex]
 mov ecx,GIT_COMMIT_HASH_SIZE
.byte:
 lodsb
 movzx edx,al
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi],dl
 movzx edx,al
 and edx,15
 mov dl,[r8+rdx]
 mov [rdi+1],dl
 add rdi,2
 loop .byte
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
