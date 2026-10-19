%ifndef GUARD_SECURITY_THREAT_INTEL_DISTRIBUTION_ENGINE_ASM
%define GUARD_SECURITY_THREAT_INTEL_DISTRIBUTION_ENGINE_ASM

; =============================================================================
; File     : security/threat_intel/src/distribution_engine.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IOC distribution engine (share IOCs with peers)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_distribution_state:     resb threat_intel_state_base_t_size
threat_intel_distribution_head:      resq 1
threat_intel_distribution_count:     resq 1

section .data
alignb 16
threat_intel_distribution_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_distribution_init - Initialize IOC distribution engine
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_distribution_init
threat_intel_distribution_init:
    push    rbx
    mov     dword [threat_intel_distribution_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_distribution_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_distribution_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_distribution_head], 0
    mov     qword [threat_intel_distribution_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_distribution_shutdown - Shut down IOC distribution engine
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_distribution_shutdown
threat_intel_distribution_shutdown:
    push    rbx
    mov     eax, [threat_intel_distribution_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_distribution_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_distribution_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_distribution_status - Return current IOC distribution engine status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_distribution_status
threat_intel_distribution_status:
    mov     eax, [threat_intel_distribution_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_distribution_state + threat_intel_state_base_t.enabled]
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
; threat_intel_distribution_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_distribution_version
threat_intel_distribution_version:
    mov     rax, threat_intel_distribution_version_str
    ret

; =============================================================================
; threat_intel_distribution_share_ioc - Share IOC with peer
; Input:  rdi = IOC ID, rsi = peer ID pointer,
;         rdx = peer ID length
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_distribution_share_ioc
threat_intel_distribution_share_ioc:
    push    rbx
    push    r12

    mov     eax, [threat_intel_distribution_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save IOC ID

    ; STUB: validate IOC ID exists
    ; STEP: serialize IOC to sharing format (STIX/TAXII/JSON)
    ; STEP: sign the serialized IOC with exporter key
    ; STEP: transmit to peer via authenticated channel
    ; STEP: update distribution statistics

    xor     eax, eax
    jmp     .done

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, THREAT_INTEL_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: threat_intel_distribution_get - retrieve distribution by ID
; STUB: threat_intel_distribution_list - list all distributions
; STUB: threat_intel_distribution_delete - delete distribution record
; STUB: threat_intel_distribution_get_stats - return distribution statistics

%endif