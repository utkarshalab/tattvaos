%ifndef GUARD_SECURITY_PRIVACY_COMPLIANCE_TESTS_TEST_PRIVACY_COMPLIANCE_ASM
%define GUARD_SECURITY_PRIVACY_COMPLIANCE_TESTS_TEST_PRIVACY_COMPLIANCE_ASM

; =============================================================================
; File     : security/privacy_compliance/tests/test_privacy_compliance.asm
; Project  : Utkarsha OS
; Description: Privacy compliance comprehensive test - all components.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/privacy.inc"

section .bss
alignb 16
test_components_tested: resq 5
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; ------------------------------------------------------------
    ; Verify version constants
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_VERSION_MAJOR
    cmp     eax, 1
    jne     .fail_version_major

    mov     eax, PRIVACY_VERSION_MINOR
    cmp     eax, 0
    jne     .fail_version_minor

    ; ------------------------------------------------------------
    ; Verify magic numbers
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_STATE_MAGIC
    cmp     eax, 0x50524956       ; "PRIV"
    jne     .fail_magic

    mov     eax, PRIVACY_STATE_MAGIC_FREED
    cmp     eax, 0xDEADBEEF
    jne     .fail_magic_freed

    ; ------------------------------------------------------------
    ; Verify component IDs
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_CORE
    cmp     eax, 1
    jne     .fail_component_core

    mov     eax, PRIVACY_DLP
    cmp     eax, 2
    jne     .fail_component_dlp

    mov     eax, PRIVACY_CONSENT
    cmp     eax, 4
    jne     .fail_component_consent

    mov     eax, PRIVACY_CLASSIFIER
    cmp     eax, 8
    jne     .fail_component_classifier

    mov     eax, PRIVACY_REPORTER
    cmp     eax, 16
    jne     .fail_component_reporter

    mov     eax, PRIVACY_ALL
    cmp     eax, 0x1F
    jne     .fail_component_all

    ; ------------------------------------------------------------
    ; Verify classification levels
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_CLASS_PUBLIC
    cmp     eax, 1
    jne     .fail_class_public

    mov     eax, PRIVACY_CLASS_INTERNAL
    cmp     eax, 2
    jne     .fail_class_internal

    mov     eax, PRIVACY_CLASS_CONFIDENTIAL
    cmp     eax, 3
    jne     .fail_class_confidential

    mov     eax, PRIVACY_CLASS_RESTRICTED
    cmp     eax, 4
    jne     .fail_class_restricted

    ; ------------------------------------------------------------
    ; Verify consent types
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_CONSENT_MARKETING
    cmp     eax, 1
    jne     .fail_consent_marketing

    mov     eax, PRIVACY_CONSENT_ANALYTICS
    cmp     eax, 2
    jne     .fail_consent_analytics

    mov     eax, PRIVACY_CONSENT_FUNCTIONAL
    cmp     eax, 3
    jne     .fail_consent_functional

    mov     eax, PRIVACY_CONSENT_PERSONALIZATION
    cmp     eax, 4
    jne     .fail_consent_personalization

    ; ------------------------------------------------------------
    ; Verify consent states
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_CONSENT_GRANTED
    cmp     eax, 1
    jne     .fail_consent_granted

    mov     eax, PRIVACY_CONSENT_DENIED
    cmp     eax, 2
    jne     .fail_consent_denied

    mov     eax, PRIVACY_CONSENT_WITHDRAWN
    cmp     eax, 3
    jne     .fail_consent_withdrawn

    mov     eax, PRIVACY_CONSENT_EXPIRED
    cmp     eax, 4
    jne     .fail_consent_expired

    ; ------------------------------------------------------------
    ; Verify DLP actions
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_DLP_ALLOW
    cmp     eax, 1
    jne     .fail_dlp_allow

    mov     eax, PRIVACY_DLP_BLOCK
    cmp     eax, 2
    jne     .fail_dlp_block

    mov     eax, PRIVACY_DLP_ENCRYPT
    cmp     eax, 3
    jne     .fail_dlp_encrypt

    mov     eax, PRIVACY_DLP_REDACT
    cmp     eax, 4
    jne     .fail_dlp_redact

    mov     eax, PRIVACY_DLP_QUARANTINE
    cmp     eax, 5
    jne     .fail_dlp_quarantine

    ; ------------------------------------------------------------
    ; Verify regulatory frameworks
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_REG_GDPR
    cmp     eax, 1
    jne     .fail_reg_gdpr

    mov     eax, PRIVACY_REG_CCPA
    cmp     eax, 2
    jne     .fail_reg_ccpa

    mov     eax, PRIVACY_REG_HIPAA
    cmp     eax, 3
    jne     .fail_reg_hipaa

    mov     eax, PRIVACY_REG_PCI_DSS
    cmp     eax, 4
    jne     .fail_reg_pci_dss

    ; ------------------------------------------------------------
    ; Verify error codes
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success

    mov     eax, PRIVACY_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general

    mov     eax, PRIVACY_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init

    mov     eax, PRIVACY_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg

    mov     eax, PRIVACY_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource

    mov     eax, PRIVACY_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access

    mov     eax, PRIVACY_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found

    mov     eax, PRIVACY_ERR_CONSENT_DENIED
    cmp     eax, 7
    jne     .fail_err_consent_denied

    mov     eax, PRIVACY_ERR_POLICY_VIOLATION
    cmp     eax, 8
    jne     .fail_err_policy_violation

    ; ------------------------------------------------------------
    ; Verify DSR response days default
    ; ------------------------------------------------------------
    mov     eax, PRIVACY_DEFAULT_DSR_RESPONSE_DAYS
    cmp     eax, 30
    jne     .fail_dsr_days

    ; ------------------------------------------------------------
    ; Verify struc sizes are defined
    ; ------------------------------------------------------------
    mov     rax, privacy_state_base_t_size
    mov     rbx, privacy_data_subject_t_size
    mov     rcx, privacy_consent_t_size
    mov     rdx, privacy_dlp_policy_t_size
    mov     rsi, privacy_dlp_incident_t_size
    mov     r8, privacy_report_t_size
    mov     r9, privacy_global_state_t_size

    ; All structural checks passed
    mov     rax, 60              ; sys_exit
    xor     rdi, rdi             ; status 0
    syscall

; ------------------------------------------------------------
; Failure handlers
; ------------------------------------------------------------
.fail_version_major:
    mov     qword [test_failures], 1
    jmp     .exit_fail
.fail_version_minor:
    mov     qword [test_failures], 2
    jmp     .exit_fail
.fail_magic:
    mov     qword [test_failures], 3
    jmp     .exit_fail
.fail_magic_freed:
    mov     qword [test_failures], 4
    jmp     .exit_fail
.fail_component_core:
    mov     qword [test_failures], 5
    jmp     .exit_fail
.fail_component_dlp:
    mov     qword [test_failures], 6
    jmp     .exit_fail
.fail_component_consent:
    mov     qword [test_failures], 7
    jmp     .exit_fail
.fail_component_classifier:
    mov     qword [test_failures], 8
    jmp     .exit_fail
.fail_component_reporter:
    mov     qword [test_failures], 9
    jmp     .exit_fail
.fail_component_all:
    mov     qword [test_failures], 10
    jmp     .exit_fail
.fail_class_public:
    mov     qword [test_failures], 11
    jmp     .exit_fail
.fail_class_internal:
    mov     qword [test_failures], 12
    jmp     .exit_fail
.fail_class_confidential:
    mov     qword [test_failures], 13
    jmp     .exit_fail
.fail_class_restricted:
    mov     qword [test_failures], 14
    jmp     .exit_fail
.fail_consent_marketing:
    mov     qword [test_failures], 15
    jmp     .exit_fail
.fail_consent_analytics:
    mov     qword [test_failures], 16
    jmp     .exit_fail
.fail_consent_functional:
    mov     qword [test_failures], 17
    jmp     .exit_fail
.fail_consent_personalization:
    mov     qword [test_failures], 18
    jmp     .exit_fail
.fail_consent_granted:
    mov     qword [test_failures], 19
    jmp     .exit_fail
.fail_consent_denied:
    mov     qword [test_failures], 20
    jmp     .exit_fail
.fail_consent_withdrawn:
    mov     qword [test_failures], 21
    jmp     .exit_fail
.fail_consent_expired:
    mov     qword [test_failures], 22
    jmp     .exit_fail
.fail_dlp_allow:
    mov     qword [test_failures], 23
    jmp     .exit_fail
.fail_dlp_block:
    mov     qword [test_failures], 24
    jmp     .exit_fail
.fail_dlp_encrypt:
    mov     qword [test_failures], 25
    jmp     .exit_fail
.fail_dlp_redact:
    mov     qword [test_failures], 26
    jmp     .exit_fail
.fail_dlp_quarantine:
    mov     qword [test_failures], 27
    jmp     .exit_fail
.fail_reg_gdpr:
    mov     qword [test_failures], 28
    jmp     .exit_fail
.fail_reg_ccpa:
    mov     qword [test_failures], 29
    jmp     .exit_fail
.fail_reg_hipaa:
    mov     qword [test_failures], 30
    jmp     .exit_fail
.fail_reg_pci_dss:
    mov     qword [test_failures], 31
    jmp     .exit_fail
.fail_err_success:
    mov     qword [test_failures], 32
    jmp     .exit_fail
.fail_err_general:
    mov     qword [test_failures], 33
    jmp     .exit_fail
.fail_err_not_init:
    mov     qword [test_failures], 34
    jmp     .exit_fail
.fail_err_invalid_arg:
    mov     qword [test_failures], 35
    jmp     .exit_fail
.fail_err_resource:
    mov     qword [test_failures], 36
    jmp     .exit_fail
.fail_err_access:
    mov     qword [test_failures], 37
    jmp     .exit_fail
.fail_err_not_found:
    mov     qword [test_failures], 38
    jmp     .exit_fail
.fail_err_consent_denied:
    mov     qword [test_failures], 39
    jmp     .exit_fail
.fail_err_policy_violation:
    mov     qword [test_failures], 40
    jmp     .exit_fail
.fail_dsr_days:
    mov     qword [test_failures], 41
    jmp     .exit_fail

.exit_fail:
    mov     rax, 60              ; sys_exit
    mov     rdi, 1               ; status 1 (failure)
    syscall

%endif