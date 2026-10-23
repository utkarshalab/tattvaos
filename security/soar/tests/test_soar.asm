%ifndef GUARD_SECURITY_SOAR_TESTS_TEST_SOAR_ASM
%define GUARD_SECURITY_SOAR_TESTS_TEST_SOAR_ASM

; =============================================================================
; File     : security/soar/tests/test_soar.asm
; Project  : Utkarsha OS
; Description: SOAR premium skeleton test.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/soar.inc"

section .bss
alignb 16
test_components_tested: resq 11
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; Verify we can reference soar.inc constants (proves include works)
    mov     eax, SOAR_ACTION_ALERT
    mov     ebx, SOAR_ACTION_BLOCK_IP
    mov     ecx, SOAR_ACTION_QUARANTINE_HOST
    mov     edx, SOAR_ACTION_REVOKE_SESSION
    mov     esi, SOAR_ACTION_CREATE_TICKET
    mov     edi, SOAR_ACTION_SEND_NOTIFICATION
    mov     r8d, SOAR_ACTION_ISOLATE_HOST
    mov     r9d, SOAR_ACTION_COLLECT_EVIDENCE
    mov     r10d, SOAR_ACTION_UPDATE_POLICY

    mov     eax, SOAR_VERDICT_ALLOW
    mov     ebx, SOAR_VERDICT_BLOCK
    mov     ecx, SOAR_VERDICT_QUARANTINE
    mov     edx, SOAR_VERDICT_ERROR

    mov     eax, SOAR_FAIL_CLOSED
    mov     ebx, SOAR_FAIL_OPEN

    mov     eax, SOAR_REASON_NONE
    mov     ebx, SOAR_REASON_POLICY_VIOLATION
    mov     ecx, SOAR_REASON_INVALID_REQUEST
    mov     edx, SOAR_REASON_RATE_LIMIT
    mov     esi, SOAR_REASON_GEOIP_BLOCKED

    mov     eax, SOAR_CASE_OPEN
    mov     ebx, SOAR_CASE_INVESTIGATING
    mov     ecx, SOAR_CASE_RESOLVED
    mov     edx, SOAR_CASE_CLOSED
    mov     esi, SOAR_CASE_ESCALATED

    mov     eax, SOAR_PLAYBOOK_MANUAL
    mov     ebx, SOAR_PLAYBOOK_AUTOMATED
    mov     ecx, SOAR_PLAYBOOK_HYBRID

    ; Verify struc sizes are defined (proves data structures exist)
    mov     rax, soar_state_base_t_size
    mov     rbx, soar_event_ctx_t_size
    mov     rcx, soar_action_result_t_size
    mov     rdx, soar_rule_t_size
    mov     rsi, soar_case_t_size
    mov     r8, soar_action_t_size
    mov     r9, soar_trigger_t_size
    mov     r10, soar_global_state_t_size

    ; All structural checks passed
    mov     rax, 60          ; sys_exit
    xor     rdi, rdi         ; status 0
    syscall

%endif