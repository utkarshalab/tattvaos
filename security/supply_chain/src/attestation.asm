%ifndef GUARD_SECURITY_SUPPLY_CHAIN_ATTESTATION_ASM
%define GUARD_SECURITY_SUPPLY_CHAIN_ATTESTATION_ASM

; =============================================================================
; File     : security/supply_chain/src/attestation.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: signed attestations for dependencies/artifacts
; Status   : PREMIUM ENTERPRISE - skeleton with full API surface.
; =============================================================================

bits 64
DEFAULT REL

%include "include/supply_chain.inc"

section .bss
alignb 16
sc_attestation_state:      resb supply_chain_state_base_t_size
sc_attestation_head:       resq 1
sc_attestation_count:      resq 1

section .data
alignb 16
sc_attestation_version_str: db SUPPLY_CHAIN_VERSION_STR, 0

section .text

; =============================================================================
; sc_attestation_init - Initialize signed attestations
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global sc_attestation_init
sc_attestation_init:
    push    rbx
    mov     dword [sc_attestation_state + supply_chain_state_base_t.magic], SUPPLY_CHAIN_STATE_MAGIC
    mov     dword [sc_attestation_state + supply_chain_state_base_t.version], SUPPLY_CHAIN_VERSION_MAJOR
    mov     byte [sc_attestation_state + supply_chain_state_base_t.enabled], 1
    mov     qword [sc_attestation_head], 0
    mov     qword [sc_attestation_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; sc_attestation_shutdown - Shut down signed attestations
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global sc_attestation_shutdown
sc_attestation_shutdown:
    push    rbx
    mov     eax, [sc_attestation_state + supply_chain_state_base_t.magic]
    cmp     eax, SUPPLY_CHAIN_STATE_MAGIC
    jnz     .not_init
    mov     dword [sc_attestation_state + supply_chain_state_base_t.magic], SUPPLY_CHAIN_STATE_MAGIC_FREED
    mov     byte [sc_attestation_state + supply_chain_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; sc_attestation_status - Return current signed attestations status
; Input:  none
; Output: rax = status code
; =============================================================================
global sc_attestation_status
sc_attestation_status:
    mov     eax, [sc_attestation_state + supply_chain_state_base_t.magic]
    cmp     eax, SUPPLY_CHAIN_STATE_MAGIC
    jnz     .not_init
    mov     al, [sc_attestation_state + supply_chain_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_init:
    mov     eax, -2
    ret

; =============================================================================
; sc_attestation_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global sc_attestation_version
sc_attestation_version:
    mov     rax, sc_attestation_version_str
    ret

; STUB: sc_attestation_create - create attestation for an artifact
; STUB: sc_attestation_get - retrieve attestation by ID
; STUB: sc_attestation_list - list all attestations
; STUB: sc_attestation_verify - verify attestation signature
; STUB: sc_attestation_revoke - revoke attestation
; STUB: sc_attestation_get_stats - return attestation statistics
; STUB: sc_attestation_add_signer - add signer to attestation
; STUB: sc_attestation_remove_signer - remove signer from attestation
; STUB: sc_attestation_verify_chain - verify attestation chain
; STUB: sc_attestation_export - export attestation to file
; STUB: sc_attestation_import - import attestation from file
; STUB: sc_attestation_batch_verify - batch verify attestations

%endif