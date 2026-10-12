; ============================================================================
; fuzz_objects — Object-Table Fuzz Target (stale handle / generation wrap)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global fuzz_objects_run
fuzz_objects_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    cmp r12, 4
    jb .done
    mov edi, [rbx]
    mov rsi, rdi
    call handle_resolve
    ; resolve must never crash on arbitrary input
.done:
    xor rax, rax
    ret

section .data
global fuzz_objects_version
fuzz_objects_version: dq 0x010000
