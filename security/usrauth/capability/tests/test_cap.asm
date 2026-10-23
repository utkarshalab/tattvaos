%ifndef GUARD_SECURITY_WAF_TESTS_CAP_ASM
%define GUARD_SECURITY_WAF_SRC_CAP_ASM

; =============================================================================
; File     : security/usrauth/capability/tests/test_cap.asm
; Project  : Utkarsha OS
; Description: Capability skeleton test.
; Status   : PREMIUM SKELETON
; =============================================================================

bits 64
DEFAULT REL

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

    call    cap_issue
    test    rax, rax
    jnz     .fail_cap_issue

    call    cap_revoke
    test    rax, rax
    jnz     .fail_cap_revoke

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_cap_init:
.fail_cap_status:
.fail_cap_version:
.fail_cap_issue:
.fail_cap_revoke:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
