%ifndef GUARD_SECURITY_USRAUTH_TESTS_TEST_USRAUTH_ASM
%define GUARD_SECURITY_USRAUTH_TESTS_TEST_USRAUTH_ASM

; =============================================================================
; File     : security/usrauth/tests/test_usrauth.asm
; Project  : Utkarsha OS
; Description: usrauth skeleton test - init/shutdown/status/version.
; Status   : SKELETON
; =============================================================================

bits 64

section .text

global _start
_start:
    call    usrauth_init
    test    rax, rax
    jnz     .fail_init

    call    usrauth_status
    test    rax, rax
    jnz     .fail_status

    call    usrauth_version
    test    rax, rax
    jz      .fail_version

    call    usrauth_shutdown
    test    rax, rax
    jnz     .fail_shutdown

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_init:
.fail_status:
.fail_version:
.fail_shutdown:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
