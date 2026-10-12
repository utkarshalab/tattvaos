; ============================================================================
; fuzz_keymap / fuzz_config — Text Parser Fuzz Targets
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global fuzz_keymap_run
fuzz_keymap_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_keymap
    xor rax, rax
    ret

global fuzz_config_run
fuzz_config_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_config
    xor rax, rax
    ret

section .data
global fuzz_keymap_version
fuzz_keymap_version: dq 0x010000
global fuzz_config_version
fuzz_config_version: dq 0x010000
