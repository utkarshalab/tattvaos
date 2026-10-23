%ifndef GUARD_SECURITY_SUPPLY_CHAIN_PROVENANCE_ASM
%define GUARD_SECURITY_SUPPLY_CHAIN_PROVENANCE_ASM

; =============================================================================
; File     : security/supply_chain/src/provenance.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: build-system attestation, signer tracking
; Status   : PREMIUM ENTERPRISE - skeleton with full API surface.
; =============================================================================

bits 64
DEFAULT REL

%include "include/supply_chain.inc"

section .bss
alignb 16
sc_provenance_state:      resb supply_chain_state_base_t_size
sc_provenance_head:       resq 1
sc_provenance_count:      resq 1

section .data
alignb 16
sc_provenance_version_str: db SUPPLY_CHAIN_VERSION_STR, 0

section .text

; =============================================================================
; sc_provenance_init - Initialize provenance tracking
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global sc_provenance_init
sc_provenance_init:
    push    rbx
    mov     dword [sc_provenance_state + supply_chain_state_base_t.magic], SUPPLY_CHAIN_STATE_MAGIC
    mov     dword [sc_provenance_state + supply_chain_state_base_t.version], SUPPLY_CHAIN_VERSION_MAJOR
    mov     byte [sc_provenance_state + supply_chain_state_base_t.enabled], 1
    mov     qword [sc_provenance_head], 0
    mov     qword [sc_provenance_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; sc_provenance_shutdown - Shut down provenance tracking
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global sc_provenance_shutdown
sc_provenance_shutdown:
    push    rbx
    mov     eax, [sc_provenance_state + supply_chain_state_base_t.magic]
    cmp     eax, SUPPLY_CHAIN_STATE_MAGIC
    jnz     .not_init
    mov     dword [sc_provenance_state + supply_chain_state_base_t.magic], SUPPLY_CHAIN_STATE_MAGIC_FREED
    mov     byte [sc_provenance_state + supply_chain_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; sc_provenance_status - Return current provenance tracking status
; Input:  none
; Output: rax = status code
; =============================================================================
global sc_provenance_status
sc_provenance_status:
    mov     eax, [sc_provenance_state + supply_chain_state_base_t.magic]
    cmp     eax, SUPPLY_CHAIN_STATE_MAGIC
    jnz     .not_init
    mov     al, [sc_provenance_state + supply_chain_state_base_t.enabled]
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
; sc_provenance_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global sc_provenance_version
sc_provenance_version:
    mov     rax, sc_provenance_version_str
    ret

; STUB: sc_provenance_record - record provenance for an artifact
; STUB: sc_provenance_get - retrieve provenance by artifact ID
; STUB: sc_provenance_list - list all provenance records
; STUB: sc_provenance_delete - delete provenance record
; STUB: sc_provenance_get_stats - return provenance statistics
; STUB: sc_provenance_add_link - add provenance link
; STUB: sc_provenance_remove_link - remove provenance link
; STUB: sc_provenance_trace_lineage - trace artifact lineage
; STUB: sc_provenance_verify_chain - verify provenance chain
; STUB: sc_provenance_export - export provenance to file
; STUB: sc_provenance_import - import provenance from file

%endif