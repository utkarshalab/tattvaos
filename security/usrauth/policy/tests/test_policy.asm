%ifndef GUARD_SECURITY_WAF_SRC_POLICY_TEST_ASM
%define GUARD_SECURITY_WAF_SRC_POLICY_ASM

; =============================================================================
; File     : security/usrauth/policy/tests/test_policy.asm
; Project  : Utkarsha OS
; Description: Policy skeleton test.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

section .text

global _start
_start:
    call    attribute_init
    test    rax, rax
    jnz     .fail_attribute_init

    call    consent_init
    test    rax, rax
    jnz     .fail_consent_init

    call    relation_init
    test    rax, rax
    jnz     .fail_relation_init

    call    ttl_init
    test    rax, rax
    jnz     .fail_ttl_init

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_attribute_init:
.fail_consent_init:
.fail_relation_init:
.fail_ttl_init:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
