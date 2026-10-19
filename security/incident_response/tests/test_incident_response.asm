%ifndef GUARD_SECURITY_INCIDENT_RESPONSE_TESTS_TEST_INCIDENT_RESPONSE_ASM
%define GUARD_SECURITY_INCIDENT_RESPONSE_TESTS_TEST_INCIDENT_RESPONSE_ASM

; =============================================================================
; File     : security/incident_response/tests/test_incident_response.asm
; Project  : Tattva OS
; Description: Incident Response comprehensive test - all components.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/ir.inc"

section .bss
alignb 16
test_components_tested: resq 6
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; ------------------------------------------------------------
    ; Verify version constants
    ; ------------------------------------------------------------
    mov     eax, IR_VERSION_MAJOR
    cmp     eax, 1
    jne     .fail_version_major

    mov     eax, IR_VERSION_MINOR
    cmp     eax, 0
    jne     .fail_version_minor

    ; ------------------------------------------------------------
    ; Verify magic numbers
    ; ------------------------------------------------------------
    mov     eax, IR_STATE_MAGIC
    cmp     eax, 0x49525350       ; "IRSP"
    jne     .fail_magic

    mov     eax, IR_STATE_MAGIC_FREED
    cmp     eax, 0xDEADBEEF
    jne     .fail_magic_freed

    ; ------------------------------------------------------------
    ; Verify component IDs
    ; ------------------------------------------------------------
    mov     eax, IR_CORE
    cmp     eax, 1
    jne     .fail_component_core

    mov     eax, IR_TRIAGE
    cmp     eax, 2
    jne     .fail_component_triage

    mov     eax, IR_CONTAINMENT
    cmp     eax, 4
    jne     .fail_component_containment

    mov     eax, IR_ERADICATION
    cmp     eax, 8
    jne     .fail_component_eradication

    mov     eax, IR_RECOVERY
    cmp     eax, 16
    jne     .fail_component_recovery

    mov     eax, IR_PLAYBOOKS
    cmp     eax, 32
    jne     .fail_component_playbooks

    mov     eax, IR_ALL
    cmp     eax, 0x3F
    jne     .fail_component_all

    ; ------------------------------------------------------------
    ; Verify severities
    ; ------------------------------------------------------------
    mov     eax, IR_SEV_INFO
    cmp     eax, 1
    jne     .fail_sev_info

    mov     eax, IR_SEV_LOW
    cmp     eax, 2
    jne     .fail_sev_low

    mov     eax, IR_SEV_MEDIUM
    cmp     eax, 3
    jne     .fail_sev_medium

    mov     eax, IR_SEV_HIGH
    cmp     eax, 4
    jne     .fail_sev_high

    mov     eax, IR_SEV_CRITICAL
    cmp     eax, 5
    jne     .fail_sev_critical

    ; ------------------------------------------------------------
    ; Verify statuses
    ; ------------------------------------------------------------
    mov     eax, IR_STATUS_NEW
    cmp     eax, 1
    jne     .fail_status_new

    mov     eax, IR_STATUS_TRIAGED
    cmp     eax, 2
    jne     .fail_status_triaged

    mov     eax, IR_STATUS_CONTAINED
    cmp     eax, 3
    jne     .fail_status_contained

    mov     eax, IR_STATUS_ERADICATED
    cmp     eax, 4
    jne     .fail_status_eradicated

    mov     eax, IR_STATUS_RECOVERED
    cmp     eax, 5
    jne     .fail_status_recovered

    mov     eax, IR_STATUS_CLOSED
    cmp     eax, 6
    jne     .fail_status_closed

    mov     eax, IR_STATUS_REOPENED
    cmp     eax, 7
    jne     .fail_status_reopened

    ; ------------------------------------------------------------
    ; Verify priorities
    ; ------------------------------------------------------------
    mov     eax, IR_PRIORITY_LOW
    cmp     eax, 1
    jne     .fail_priority_low

    mov     eax, IR_PRIORITY_MEDIUM
    cmp     eax, 2
    jne     .fail_priority_medium

    mov     eax, IR_PRIORITY_HIGH
    cmp     eax, 3
    jne     .fail_priority_high

    mov     eax, IR_PRIORITY_CRITICAL
    cmp     eax, 4
    jne     .fail_priority_critical

    ; ------------------------------------------------------------
    ; Verify containment actions
    ; ------------------------------------------------------------
    mov     eax, IR_CONTAIN_ISOLATE_HOST
    cmp     eax, 1
    jne     .fail_contain_isolate_host

    mov     eax, IR_CONTAIN_REVOKE_SESSION
    cmp     eax, 2
    jne     .fail_contain_revoke_session

    mov     eax, IR_CONTAIN_BLOCK_INDICATOR
    cmp     eax, 3
    jne     .fail_contain_block_indicator

    mov     eax, IR_CONTAIN_DISABLE_ACCOUNT
    cmp     eax, 4
    jne     .fail_contain_disable_account

    mov     eax, IR_CONTAIN_BLOCK_IP
    cmp     eax, 5
    jne     .fail_contain_block_ip

    mov     eax, IR_CONTAIN_DISABLE_SERVICE
    cmp     eax, 6
    jne     .fail_contain_disable_service

    ; ------------------------------------------------------------
    ; Verify eradication actions
    ; ------------------------------------------------------------
    mov     eax, IR_ERAD_REMOVE_MALWARE
    cmp     eax, 1
    jne     .fail_erad_remove_malware

    mov     eax, IR_ERAD_DISABLE_PERSISTENCE
    cmp     eax, 2
    jne     .fail_erad_disable_persistence

    mov     eax, IR_ERAD_PATCH_VULNERABILITY
    cmp     eax, 3
    jne     .fail_erad_patch_vuln

    mov     eax, IR_ERAD_RESET_CREDENTIALS
    cmp     eax, 4
    jne     .fail_erad_reset_creds

    mov     eax, IR_ERAD_REMOVE_BACKDOOR
    cmp     eax, 5
    jne     .fail_erad_remove_backdoor

    mov     eax, IR_ERAD_REBUILD_SYSTEM
    cmp     eax, 6
    jne     .fail_erad_rebuild_system

    ; ------------------------------------------------------------
    ; Verify recovery actions
    ; ------------------------------------------------------------
    mov     eax, IR_RECOVER_RESTORE_BACKUP
    cmp     eax, 1
    jne     .fail_recover_restore

    mov     eax, IR_RECOVER_VALIDATE_INTEGRITY
    cmp     eax, 2
    jne     .fail_recover_validate

    mov     eax, IR_RECOVER_MONITOR_ACTIVITY
    cmp     eax, 3
    jne     .fail_recover_monitor

    mov     eax, IR_RECOVER_UPDATE_DETECTION
    cmp     eax, 4
    jne     .fail_recover_update

    mov     eax, IR_RECOVER_CONDUCT_REVIEW
    cmp     eax, 5
    jne     .fail_recover_review

    ; ------------------------------------------------------------
    ; Verify playbook types
    ; ------------------------------------------------------------
    mov     eax, IR_PLAYBOOK_PHISHING
    cmp     eax, 1
    jne     .fail_playbook_phishing

    mov     eax, IR_PLAYBOOK_MALWARE
    cmp     eax, 2
    jne     .fail_playbook_malware

    mov     eax, IR_PLAYBOOK_RANSOMWARE
    cmp     eax, 3
    jne     .fail_playbook_ransomware

    mov     eax, IR_PLAYBOOK_DDoS
    cmp     eax, 4
    jne     .fail_playbook_ddos

    mov     eax, IR_PLAYBOOK_INSIDER_THREAT
    cmp     eax, 5
    jne     .fail_playbook_insider

    mov     eax, IR_PLAYBOOK_DATA_BREACH
    cmp     eax, 6
    jne     .fail_playbook_databreach

    mov     eax, IR_PLAYBOOK_APT
    cmp     eax, 7
    jne     .fail_playbook_apt

    ; ------------------------------------------------------------
    ; Verify error codes
    ; ------------------------------------------------------------
    mov     eax, IR_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success

    mov     eax, IR_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general

    mov     eax, IR_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init

    mov     eax, IR_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg

    mov     eax, IR_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource

    mov     eax, IR_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access

    mov     eax, IR_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found

    mov     eax, IR_ERR_CONTAINMENT
    cmp     eax, 7
    jne     .fail_err_containment

    mov     eax, IR_ERR_ERADICATION
    cmp     eax, 8
    jne     .fail_err_eradication

    ; ------------------------------------------------------------
    ; Verify SLA defaults
    ; ------------------------------------------------------------
    mov     eax, IR_DEFAULT_SLA_CRITICAL_MIN
    cmp     eax, 15
    jne     .fail_sla_critical

    mov     eax, IR_DEFAULT_SLA_HIGH_MIN
    cmp     eax, 60
    jne     .fail_sla_high

    mov     eax, IR_DEFAULT_SLA_MEDIUM_MIN
    cmp     eax, 240
    jne     .fail_sla_medium

    mov     eax, IR_DEFAULT_SLA_LOW_MIN
    cmp     eax, 1440
    jne     .fail_sla_low

    ; ------------------------------------------------------------
    ; Verify struc sizes are defined
    ; ------------------------------------------------------------
    mov     rax, ir_state_base_t_size
    mov     rbx, ir_incident_t_size
    mov     rcx, ir_containment_t_size
    mov     rdx, ir_eradication_t_size
    mov     rsi, ir_recovery_t_size
    mov     r8, ir_playbook_t_size
    mov     r9, ir_global_state_t_size

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
.fail_component_triage:
    mov     qword [test_failures], 6
    jmp     .exit_fail
.fail_component_containment:
    mov     qword [test_failures], 7
    jmp     .exit_fail
.fail_component_eradication:
    mov     qword [test_failures], 8
    jmp     .exit_fail
.fail_component_recovery:
    mov     qword [test_failures], 9
    jmp     .exit_fail
.fail_component_playbooks:
    mov     qword [test_failures], 10
    jmp     .exit_fail
.fail_component_all:
    mov     qword [test_failures], 11
    jmp     .exit_fail
.fail_sev_info:
    mov     qword [test_failures], 12
    jmp     .exit_fail
.fail_sev_low:
    mov     qword [test_failures], 13
    jmp     .exit_fail
.fail_sev_medium:
    mov     qword [test_failures], 14
    jmp     .exit_fail
.fail_sev_high:
    mov     qword [test_failures], 15
    jmp     .exit_fail
.fail_sev_critical:
    mov     qword [test_failures], 16
    jmp     .exit_fail
.fail_status_new:
    mov     qword [test_failures], 17
    jmp     .exit_fail
.fail_status_triaged:
    mov     qword [test_failures], 18
    jmp     .exit_fail
.fail_status_contained:
    mov     qword [test_failures], 19
    jmp     .exit_fail
.fail_status_eradicated:
    mov     qword [test_failures], 20
    jmp     .exit_fail
.fail_status_recovered:
    mov     qword [test_failures], 21
    jmp     .exit_fail
.fail_status_closed:
    mov     qword [test_failures], 22
    jmp     .exit_fail
.fail_status_reopened:
    mov     qword [test_failures], 23
    jmp     .exit_fail
.fail_priority_low:
    mov     qword [test_failures], 24
    jmp     .exit_fail
.fail_priority_medium:
    mov     qword [test_failures], 25
    jmp     .exit_fail
.fail_priority_high:
    mov     qword [test_failures], 26
    jmp     .exit_fail
.fail_priority_critical:
    mov     qword [test_failures], 27
    jmp     .exit_fail
.fail_contain_isolate_host:
    mov     qword [test_failures], 28
    jmp     .exit_fail
.fail_contain_revoke_session:
    mov     qword [test_failures], 29
    jmp     .exit_fail
.fail_contain_block_indicator:
    mov     qword [test_failures], 30
    jmp     .exit_fail
.fail_contain_disable_account:
    mov     qword [test_failures], 31
    jmp     .exit_fail
.fail_contain_block_ip:
    mov     qword [test_failures], 32
    jmp     .exit_fail
.fail_contain_disable_service:
    mov     qword [test_failures], 33
    jmp     .exit_fail
.fail_erad_remove_malware:
    mov     qword [test_failures], 34
    jmp     .exit_fail
.fail_erad_disable_persistence:
    mov     qword [test_failures], 35
    jmp     .exit_fail
.fail_erad_patch_vuln:
    mov     qword [test_failures], 36
    jmp     .exit_fail
.fail_erad_reset_creds:
    mov     qword [test_failures], 37
    jmp     .exit_fail
.fail_erad_remove_backdoor:
    mov     qword [test_failures], 38
    jmp     .exit_fail
.fail_erad_rebuild_system:
    mov     qword [test_failures], 39
    jmp     .exit_fail
.fail_recover_restore:
    mov     qword [test_failures], 40
    jmp     .exit_fail
.fail_recover_validate:
    mov     qword [test_failures], 41
    jmp     .exit_fail
.fail_recover_monitor:
    mov     qword [test_failures], 42
    jmp     .exit_fail
.fail_recover_update:
    mov     qword [test_failures], 43
    jmp     .exit_fail
.fail_recover_review:
    mov     qword [test_failures], 44
    jmp     .exit_fail
.fail_playbook_phishing:
    mov     qword [test_failures], 45
    jmp     .exit_fail
.fail_playbook_malware:
    mov     qword [test_failures], 46
    jmp     .exit_fail
.fail_playbook_ransomware:
    mov     qword [test_failures], 47
    jmp     .exit_fail
.fail_playbook_ddos:
    mov     qword [test_failures], 48
    jmp     .exit_fail
.fail_playbook_insider:
    mov     qword [test_failures], 49
    jmp     .exit_fail
.fail_playbook_databreach:
    mov     qword [test_failures], 50
    jmp     .exit_fail
.fail_playbook_apt:
    mov     qword [test_failures], 51
    jmp     .exit_fail
.fail_err_success:
    mov     qword [test_failures], 52
    jmp     .exit_fail
.fail_err_general:
    mov     qword [test_failures], 53
    jmp     .exit_fail
.fail_err_not_init:
    mov     qword [test_failures], 54
    jmp     .exit_fail
.fail_err_invalid_arg:
    mov     qword [test_failures], 55
    jmp     .exit_fail
.fail_err_resource:
    mov     qword [test_failures], 56
    jmp     .exit_fail
.fail_err_access:
    mov     qword [test_failures], 57
    jmp     .exit_fail
.fail_err_not_found:
    mov     qword [test_failures], 58
    jmp     .exit_fail
.fail_err_containment:
    mov     qword [test_failures], 59
    jmp     .exit_fail
.fail_err_eradication:
    mov     qword [test_failures], 60
    jmp     .exit_fail
.fail_sla_critical:
    mov     qword [test_failures], 61
    jmp     .exit_fail
.fail_sla_high:
    mov     qword [test_failures], 62
    jmp     .exit_fail
.fail_sla_medium:
    mov     qword [test_failures], 63
    jmp     .exit_fail
.fail_sla_low:
    mov     qword [test_failures], 64
    jmp     .exit_fail

.exit_fail:
    mov     rax, 60              ; sys_exit
    mov     rdi, 1               ; status 1 (failure)
    syscall

%endif