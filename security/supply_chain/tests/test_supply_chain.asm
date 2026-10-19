%ifndef GUARD_SECURITY_SUPPLY_CHAIN_TESTS_TEST_SUPPLY_CHAIN_ASM
%define GUARD_SECURITY_SUPPLY_CHAIN_TESTS_TEST_SUPPLY_CHAIN_ASM

; =============================================================================
; File     : security/supply_chain/tests/test_supply_chain.asm
; Project  : Tattva OS
; Description: Supply chain comprehensive test - all components.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/supply_chain.inc"

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
    mov     eax, SUPPLY_CHAIN_VERSION_MAJOR
    cmp     eax, 1
    jne     .fail_version_major

    mov     eax, SUPPLY_CHAIN_VERSION_MINOR
    cmp     eax, 0
    jne     .fail_version_minor

    ; ------------------------------------------------------------
    ; Verify magic numbers
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_STATE_MAGIC
    cmp     eax, 0x53434841       ; "SCHA"
    jne     .fail_magic

    mov     eax, SUPPLY_CHAIN_STATE_MAGIC_FREED
    cmp     eax, 0xDEADBEEF
    jne     .fail_magic_freed

    ; ------------------------------------------------------------
    ; Verify component IDs
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_CORE
    cmp     eax, 1
    jne     .fail_component_core

    mov     eax, SUPPLY_CHAIN_SBOM
    cmp     eax, 2
    jne     .fail_component_sbom

    mov     eax, SUPPLY_CHAIN_PROVENANCE
    cmp     eax, 4
    jne     .fail_component_provenance

    mov     eax, SUPPLY_CHAIN_ATTESTATION
    cmp     eax, 8
    jne     .fail_component_attestation

    mov     eax, SUPPLY_CHAIN_VERIFICATION
    cmp     eax, 16
    jne     .fail_component_verification

    mov     eax, SUPPLY_CHAIN_ALL
    cmp     eax, 0x1F
    jne     .fail_component_all

    ; ------------------------------------------------------------
    ; Verify artifact types
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_ARTIFACT_SOURCE
    cmp     eax, 1
    jne     .fail_artifact_source

    mov     eax, SUPPLY_CHAIN_ARTIFACT_BINARY
    cmp     eax, 2
    jne     .fail_artifact_binary

    mov     eax, SUPPLY_CHAIN_ARTIFACT_LIBRARY
    cmp     eax, 3
    jne     .fail_artifact_library

    mov     eax, SUPPLY_CHAIN_ARTIFACT_CONTAINER
    cmp     eax, 4
    jne     .fail_artifact_container

    mov     eax, SUPPLY_CHAIN_ARTIFACT_CONFIG
    cmp     eax, 5
    jne     .fail_artifact_config

    mov     eax, SUPPLY_CHAIN_ARTIFACT_DOCUMENT
    cmp     eax, 6
    jne     .fail_artifact_document

    ; ------------------------------------------------------------
    ; Verify artifact states
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_ARTIFACT_UNKNOWN
    cmp     eax, 0
    jne     .fail_state_unknown

    mov     eax, SUPPLY_CHAIN_ARTIFACT_TRUSTED
    cmp     eax, 1
    jne     .fail_state_trusted

    mov     eax, SUPPLY_CHAIN_ARTIFACT_UNTRUSTED
    cmp     eax, 2
    jne     .fail_state_untrusted

    mov     eax, SUPPLY_CHAIN_ARTIFACT_REVOKED
    cmp     eax, 3
    jne     .fail_state_revoked

    mov     eax, SUPPLY_CHAIN_ARTIFACT_EXPIRED
    cmp     eax, 4
    jne     .fail_state_expired

    ; ------------------------------------------------------------
    ; Verify verification statuses
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_VERIFY_PENDING
    cmp     eax, 1
    jne     .fail_verify_pending

    mov     eax, SUPPLY_CHAIN_VERIFY_VERIFIED
    cmp     eax, 2
    jne     .fail_verify_verified

    mov     eax, SUPPLY_CHAIN_VERIFY_FAILED
    cmp     eax, 3
    jne     .fail_verify_failed

    mov     eax, SUPPLY_CHAIN_VERIFY_SKIPPED
    cmp     eax, 4
    jne     .fail_verify_skipped

    ; ------------------------------------------------------------
    ; Verify signer trust levels
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_TRUST_UNKNOWN
    cmp     eax, 0
    jne     .fail_trust_unknown

    mov     eax, SUPPLY_CHAIN_TRUST_LOW
    cmp     eax, 1
    jne     .fail_trust_low

    mov     eax, SUPPLY_CHAIN_TRUST_MEDIUM
    cmp     eax, 2
    jne     .fail_trust_medium

    mov     eax, SUPPLY_CHAIN_TRUST_HIGH
    cmp     eax, 3
    jne     .fail_trust_high

    mov     eax, SUPPLY_CHAIN_TRUST_ROOT
    cmp     eax, 4
    jne     .fail_trust_root

    ; ------------------------------------------------------------
    ; Verify error codes
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success

    mov     eax, SUPPLY_CHAIN_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general

    mov     eax, SUPPLY_CHAIN_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init

    mov     eax, SUPPLY_CHAIN_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg

    mov     eax, SUPPLY_CHAIN_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource

    mov     eax, SUPPLY_CHAIN_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access

    mov     eax, SUPPLY_CHAIN_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found

    mov     eax, SUPPLY_CHAIN_ERR_VERIFY_FAILED
    cmp     eax, 7
    jne     .fail_err_verify_failed

    mov     eax, SUPPLY_CHAIN_ERR_SIGNATURE
    cmp     eax, 8
    jne     .fail_err_signature

    mov     eax, SUPPLY_CHAIN_ERR_CERT_EXPIRED
    cmp     eax, 9
    jne     .fail_err_cert_expired

    ; ------------------------------------------------------------
    ; Verify SBOM formats
    ; ------------------------------------------------------------
    mov     eax, SUPPLY_CHAIN_SBOM_SPDX
    cmp     eax, 1
    jne     .fail_sbom_spdx

    mov     eax, SUPPLY_CHAIN_SBOM_CYCLONEDX
    cmp     eax, 2
    jne     .fail_sbom_cyclonedx

    mov     eax, SUPPLY_CHAIN_SBOM_SWID
    cmp     eax, 3
    jne     .fail_sbom_swid

    ; ------------------------------------------------------------
    ; Verify struc sizes are defined
    ; ------------------------------------------------------------
    mov     rax, supply_chain_state_base_t_size
    mov     rbx, supply_chain_artifact_t_size
    mov     rcx, supply_chain_sbom_t_size
    mov     rdx, supply_chain_provenance_t_size
    mov     rsi, supply_chain_attestation_t_size
    mov     r8, supply_chain_verification_t_size
    mov     r9, supply_chain_global_state_t_size

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
.fail_component_sbom:
    mov     qword [test_failures], 6
    jmp     .exit_fail
.fail_component_provenance:
    mov     qword [test_failures], 7
    jmp     .exit_fail
.fail_component_attestation:
    mov     qword [test_failures], 8
    jmp     .exit_fail
.fail_component_verification:
    mov     qword [test_failures], 9
    jmp     .exit_fail
.fail_component_all:
    mov     qword [test_failures], 10
    jmp     .exit_fail
.fail_artifact_source:
    mov     qword [test_failures], 11
    jmp     .exit_fail
.fail_artifact_binary:
    mov     qword [test_failures], 12
    jmp     .exit_fail
.fail_artifact_library:
    mov     qword [test_failures], 13
    jmp     .exit_fail
.fail_artifact_container:
    mov     qword [test_failures], 14
    jmp     .exit_fail
.fail_artifact_config:
    mov     qword [test_failures], 15
    jmp     .exit_fail
.fail_artifact_document:
    mov     qword [test_failures], 16
    jmp     .exit_fail
.fail_state_unknown:
    mov     qword [test_failures], 17
    jmp     .exit_fail
.fail_state_trusted:
    mov     qword [test_failures], 18
    jmp     .exit_fail
.fail_state_untrusted:
    mov     qword [test_failures], 19
    jmp     .exit_fail
.fail_state_revoked:
    mov     qword [test_failures], 20
    jmp     .exit_fail
.fail_state_expired:
    mov     qword [test_failures], 21
    jmp     .exit_fail
.fail_verify_pending:
    mov     qword [test_failures], 22
    jmp     .exit_fail
.fail_verify_verified:
    mov     qword [test_failures], 23
    jmp     .exit_fail
.fail_verify_failed:
    mov     qword [test_failures], 24
    jmp     .exit_fail
.fail_verify_skipped:
    mov     qword [test_failures], 25
    jmp     .exit_fail
.fail_trust_unknown:
    mov     qword [test_failures], 26
    jmp     .exit_fail
.fail_trust_low:
    mov     qword [test_failures], 27
    jmp     .exit_fail
.fail_trust_medium:
    mov     qword [test_failures], 28
    jmp     .exit_fail
.fail_trust_high:
    mov     qword [test_failures], 29
    jmp     .exit_fail
.fail_trust_root:
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
.fail_err_verify_failed:
    mov     qword [test_failures], 38
    jmp     .exit_fail
.fail_err_signature:
    mov     qword [test_failures], 39
    jmp     .exit_fail
.fail_err_cert_expired:
    mov     qword [test_failures], 40
    jmp     .exit_fail
.fail_sbom_spdx:
    mov     qword [test_failures], 41
    jmp     .exit_fail
.fail_sbom_cyclonedx:
    mov     qword [test_failures], 42
    jmp     .exit_fail
.fail_sbom_swid:
    mov     qword [test_failures], 43
    jmp     .exit_fail

.exit_fail:
    mov     rax, 60              ; sys_exit
    mov     rdi, 1               ; status 1 (failure)
    syscall

%endif