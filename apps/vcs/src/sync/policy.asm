; Repository negotiation policy for fetch, push advertisement, and clone.
%include "include/vcs.inc"
%include "include/sync_protocol.inc"
bits 64
default rel

extern vcs_sync_plan

section .bss
global vcs_sync_policy_ids,vcs_sync_policy_count
vcs_sync_policy_ids: resq 64
vcs_sync_policy_count: resq 1

section .text
global vcs_sync_repository_policy

; EDI=operation, RSI=peer digest32, RDX=ref or zero, RCX=incoming count.
; EAX=response status, RDX=local head digest, RCX=outgoing bundle count.
vcs_sync_repository_policy:
 push rbx
 push r12
 push r13
 mov ebx,edi
 mov r12,rsi
 mov r13,rdx
 mov qword [vcs_sync_policy_count],0
 cmp ebx,VS_OP_PUSH
 je .push
 cmp ebx,VS_OP_FETCH
 je .plan
 cmp ebx,VS_OP_CLONE
 jne .unsupported
 ; Clone is defined only from an unborn peer.
 mov rax,[r12]
 or rax,[r12+8]
 or rax,[r12+16]
 or rax,[r12+24]
 jnz .conflict
.plan:
 mov rdi,r12
 mov rsi,r13
 lea rdx,[vcs_sync_policy_ids]
 mov ecx,64
 call vcs_sync_plan
 test eax,eax
 jnz .policy_done
 mov [vcs_sync_policy_count],rdx
 mov rcx,rdx
 mov rdx,r9
 xor eax,eax
 jmp .policy_done
.push:
 ; Count zero is the signed advertisement round. A nonzero second round
 ; declares the exact number of bundle frames the server will accept.
 test rcx,rcx
 jnz .push_accept
 xor edi,edi
 xor esi,esi
 lea rdx,[vcs_sync_policy_ids]
 mov ecx,64
 call vcs_sync_plan
 test eax,eax
 jnz .policy_done
 mov rdx,r9
 xor ecx,ecx
 xor eax,eax
 jmp .policy_done
.push_accept:
 cmp rcx,64
 ja .usage
 mov [vcs_sync_policy_count],rcx
 xor edi,edi
 xor esi,esi
 lea rdx,[vcs_sync_policy_ids]
 mov ecx,64
 call vcs_sync_plan
 test eax,eax
 jnz .policy_done
 mov rdx,r9
 xor ecx,ecx
 xor eax,eax
 jmp .policy_done
.usage: mov eax,VCS_ERR_USAGE
 jmp .policy_done
.conflict: mov eax,VCS_ERR_CONFLICT
 jmp .policy_done
.unsupported: mov eax,VCS_ERR_UNSUPPORTED
.policy_done:
 pop r13
 pop r12
 pop rbx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
