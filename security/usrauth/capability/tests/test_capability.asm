%ifndef GUARD_SECURITY_USRAUTH_CAPABILITY_TESTS_TEST_CAPABILITY_ASM
%define GUARD_SECURITY_USRAUTH_CAPABILITY_TESTS_TEST_CAPABILITY_ASM

; =============================================================================
; File     : security/usrauth/capability/tests/test_capability.asm
; Project  : Tattva OS
; Description: Capability skeleton test - init/shutdown/status/version.
; Status   : SKELETON
; =============================================================================

bits 64

section .text

global _start
_start:
    call    cap_init
    test    rax, rax
    jnz     .fail_cap_init

    call    cap_status
    test    rax, rax
    jnz     .fail_cap_status

    call    cap_version
    test    rax, rax
    jz      .fail_cap_version

    call    restrict_init
    test    rax, rax
    jnz     .fail_restrict_init

    call    cap_shutdown
    test    rax, rax
    jnz     .fail_cap_shutdown

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_cap_init:
.fail_cap_status:
.fail_cap_version:
.fail_restrict_init:
.fail_cap_shutdown:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
