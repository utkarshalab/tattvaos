; ============================================================================
; fuzz_wire — Wire Parser Fuzz Target
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global fuzz_wire_run
fuzz_wire_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_wire
    xor rax, rax
    ret

section .data
global fuzz_wire_version
fuzz_wire_version: dq 0x010000
