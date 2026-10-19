%ifndef GUARD_SECURITY_WAF_SRC_TOKEN_TEST_ASM
%define GUARD_SECURITY_WAF_SRC_TOKEN_ASM

; =============================================================================
; File     : security/usrauth/token/tests/test_token.asm
; Project  : Tattva OS
; Description: Token skeleton test.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

section .text

global _start
_start:
    call    token_init
    test    rax, rax
    jnz     .fail_token_init

    call    caveat_init
    test    rax, rax
    jnz     .fail_caveat_init

    call    revoke_init
    test    rax, rax
    jnz     .fail_revoke_init

    mov     rax, 60
    xor     rdi, rdi
    syscall

.fail_token_init:
.fail_caveat_init:
.fail_revoke_init:
    mov     rax, 60
    mov     rdi, 1
    syscall

%endif
