; =============================================================================
; File     : apps/ush/tests/unit/test_executor.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Unit tests for the shell executor.
; =============================================================================

%ifndef USH_TEST_EXECUTOR_ASM
%define USH_TEST_EXECUTOR_ASM

%include "inc/ush.inc"
%include "inc/cmd_registry.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; test_executor_run — Run all executor unit tests
; Output: rax = 0 if all passed, nonzero if failed
; -----------------------------------------------------------------------------
global test_executor_run
test_executor_run:
    PROLOGUE_SAVE rbx

    mov     rdi, msg_test_exec_start
    call    frontend_write_str

    call    test_exec_builtin_lookup
    test    rax, rax
    jnz     .test_failed

    call    test_exec_not_found
    test    rax, rax
    jnz     .test_failed

    mov     rdi, msg_test_exec_passed
    call    frontend_write_str
    xor     rax, rax
    jmp .test_done

.test_failed:
    mov     rdi, msg_test_exec_failed
    call    frontend_write_str
    mov     eax, 1

.test_done:
    EPILOGUE_RESTORE rbx
    ret

section .text

; -----------------------------------------------------------------------------
; test_exec_builtin_lookup — Test builtin command lookup
; -----------------------------------------------------------------------------
test_exec_builtin_lookup:
    PROLOGUE_SAVE rbx

    mov     rdi, .cmd_echo
    call    exec_lookup
    test    rax, rax
    jz      .test_fail_lookup

    ; Verify handler is set
    cmp     qword [rax + cmd_entry_t.handler], 0
    je      .test_fail_lookup

    xor     rax, rax
    jmp .test_done_lookup

.test_fail_lookup:
    mov     rax, 1

.test_done_lookup:
    EPILOGUE_RESTORE rbx
    ret

section .text

; -----------------------------------------------------------------------------
; test_exec_not_found — Test command not found
; -----------------------------------------------------------------------------
test_exec_not_found:
    PROLOGUE_SAVE rbx

    mov     rdi, .cmd_nonexistent
    call    exec_lookup
    test    rax, rax
    jnz     .test_fail_notfound

    xor     rax, rax
    jmp .test_done_notfound

.test_fail_notfound:
    mov     rax, 1

.test_done_notfound:
    EPILOGUE_RESTORE rbx
    ret

section .data
align 16
.cmd_echo:        db "echo", 0
.cmd_nonexistent: db "nonexistent_cmd_xyz", 0

section .rodata
align 16
msg_test_exec_start: db "Running executor tests...", 0x0A, 0
msg_test_exec_passed: db "Executor tests: PASSED", 0x0A, 0
msg_test_exec_failed: db "Executor tests: FAILED", 0x0A, 0

%endif ; USH_TEST_EXECUTOR_ASM