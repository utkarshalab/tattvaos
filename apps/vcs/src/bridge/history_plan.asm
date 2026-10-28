; Bounded validated first-parent planning shared by Git export and upload-pack.
%include "include/vcs.inc"
bits 64
default rel

extern vcs_load_manifest

section .text
global git_first_parent_plan

; RDI=tip VCS commit ID, RSI=u64 ID output, RDX=capacity.
; RAX=status, RDX=count. IDs are returned newest-first.
git_first_parent_plan:
 push rbx
 push r12
 push r13
 push r14
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 test r12,r12
 jz .usage
 test r13,r13
 jz .usage
 test r14,r14
 jz .usage
 xor ebx,ebx
.collect:
 cmp rbx,r14
 jae .capacity
 mov [r13+rbx*8],r12
 inc rbx
 mov rdi,r12
 call vcs_load_manifest
 test rax,rax
 jz .corrupt
 mov r12,[rax+16]
 test r12,r12
 jnz .collect
 mov rdx,rbx
 xor eax,eax
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.capacity:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
