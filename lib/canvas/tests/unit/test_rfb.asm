; ============================================================================
; Unit Test — RFB Version Check (src/remote/rfb_handshake.asm)
; ============================================================================
; test_rfb_suite -> eax = failed cases (each case returns 0 / 1).
; The three versions spoken are accepted; other versions, majors and
; signatures are not.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern rfb_check_version

section .text

global test_rfb_suite
global test_rfb_main
test_rfb_suite:
test_rfb_main:
    sub rsp, 8
    xor eax, eax
%macro VERSION 2                        ; the 12-byte text at %1 gives %2
    push rax
    sub rsp, 8
    lea rdi, [rel %1]
    call rfb_check_version
    add rsp, 8
    cmp rax, %2
    pop rax
    je %%ok
    inc eax
%%ok:
%endmacro
    VERSION v33, 1
    VERSION v37, 1
    VERSION v38, 1
    VERSION v35, 0
    VERSION v_major, 0
    VERSION v_sep, 0
    VERSION v_name, 0
    add rsp, 8
    ret

section .rodata
v33:        db "RFB 003.003", 10
v37:        db "RFB 003.007", 10
v38:        db "RFB 003.008", 10
v35:        db "RFB 003.005", 10
v_major:    db "RFB 009.008", 10
v_sep:      db "RFB 003-008", 10
v_name:     db "XFB 003.008", 10
