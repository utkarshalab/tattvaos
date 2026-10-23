%ifndef GUARD_SECURITY_THREAT_INTEL_ENRICHMENT_ENGINE_ASM
%define GUARD_SECURITY_THREAT_INTEL_ENRICHMENT_ENGINE_ASM

; =============================================================================
; File     : security/threat_intel/src/enrichment_engine.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IOC enrichment engine (enrich IOCs with context data)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_enrichment_state:     resb threat_intel_state_base_t_size
threat_intel_enrichment_head:      resq 1
threat_intel_enrichment_count:     resq 1

section .data
alignb 16
threat_intel_enrichment_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_enrichment_init - Initialize IOC enrichment engine
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_enrichment_init
threat_intel_enrichment_init:
    push    rbx
    mov     dword [threat_intel_enrichment_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_enrichment_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_enrichment_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_enrichment_head], 0
    mov     qword [threat_intel_enrichment_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_enrichment_shutdown - Shut down IOC enrichment engine
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_enrichment_shutdown
threat_intel_enrichment_shutdown:
    push    rbx
    mov     eax, [threat_intel_enrichment_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_enrichment_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_enrichment_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_enrichment_status - Return current IOC enrichment engine status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_enrichment_status
threat_intel_enrichment_status:
    mov     eax, [threat_intel_enrichment_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_enrichment_state + threat_intel_state_base_t.enabled]
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
; threat_intel_enrichment_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_enrichment_version
threat_intel_enrichment_version:
    mov     rax, threat_intel_enrichment_version_str
    ret

; =============================================================================
; threat_intel_enrichment_enrich_ioc - Enrich IOC with external data
; Input:  rdi = IOC ID, rsi = external data pointer,
;         rdx = external data length
; Output: rax = updated IOC ID on success, negative error code on failure
; =============================================================================
global threat_intel_enrichment_enrich_ioc
threat_intel_enrichment_enrich_ioc:
    push    rbx
    push    r12

    mov     eax, [threat_intel_enrichment_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save IOC ID

    ; STUB: load IOC from store by ID
    ; STEP: query external enrichment sources
    ; STEP: enrich IOC with context data
    ; STEP: store enriched IOC back to store
    ; STEP: increment enrichment counter

    mov     rax, 1               ; STUB: return IOC ID 1
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

; STUB: threat_intel_enrichment_get_stats - return enrichment statistics
; STUB: threat_intel_enrichment_list_enriched - list all enriched IOCs
; STUB: threat_intel_enrichment_refresh - refresh enrichment for all IOCs
; STUB: threat_intel_enrichment_get_by_source - get IOCs by enrichment source

%endif