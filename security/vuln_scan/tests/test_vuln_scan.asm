%ifndef GUARD_SECURITY_VULN_SCAN_TESTS_TEST_VULN_SCAN_ASM
%define GUARD_SECURITY_VULN_SCAN_TESTS_TEST_VULN_SCAN_ASM

; =============================================================================
; File     : security/vuln_scan/tests/test_vuln_scan.asm
; Project  : Utkarsha OS
; Description: Vulnerability scan comprehensive test - all components.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/vuln_scan.inc"

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
    mov     eax, VULN_SCAN_VERSION_MAJOR
    cmp     eax, 1
    jne     .fail_version_major

    mov     eax, VULN_SCAN_VERSION_MINOR
    cmp     eax, 0
    jne     .fail_version_minor

    ; ------------------------------------------------------------
    ; Verify magic numbers
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_STATE_MAGIC
    cmp     eax, 0x56554C53       ; "VULS"
    jne     .fail_magic

    mov     eax, VULN_SCAN_STATE_MAGIC_FREED
    cmp     eax, 0xDEADBEEF
    jne     .fail_magic_freed

    ; ------------------------------------------------------------
    ; Verify component IDs
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_CORE
    cmp     eax, 1
    jne     .fail_component_core

    mov     eax, VULN_SCAN_SCANNER
    cmp     eax, 2
    jne     .fail_component_scanner

    mov     eax, VULN_SCAN_ASSESSOR
    cmp     eax, 4
    jne     .fail_component_assessor

    mov     eax, VULN_SCAN_DATABASE
    cmp     eax, 8
    jne     .fail_component_database

    mov     eax, VULN_SCAN_REPORTER
    cmp     eax, 16
    jne     .fail_component_reporter

    mov     eax, VULN_SCAN_ALL
    cmp     eax, 0x1F
    jne     .fail_component_all

    ; ------------------------------------------------------------
    ; Verify scan types
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_TYPE_NETWORK
    cmp     eax, 1
    jne     .fail_type_network

    mov     eax, VULN_SCAN_TYPE_HOST
    cmp     eax, 2
    jne     .fail_type_host

    mov     eax, VULN_SCAN_TYPE_APPLICATION
    cmp     eax, 3
    jne     .fail_type_application

    mov     eax, VULN_SCAN_TYPE_CONTAINER
    cmp     eax, 4
    jne     .fail_type_container

    mov     eax, VULN_SCAN_TYPE_CLOUD
    cmp     eax, 5
    jne     .fail_type_cloud

    ; ------------------------------------------------------------
    ; Verify severities
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_SEV_NONE
    cmp     eax, 0
    jne     .fail_sev_none

    mov     eax, VULN_SCAN_SEV_LOW
    cmp     eax, 1
    jne     .fail_sev_low

    mov     eax, VULN_SCAN_SEV_MEDIUM
    cmp     eax, 2
    jne     .fail_sev_medium

    mov     eax, VULN_SCAN_SEV_HIGH
    cmp     eax, 3
    jne     .fail_sev_high

    mov     eax, VULN_SCAN_SEV_CRITICAL
    cmp     eax, 4
    jne     .fail_sev_critical

    ; ------------------------------------------------------------
    ; Verify scan statuses
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_STATUS_QUEUED
    cmp     eax, 1
    jne     .fail_status_queued

    mov     eax, VULN_SCAN_STATUS_RUNNING
    cmp     eax, 2
    jne     .fail_status_running

    mov     eax, VULN_SCAN_STATUS_COMPLETED
    cmp     eax, 3
    jne     .fail_status_completed

    mov     eax, VULN_SCAN_STATUS_FAILED
    cmp     eax, 4
    jne     .fail_status_failed

    mov     eax, VULN_SCAN_STATUS_CANCELLED
    cmp     eax, 5
    jne     .fail_status_cancelled

    ; ------------------------------------------------------------
    ; Verify finding statuses
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_FINDING_OPEN
    cmp     eax, 1
    jne     .fail_finding_open

    mov     eax, VULN_SCAN_FINDING_IN_PROGRESS
    cmp     eax, 2
    jne     .fail_finding_in_progress

    mov     eax, VULN_SCAN_FINDING_REMEDIATED
    cmp     eax, 3
    jne     .fail_finding_remediated

    mov     eax, VULN_SCAN_FINDING_FALSE_POSITIVE
    cmp     eax, 4
    jne     .fail_finding_false_positive

    mov     eax, VULN_SCAN_FINDING_RISK_ACCEPTED
    cmp     eax, 5
    jne     .fail_finding_risk_accepted

    ; ------------------------------------------------------------
    ; Verify error codes
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success

    mov     eax, VULN_SCAN_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general

    mov     eax, VULN_SCAN_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init

    mov     eax, VULN_SCAN_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg

    mov     eax, VULN_SCAN_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource

    mov     eax, VULN_SCAN_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access

    mov     eax, VULN_SCAN_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found

    mov     eax, VULN_SCAN_ERR_SCAN_FAILED
    cmp     eax, 7
    jne     .fail_err_scan_failed

    mov     eax, VULN_SCAN_ERR_TARGET_UNREACHABLE
    cmp     eax, 8
    jne     .fail_err_target_unreachable

    ; ------------------------------------------------------------
    ; Verify scan timeout default
    ; ------------------------------------------------------------
    mov     eax, VULN_SCAN_DEFAULT_SCAN_TIMEOUT
    cmp     eax, 3600
    jne     .fail_scan_timeout

    ; ------------------------------------------------------------
    ; Verify struc sizes are defined
    ; ------------------------------------------------------------
    mov     rax, vuln_scan_state_base_t_size
    mov     rbx, vuln_scan_target_t_size
    mov     rcx, vuln_scan_finding_t_size
    mov     rdx, vuln_scan_scan_t_size
    mov     rsi, vuln_scan_db_entry_t_size
    mov     r8, vuln_scan_report_t_size
    mov     r9, vuln_scan_global_state_t_size

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
.fail_component_scanner:
    mov     qword [test_failures], 6
    jmp     .exit_fail
.fail_component_assessor:
    mov     qword [test_failures], 7
    jmp     .exit_fail
.fail_component_database:
    mov     qword [test_failures], 8
    jmp     .exit_fail
.fail_component_reporter:
    mov     qword [test_failures], 9
    jmp     .exit_fail
.fail_component_all:
    mov     qword [test_failures], 10
    jmp     .exit_fail
.fail_type_network:
    mov     qword [test_failures], 11
    jmp     .exit_fail
.fail_type_host:
    mov     qword [test_failures], 12
    jmp     .exit_fail
.fail_type_application:
    mov     qword [test_failures], 13
    jmp     .exit_fail
.fail_type_container:
    mov     qword [test_failures], 14
    jmp     .exit_fail
.fail_type_cloud:
    mov     qword [test_failures], 15
    jmp     .exit_fail
.fail_sev_none:
    mov     qword [test_failures], 16
    jmp     .exit_fail
.fail_sev_low:
    mov     qword [test_failures], 17
    jmp     .exit_fail
.fail_sev_medium:
    mov     qword [test_failures], 18
    jmp     .exit_fail
.fail_sev_high:
    mov     qword [test_failures], 19
    jmp     .exit_fail
.fail_sev_critical:
    mov     qword [test_failures], 20
    jmp     .exit_fail
.fail_status_queued:
    mov     qword [test_failures], 21
    jmp     .exit_fail
.fail_status_running:
    mov     qword [test_failures], 22
    jmp     .exit_fail
.fail_status_completed:
    mov     qword [test_failures], 23
    jmp     .exit_fail
.fail_status_failed:
    mov     qword [test_failures], 24
    jmp     .exit_fail
.fail_status_cancelled:
    mov     qword [test_failures], 25
    jmp     .exit_fail
.fail_finding_open:
    mov     qword [test_failures], 26
    jmp     .exit_fail
.fail_finding_in_progress:
    mov     qword [test_failures], 27
    jmp     .exit_fail
.fail_finding_remediated:
    mov     qword [test_failures], 28
    jmp     .exit_fail
.fail_finding_false_positive:
    mov     qword [test_failures], 29
    jmp     .exit_fail
.fail_finding_risk_accepted:
    mov     qword [test_failures], 30
    jmp     .exit_fail
.fail_err_success:
    mov     qword [test_failures], 31
    jmp     .exit_fail
.fail_err_general:
    mov     qword [test_failures], 32
    jmp     .exit_fail
.fail_err_not_init:
    mov     qword [test_failures], 33
    jmp     .exit_fail
.fail_err_invalid_arg:
    mov     qword [test_failures], 34
    jmp     .exit_fail
.fail_err_resource:
    mov     qword [test_failures], 35
    jmp     .exit_fail
.fail_err_access:
    mov     qword [test_failures], 36
    jmp     .exit_fail
.fail_err_not_found:
    mov     qword [test_failures], 37
    jmp     .exit_fail
.fail_err_scan_failed:
    mov     qword [test_failures], 38
    jmp     .exit_fail
.fail_err_target_unreachable:
    mov     qword [test_failures], 39
    jmp     .exit_fail
.fail_scan_timeout:
    mov     qword [test_failures], 40
    jmp     .exit_fail

.exit_fail:
    mov     rax, 60              ; sys_exit
    mov     rdi, 1               ; status 1 (failure)
    syscall

%endif