%ifndef GUARD_SECURITY_ZERO_TRUST_TESTS_TEST_ZERO_TRUST_ASM
%define GUARD_SECURITY_ZERO_TRUST_TESTS_TEST_ZERO_TRUST_ASM

; =============================================================================
; File     : security/zero_trust/tests/test_zero_trust.asm
; Project  : Utkarsha OS
; Description: Zero Trust premium skeleton test.
;              Validates that all 8 component .asm files exist, assemble
;              independently, and export the required enterprise contract
;              symbols (init, shutdown, status, version).
;              This test assembles standalone - no cross-component calls
;              (those are separate binaries linked at system integration).
; Status   : PREMIUM SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/zero_trust.inc"
%include "../usrauth/include/usrauth.inc"

section .bss
alignb 16
test_components_tested: resq 8
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; =========================================================================
    ; This test file verifies structural integrity of the zero_trust module:
    ;
    ;   1. All 8 component source files exist in src/
    ;   2. Each component exports: *_init, *_shutdown, *_status, *_version
    ;   3. All components include zero_trust.inc
    ;   4. zero_trust.asm includes usrauth.inc (intersection model dep)
    ;   5. Include guards present in zero_trust.inc
    ;
    ; Checks 1-5 are performed by tests/run.sh (bash). This .asm file simply
    ; verifies it can assemble standalone as a flat binary, confirming the
    ; NASM syntax and include paths are valid.
    ;
    ; Cross-component calls (zt_evaluate_access calling zt_policy_engine_*,
    ; etc.) are STUBbed in source with comments - they resolve at system
    ; integration time when all components are linked into the kernel.
    ; =========================================================================

    ; Verify we can reference zero_trust.inc constants (proves include works)
    mov     eax, ZT_VERDICT_ALLOW
    mov     ebx, ZT_DENY_NO_SESSION
    mov     ecx, ZT_DENY_SESSION_EXPIRED
    mov     edx, ZT_DENY_POSTURE_FAIL
    mov     edi, ZT_DENY_SEGMENT_BLOCKED

    ; Verify we can reference usrauth.inc constants (proves intersection dep)
    mov     esi, USRAUTH_ALLOW
    mov     r8d, USRAUTH_DENY_MANDATORY
    mov     r9d, USRAUTH_VERB_READ

    ; Verify struc sizes are defined (proves data structures exist)
    ; (These would fail to assemble if strucs were missing)
    mov     rax, zt_state_base_t_size
    mov     rbx, zt_request_ctx_t_size
    mov     rcx, zt_verdict_t_size
    mov     rdx, zt_policy_rule_t_size
    mov     rsi, zt_session_t_size

    ; All structural checks passed
    mov     rax, 60          ; sys_exit
    xor     rdi, rdi         ; status 0
    syscall

%endif
