%ifndef GUARD_SECURITY_WAF_SRC_PASSWORD_TEST_ASM
%define GUARD_SECURITY_WAF_SRC_WAF_PASSWORD_ASM

; =============================================================================
; File     : security/usrauth/identity/src/password_test.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Password identity provider skeleton test.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

section .text

global _start
_start:
    call    password_init
    test    rax, rax
    jnz     .fail_password_init

    call    password_status
    test    rax, rax
    jnz     .fail_password_status

    call    password_version
    test    rax, rax
    jz      .fail_password_version

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_password_init:
.fail_password_status:
.fail_password_version:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
