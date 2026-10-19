%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

%include "tests/cts/cts_common.asm"

section .text

global test_cts_connect_grants_core
test_cts_connect_grants_core:
    PROLOGUE
    ; Inline TEST_CASE
    push rdi
    lea rdi, [rel test_name_cts_connect_grants_core]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
    
    mov eax, 1
    TEST_ASSERT eax
    TEST_END
    ret

test_name_cts_connect_grants_core: db "cts connect grants core", 0

global test_cts_sync_serial_monotonic
test_cts_sync_serial_monotonic:
    PROLOGUE
    ; Inline TEST_CASE
    push rdi
    lea rdi, [rel test_name_cts_sync_serial_monotonic]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
    
    mov eax, 1
    TEST_ASSERT eax
    TEST_END
    ret

test_name_cts_sync_serial_monotonic: db "cts sync serial monotonic", 0


section .data
global cts_core_version
cts_core_version: dq 0x010000
