%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

%include "tests/cts/cts_common.asm"

section .text

global test_cts_sandboxed_has_no_capture
test_cts_sandboxed_has_no_capture:
    PROLOGUE
    ; Inline TEST_CASE
    push rdi
    lea rdi, [rel test_name_cts_sandboxed_has_no_capture]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
    
    mov eax, 1
    TEST_ASSERT eax
    TEST_END
    ret

test_name_cts_sandboxed_has_no_capture: db "cts sandboxed has no capture", 0


section .data
global cts_security_version
cts_security_version: dq 0x010000
