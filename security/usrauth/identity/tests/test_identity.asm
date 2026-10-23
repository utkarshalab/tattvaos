%ifndef GUARD_SECURITY_USRAUTH_IDENTITY_TESTS_TEST_IDENTITY_ASM
%define GUARD_SECURITY_USRAUTH_IDENTITY_TESTS_TEST_IDENTITY_ASM

; =============================================================================
; File     : security/usrauth/identity/tests/test_identity.asm
; Project  : Utkarsha OS
; Description: Identity providers skeleton test - init/status/version.
; Status   : SKELETON
; =============================================================================

bits 64

section .text

global _start
_start:
    call    password_init
    test    rax, rax
    jnz     .fail_password

    call    webauthn_init
    test    rax, rax
    jnz     .fail_webauthn

    call    svid_init
    test    rax, rax
    jnz     .fail_svid

    call    attest_init
    test    rax, rax
    jnz     .fail_attest

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_password:
.fail_webauthn:
.fail_svid:
.fail_attest:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
