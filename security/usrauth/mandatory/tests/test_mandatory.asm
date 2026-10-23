%ifndef GUARD_SECURITY_WAF_SRC_MANDATORY_TEST_ASM
%define GUARD_SECURITY_WAF_SRC_MANDATORY_ASM

; =============================================================================
; File     : security/usrauth/mandatory/tests/test_mandatory.asm
; Project  : Utkarsha OS
; Description: Mandatory access control skeleton test.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

section .text

global _start
_start:
    call    integrity_init
    test    rax, rax
    jnz     .fail_integrity_init

    call    mls_init
    test    rax, rax
    jnz     .fail_mls_init

    call    te_init
    test    rax, rax
    jnz     .fail_te_init

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_integrity_init:
.fail_mls_init:
.fail_te_init:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
