; ============================================================================
; soak_churn — 24h Client Connect/Commit/Fault Cycles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global soak_churn_run
soak_churn_run:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    xor r13d, r13d
.loop:
    cmp r13, r12
    jae .done
    mov rdi, rbx
    xor rsi, rsi
    xor rdx, rdx
    call surface_create
    test rax, rax
    js .next
    mov rdi, rbx
    mov rsi, rax
    mov rdx, 0
    call commit_surface
.next:
    inc r13
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global soak_churn_version
soak_churn_version: dq 0x010000
