; ============================================================================
; soak_quota — Quota Pressure: Alloc to Limit, Verify Containment
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global soak_quota_run
soak_quota_run:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    xor r13d, r13d
    xor r14d, r14d
.loop:
    cmp r13, r12
    jae .done
    mov rdi, rbx
    xor rsi, rsi
    xor rdx, rdx
    call surface_create
    test rax, rax
    js .over_limit
    inc r14
    jmp .next
.over_limit:
    jmp .next
.next:
    inc r13
    jmp .loop
.done:
    mov rax, r14
    ret

section .data
global soak_quota_version
soak_quota_version: dq 0x010000
