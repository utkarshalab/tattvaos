%ifndef GUARD_SECURITY_WAF_TESTS_TEST_WAF_ASM
%define GUARD_SECURITY_WAF_TESTS_TEST_WAF_ASM

; =============================================================================
; File     : security/waf/tests/test_waf.asm
; Project  : Tattva OS
; Description: WAF premium enterprise skeleton test.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
test_components_tested: resq 18
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; Verify WAF constants resolve
    mov     eax, WAF_ACTION_ALLOW
    mov     ebx, WAF_ACTION_BLOCK
    mov     ecx, WAF_ACTION_CHALLENGE
    mov     edx, WAF_ACTION_LOG
    mov     esi, WAF_ACTION_REDIRECT

    mov     eax, WAF_VERDICT_ALLOW
    mov     ebx, WAF_VERDICT_BLOCK
    mov     ecx, WAF_VERDICT_CHALLENGE

    mov     eax, WAF_ATTACK_SQLI
    mov     ebx, WAF_ATTACK_XSS
    mov     ecx, WAF_ATTACK_CSRF
    mov     edx, WAF_ATTACK_FILE_INCLUSION
    mov     esi, WAF_ATTACK_CMD_INJECTION
    mov     edi, WAF_ATTACK_DESERIALIZATION
    mov     r8d, WAF_ATTACK_SCANNER
    mov     r9d, WAF_ATTACK_BOT
    mov     r10d, WAF_ATTACK_API_ABUSE

    mov     eax, WAF_SEV_LOW
    mov     ebx, WAF_SEV_MEDIUM
    mov     ecx, WAF_SEV_HIGH
    mov     edx, WAF_SEV_CRITICAL

    ; Verify struc sizes
    mov     rax, waf_state_base_t_size
    mov     rbx, waf_request_ctx_t_size
    mov     rcx, waf_rule_t_size
    mov     rdx, waf_match_t_size
    mov     rsi, waf_blocked_ip_t_size
    mov     r8, waf_session_t_size
    mov     r9, waf_api_key_t_size
    mov     r10, waf_stats_t_size
    mov     r11, waf_global_state_t_size

    ; All structural checks passed
    mov     rax, 60
    xor     rdi, rdi
    syscall

%endif
