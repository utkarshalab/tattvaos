%ifndef GUARD_SECURITY_SUPPLY_CHAIN_SBOM_ASM
%define GUARD_SECURITY_SUPPLY_CHAIN_SBOM_ASM

; =============================================================================
; File     : security/supply_chain/src/sbom.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: SBOM generation and storage
; Status   : PREMIUM ENTERPRISE - skeleton with full API surface.
; =============================================================================

bits 64
DEFAULT REL

%include "include/supply_chain.inc"

section .bss
alignb 16
sc_sbom_state:        resb supply_chain_state_base_t_size
sc_sbom_head:         resq 1
sc_sbom_count:        resq 1

section .data
alignb 16
sc_sbom_version_str:  db SUPPLY_CHAIN_VERSION_STR, 0

section .text

; =============================================================================
; sc_sbom_init - Initialize SBOM generation and storage
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global sc_sbom_init
sc_sbom_init:
    push    rbx
    mov     dword [sc_sbom_state + supply_chain_state_base_t.magic], SUPPLY_CHAIN_STATE_MAGIC
    mov     dword [sc_sbom_state + supply_chain_state_base_t.version], SUPPLY_CHAIN_VERSION_MAJOR
    mov     byte [sc_sbom_state + supply_chain_state_base_t.enabled], 1
    mov     qword [sc_sbom_head], 0
    mov     qword [sc_sbom_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; sc_sbom_shutdown - Shut down SBOM generation and storage
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global sc_sbom_shutdown
sc_sbom_shutdown:
    push    rbx
    mov     eax, [sc_sbom_state + supply_chain_state_base_t.magic]
    cmp     eax, SUPPLY_CHAIN_STATE_MAGIC
    jnz     .not_init
    mov     dword [sc_sbom_state + supply_chain_state_base_t.magic], SUPPLY_CHAIN_STATE_MAGIC_FREED
    mov     byte [sc_sbom_state + supply_chain_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; sc_sbom_status - Return current SBOM generation and storage status
; Input:  none
; Output: rax = status code
; =============================================================================
global sc_sbom_status
sc_sbom_status:
    mov     eax, [sc_sbom_state + supply_chain_state_base_t.magic]
    cmp     eax, SUPPLY_CHAIN_STATE_MAGIC
    jnz     .not_init
    mov     al, [sc_sbom_state + supply_chain_state_base_t.enabled]
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
; sc_sbom_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global sc_sbom_version
sc_sbom_version:
    mov     rax, sc_sbom_version_str
    ret

; STUB: sc_sbom_generate - generate SBOM for an artifact
; STUB: sc_sbom_export - export SBOM to file
; STUB: sc_sbom_import - import SBOM from file
; STUB: sc_sbom_get - retrieve SBOM by ID
; STUB: sc_sbom_list - list all SBOMs
; STUB: sc_sbom_delete - delete SBOM
; STUB: sc_sbom_get_stats - return SBOM statistics
; STUB: sc_sbom_add_component - add component to SBOM
; STUB: sc_sbom_remove_component - remove component from SBOM
; STUB: sc_sbom_verify_signature - verify SBOM signature
; STUB: sc_sbom_compare - compare two SBOMs
; STUB: sc_sbom_diff - compute differences between SBOMs
; STUB: sc_sbom_validate - validate SBOM structure
; STUB: sc_sbom_convert - convert SBOM between formats

%endif