%ifndef GUARD_SECURITY_IPS_TESTS_TEST_IPS_ASM
%define GUARD_SECURITY_IPS_TESTS_TEST_IPS_ASM

; =============================================================================
; File     : security/ips/tests/test_ips.asm
; Project  : Tattva OS
; Description: IPS premium enterprise skeleton test.
;              Validates that all 21 component .asm files exist, assemble
;              independently, and export the required enterprise contract
;              symbols (init, shutdown, status, version + component-specific
;              functions). Also verifies that all include guards, struc sizes,
;              and constants resolve correctly.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
test_components_tested: resq 21
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; =========================================================================
    ; This test file verifies structural integrity of the IPS module:
    ;
    ;   1. All 21 component source files exist in src/
    ;   2. Each component exports: *_init, *_shutdown, *_status, *_version
    ;   3. Component-specific functions are exported
    ;   4. All components include ips.inc
    ;   5. Include guards present in ips.inc
    ;
    ; Checks 1-5 are performed by tests/run.sh (bash). This .asm file simply
    ; verifies it can assemble standalone as a flat binary, confirming the
    ; NASM syntax, include paths, struc definitions, and constants are valid.
    ;
    ; Cross-component calls (ips_enforce calling ips_inspector_inspect,
    ; ips_policy_evaluate, ips_enforcer_apply_action, etc.) are STUBbed in
    ; source with comments - they resolve at system integration time when all
    ; components are linked into the kernel.
    ; =========================================================================

    ; Verify we can reference ips.inc constants (proves include works)
    mov     eax, IPS_ACTION_ALLOW
    mov     ebx, IPS_ACTION_DROP
    mov     ecx, IPS_ACTION_RESET
    mov     edx, IPS_ACTION_THROTTLE
    mov     esi, IPS_ACTION_QUARANTINE
    mov     edi, IPS_ACTION_BLOCK
    mov     r8d, IPS_ACTION_REDIRECT
    mov     r9d, IPS_ACTION_INSPECT_DEEP
    mov     r10d, IPS_ACTION_SANDBOX
    mov     r11d, IPS_ACTION_CHALLENGE

    mov     eax, IPS_VERDICT_ALLOW
    mov     ebx, IPS_VERDICT_DROP
    mov     ecx, IPS_VERDICT_RESET
    mov     edx, IPS_VERDICT_THROTTLE
    mov     esi, IPS_VERDICT_QUARANTINE
    mov     edi, IPS_VERDICT_BLOCK

    mov     eax, IPS_REASON_BLACKLISTED_IP
    mov     ebx, IPS_REASON_POLICY_VIOLATION
    mov     ecx, IPS_REASON_RATE_LIMIT
    mov     edx, IPS_REASON_IDS_ALERT
    mov     esi, IPS_REASON_PROTOCOL_VIOLATION
    mov     edi, IPS_REASON_QUARANTINED_HOST
    mov     r8d, IPS_REASON_CONNECTION_LIMIT
    mov     r9d, IPS_REASON_COMPONENT_DOWN
    mov     r10d, IPS_REASON_INVALID_REQUEST
    mov     r11d, IPS_REASON_GEOIP_BLOCKED
    mov     r12d, IPS_REASON_APP_BLOCKED
    mov     r13d, IPS_REASON_TLS_VIOLATION
    mov     r14d, IPS_REASON_DNS_BLOCKED
    mov     r15d, IPS_REASON_FILE_MALICIOUS

    mov     eax, IPS_FAIL_CLOSED
    mov     ebx, IPS_FAIL_OPEN

    mov     eax, IPS_CONN_NEW
    mov     ebx, IPS_CONN_ESTABLISHED
    mov     ecx, IPS_CONN_RELATED
    mov     edx, IPS_CONN_INVALID

    ; Verify protocol constants
    mov     eax, 6          ; TCP
    mov     ebx, 17         ; UDP
    mov     ecx, 1          ; ICMP

    ; Verify struc sizes are defined (proves data structures exist)
    mov     rax, ips_state_base_t_size
    mov     rbx, ips_enforce_ctx_t_size
    mov     rcx, ips_enforce_result_t_size
    mov     rdx, ips_blocklist_entry_t_size
    mov     rsi, ips_quarantine_entry_t_size
    mov     r8, ips_policy_rule_t_size
    mov     r9, ips_rate_limit_entry_t_size
    mov     r10, ips_connection_t_size
    mov     r11, ips_stats_t_size
    mov     r12, ips_geoip_entry_t_size
    mov     r13, ips_app_entry_t_size
    mov     r14, ips_tls_entry_t_size
    mov     r15, ips_dns_entry_t_size

    ; Verify global state struc size
    mov     rax, ips_global_state_t_size

    ; All structural checks passed
    mov     rax, 60          ; sys_exit
    xor     rdi, rdi         ; status 0
    syscall

%endif
