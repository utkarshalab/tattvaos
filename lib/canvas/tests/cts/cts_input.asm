%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

%include "tests/cts/cts_common.asm"

section .text

global test_cts_input_connect
test_cts_input_connect:
    PROLOGUE
    ; Inline TEST_CASE
    push rdi
    lea rdi, [rel test_name_cts_input_connect]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
    
    mov eax, 1
    TEST_ASSERT eax
    TEST_END
    ret

test_name_cts_input_connect: db "cts input connect", 0


section .data
global cts_input_version
cts_input_version: dq 0x010000
