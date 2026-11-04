bits 64
default rel

extern vcs_sync_repository_policy,vcs_sync_policy_count
global vcs_sync_plan,policy_call_probe
global policy_test_status,policy_test_count,policy_test_head
global policy_test_digest,policy_test_ref,policy_test_capacity,policy_test_calls

section .bss
policy_test_status: resq 1
policy_test_count: resq 1
policy_test_head: resb 32
policy_test_digest: resq 1
policy_test_ref: resq 1
policy_test_capacity: resq 1
policy_test_calls: resq 1

section .text
; Deterministic planner substitute for repository-policy unit coverage.
vcs_sync_plan:
 mov [policy_test_digest],rdi
 mov [policy_test_ref],rsi
 mov [policy_test_capacity],rcx
 inc qword [policy_test_calls]
 mov r10,rdx
 mov r8,[policy_test_count]
 xor r11d,r11d
.fill:
 cmp r11,r8
 jae .return
 cmp r11,rcx
 jae .return
 lea rax,[r11+1]
 mov [r10+r11*8],rax
 inc r11
 jmp .fill
.return:
 mov rax,[policy_test_status]
 mov rdx,[policy_test_count]
 lea r9,[policy_test_head]
 ret

; EDI=operation, RSI=digest, RDX=ref, RCX=incoming, R8=four-qword results.
policy_call_probe:
 push rbx
 mov rbx,r8
 call vcs_sync_repository_policy
 mov [rbx],rax
 mov [rbx+8],rdx
 mov [rbx+16],rcx
 mov rax,[vcs_sync_policy_count]
 mov [rbx+24],rax
 pop rbx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
