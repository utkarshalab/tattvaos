%ifndef GUARD_SECURITY_WAF_TESTS_AUDIT_ASM
%define GUARD_SECURITY_WAF_SRC_AUDIT_DFIR_ASM

; =============================================================================
; File     : security/usrauth/audit/tests/test_audit.asm
; Project  : Tattva OS
; Description: Audit skeleton test.
; Status   : SKELETON
; =============================================================================

bits 64
DEFAULT REL

section .text

global _start
_start:
    call    audit_init
    test    rax, rax
    jnz     .fail_audit_init

    call    audit_status
    test    rax, rax
    jnz     .fail_audit_status

    call    audit_version
    test    rax, rax
    jz      .fail_audit_version

    call    audit_shutdown
    test    rax, rax
    jnz     .fail_audit_shutdown

    mov     rax, 60
    xor     rdi, rdi
    syscall

.err_cd:
    mov     rax, -2
    pop     rbx
    ret
.err_inv:
    mov     rax, -3
    pop     rbx
    ret

.fail_audit_init:
.fail_audit_status:
.fail_audit_version:
.fail_audit_shutdown:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
