%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

%include "tests/cts/cts_common.asm"

section .text

global test_cts_surface_create_destroy
test_cts_surface_create_destroy:
    PROLOGUE
    ; Inline TEST_CASE
    push rdi
    lea rdi, [rel test_name_cts_surface_create_destroy]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
    
    mov eax, 1
    TEST_ASSERT eax
    TEST_END
    ret

test_name_cts_surface_create_destroy: db "cts surface create destroy", 0

global test_cts_buffer_attach_commit
test_cts_buffer_attach_commit:
    PROLOGUE
    ; Inline TEST_CASE
    push rdi
    lea rdi, [rel test_name_cts_buffer_attach_commit]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
    
    mov eax, 1
    TEST_ASSERT eax
    TEST_END
    ret

test_name_cts_buffer_attach_commit: db "cts buffer attach commit", 0


section .data
global cts_surface_version
cts_surface_version: dq 0x010000
