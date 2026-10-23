%ifndef GUARD_SECURITY_DIGITAL_FORENSICS_TESTS_TEST_DFIR_ASM
%define GUARD_SECURITY_DIGITAL_FORENSICS_TESTS_TEST_DFIR_ASM

; =============================================================================
; File     : security/digital_forensics/tests/test_dfir.asm
; Project  : Utkarsha OS
; Description: DFIR comprehensive test - all components.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/dfir.inc"

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
    mov     eax, DFIR_VERSION_MAJOR
    cmp     eax, 1
    jne     .fail_version_major

    mov     eax, DFIR_VERSION_MINOR
    cmp     eax, 0
    jne     .fail_version_minor

    ; ------------------------------------------------------------
    ; Verify magic numbers
    ; ------------------------------------------------------------
    mov     eax, DFIR_STATE_MAGIC
    cmp     eax, 0x44464952       ; "DFIR"
    jne     .fail_magic

    mov     eax, DFIR_STATE_MAGIC_FREED
    cmp     eax, 0xDEADBEEF
    jne     .fail_magic_freed

    ; ------------------------------------------------------------
    ; Verify component IDs
    ; ------------------------------------------------------------
    mov     eax, DFIR_CORE
    cmp     eax, 1
    jne     .fail_component_core

    mov     eax, DFIR_ACQUIRER
    cmp     eax, 2
    jne     .fail_component_acquirer

    mov     eax, DFIR_ANALYZER
    cmp     eax, 4
    jne     .fail_component_analyzer

    mov     eax, DFIR_CUSTODY
    cmp     eax, 8
    jne     .fail_component_custody

    mov     eax, DFIR_REPORTER
    cmp     eax, 16
    jne     .fail_component_reporter

    mov     eax, DFIR_ALL
    cmp     eax, 0x1F
    jne     .fail_component_all

    ; ------------------------------------------------------------
    ; Verify acquisition types
    ; ------------------------------------------------------------
    mov     eax, DFIR_ACQ_DISK
    cmp     eax, 1
    jne     .fail_acq_disk

    mov     eax, DFIR_ACQ_MEMORY
    cmp     eax, 2
    jne     .fail_acq_memory

    mov     eax, DFIR_ACQ_FILE
    cmp     eax, 3
    jne     .fail_acq_file

    mov     eax, DFIR_ACQ_NETWORK
    cmp     eax, 4
    jne     .fail_acq_network

    mov     eax, DFIR_ACQ_MOBILE
    cmp     eax, 5
    jne     .fail_acq_mobile

    ; ------------------------------------------------------------
    ; Verify evidence states
    ; ------------------------------------------------------------
    mov     eax, DFIR_EVIDENCE_ACQUIRED
    cmp     eax, 1
    jne     .fail_evidence_acquired

    mov     eax, DFIR_EVIDENCE_ANALYZED
    cmp     eax, 2
    jne     .fail_evidence_analyzed

    mov     eax, DFIR_EVIDENCE_REVIEWED
    cmp     eax, 3
    jne     .fail_evidence_reviewed

    mov     eax, DFIR_EVIDENCE_RELEASED
    cmp     eax, 4
    jne     .fail_evidence_released

    mov     eax, DFIR_EVIDENCE_DESTROYED
    cmp     eax, 5
    jne     .fail_evidence_destroyed

    ; ------------------------------------------------------------
    ; Verify verdicts
    ; ------------------------------------------------------------
    mov     eax, DFIR_VERDICT_CLEAN
    cmp     eax, 0
    jne     .fail_verdict_clean

    mov     eax, DFIR_VERDICT_SUSPICIOUS
    cmp     eax, 1
    jne     .fail_verdict_suspicious

    mov     eax, DFIR_VERDICT_MALICIOUS
    cmp     eax, 2
    jne     .fail_verdict_malicious

    mov     eax, DFIR_VERDICT_INCONCLUSIVE
    cmp     eax, 3
    jne     .fail_verdict_inconclusive

    ; ------------------------------------------------------------
    ; Verify custody actions
    ; ------------------------------------------------------------
    mov     eax, DFIR_CUSTODY_COLLECT
    cmp     eax, 1
    jne     .fail_custody_collect

    mov     eax, DFIR_CUSTODY_TRANSFER
    cmp     eax, 2
    jne     .fail_custody_transfer

    mov     eax, DFIR_CUSTODY_ACCESS
    cmp     eax, 3
    jne     .fail_custody_access

    mov     eax, DFIR_CUSTODY_RETURN
    cmp     eax, 4
    jne     .fail_custody_return

    mov     eax, DFIR_CUSTODY_DESTROY
    cmp     eax, 5
    jne     .fail_custody_destroy

    ; ------------------------------------------------------------
    ; Verify error codes
    ; ------------------------------------------------------------
    mov     eax, DFIR_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success

    mov     eax, DFIR_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general

    mov     eax, DFIR_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init

    mov     eax, DFIR_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg

    mov     eax, DFIR_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource

    mov     eax, DFIR_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access

    mov     eax, DFIR_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found

    mov     eax, DFIR_ERR_WRITE_BLOCKED
    cmp     eax, 7
    jne     .fail_err_write_blocked

    mov     eax, DFIR_ERR_HASH_MISMATCH
    cmp     eax, 8
    jne     .fail_err_hash_mismatch

    mov     eax, DFIR_ERR_CUSTODY_BREAK
    cmp     eax, 9
    jne     .fail_err_custody_break

    ; ------------------------------------------------------------
    ; Verify hash algorithms
    ; ------------------------------------------------------------
    mov     eax, DFIR_HASH_SHA256
    cmp     eax, 1
    jne     .fail_hash_sha256

    mov     eax, DFIR_HASH_SHA512
    cmp     eax, 2
    jne     .fail_hash_sha512

    mov     eax, DFIR_HASH_BLAKE3
    cmp     eax, 3
    jne     .fail_hash_blake3

    ; ------------------------------------------------------------
    ; Verify config defaults
    ; ------------------------------------------------------------
    mov     eax, DFIR_DEFAULT_WRITE_BLOCKED
    cmp     eax, 1
    jne     .fail_write_blocked

    mov     eax, DFIR_DEFAULT_HASH_ALGORITHM
    cmp     eax, 1
    jne     .fail_hash_alg_default

    ; ------------------------------------------------------------
    ; Verify struc sizes are defined
    ; ------------------------------------------------------------
    mov     rax, dfir_state_base_t_size
    mov     rbx, dfir_case_t_size
    mov     rcx, dfir_evidence_t_size
    mov     rdx, dfir_custody_t_size
    mov     rsi, dfir_analysis_t_size
    mov     r8, dfir_report_t_size
    mov     r9, dfir_global_state_t_size

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
.fail_component_acquirer:
    mov     qword [test_failures], 6
    jmp     .exit_fail
.fail_component_analyzer:
    mov     qword [test_failures], 7
    jmp     .exit_fail
.fail_component_custody:
    mov     qword [test_failures], 8
    jmp     .exit_fail
.fail_component_reporter:
    mov     qword [test_failures], 9
    jmp     .exit_fail
.fail_component_all:
    mov     qword [test_failures], 10
    jmp     .exit_fail
.fail_acq_disk:
    mov     qword [test_failures], 11
    jmp     .exit_fail
.fail_acq_memory:
    mov     qword [test_failures], 12
    jmp     .exit_fail
.fail_acq_file:
    mov     qword [test_failures], 13
    jmp     .exit_fail
.fail_acq_network:
    mov     qword [test_failures], 14
    jmp     .exit_fail
.fail_acq_mobile:
    mov     qword [test_failures], 15
    jmp     .exit_fail
.fail_evidence_acquired:
    mov     qword [test_failures], 16
    jmp     .exit_fail
.fail_evidence_analyzed:
    mov     qword [test_failures], 17
    jmp     .exit_fail
.fail_evidence_reviewed:
    mov     qword [test_failures], 18
    jmp     .exit_fail
.fail_evidence_released:
    mov     qword [test_failures], 19
    jmp     .exit_fail
.fail_evidence_destroyed:
    mov     qword [test_failures], 20
    jmp     .exit_fail
.fail_verdict_clean:
    mov     qword [test_failures], 21
    jmp     .exit_fail
.fail_verdict_suspicious:
    mov     qword [test_failures], 22
    jmp     .exit_fail
.fail_verdict_malicious:
    mov     qword [test_failures], 23
    jmp     .exit_fail
.fail_verdict_inconclusive:
    mov     qword [test_failures], 24
    jmp     .exit_fail
.fail_custody_collect:
    mov     qword [test_failures], 25
    jmp     .exit_fail
.fail_custody_transfer:
    mov     qword [test_failures], 26
    jmp     .exit_fail
.fail_custody_access:
    mov     qword [test_failures], 27
    jmp     .exit_fail
.fail_custody_return:
    mov     qword [test_failures], 28
    jmp     .exit_fail
.fail_custody_destroy:
    mov     qword [test_failures], 29
    jmp     .exit_fail
.fail_err_success:
    mov     qword [test_failures], 30
    jmp     .exit_fail
.fail_err_general:
    mov     qword [test_failures], 31
    jmp     .exit_fail
.fail_err_not_init:
    mov     qword [test_failures], 32
    jmp     .exit_fail
.fail_err_invalid_arg:
    mov     qword [test_failures], 33
    jmp     .exit_fail
.fail_err_resource:
    mov     qword [test_failures], 34
    jmp     .exit_fail
.fail_err_access:
    mov     qword [test_failures], 35
    jmp     .exit_fail
.fail_err_not_found:
    mov     qword [test_failures], 36
    jmp     .exit_fail
.fail_err_write_blocked:
    mov     qword [test_failures], 37
    jmp     .exit_fail
.fail_err_hash_mismatch:
    mov     qword [test_failures], 38
    jmp     .exit_fail
.fail_err_custody_break:
    mov     qword [test_failures], 39
    jmp     .exit_fail
.fail_hash_sha256:
    mov     qword [test_failures], 40
    jmp     .exit_fail
.fail_hash_sha512:
    mov     qword [test_failures], 41
    jmp     .exit_fail
.fail_hash_blake3:
    mov     qword [test_failures], 42
    jmp     .exit_fail
.fail_write_blocked:
    mov     qword [test_failures], 43
    jmp     .exit_fail
.fail_hash_alg_default:
    mov     qword [test_failures], 44
    jmp     .exit_fail

.exit_fail:
    mov     rax, 60              ; sys_exit
    mov     rdi, 1               ; status 1 (failure)
    syscall

%endif