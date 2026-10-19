%ifndef GUARD_SECURITY_WAF_SRC_SUBJECT_TEST_ASM
%define GUARD_SECURITY_WAF_SRC_SUBJECT_ASM

; =============================================================================
; File     : security/usrauth/subject/tests/test_subject.asm
; Project  : Tattva OS
; Description: Subject skeleton test.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

section .text

global _start
_start:
    call    subject_init
    test    rax, rax
    jnz     .fail_subject_init

    call    subject_status
    test    rax, rax
    jnz     .fail_subject_status

    call    subject_version
    test    rax, rax
    jz      .fail_subject_version

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_subject_init:
.fail_subject_status:
.fail_subject_version:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
