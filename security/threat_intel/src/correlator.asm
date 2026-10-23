%ifndef GUARD_SECURITY_THREAT_INTEL_CORRELATOR_ASM
%define GUARD_SECURITY_THREAT_INTEL_CORRELATOR_ASM

; =============================================================================
; File     : security/threat_intel/src/correlator.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IOC correlator (match events, scoring)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_correlator_state:     resb threat_intel_state_base_t_size
threat_intel_correlator_match_head: resq 1
threat_intel_correlator_match_count: resq 1

section .data
alignb 16
threat_intel_correlator_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_correlator_init - Initialize IOC correlator
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_correlator_init
threat_intel_correlator_init:
    push    rbx
    mov     dword [threat_intel_correlator_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_correlator_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_correlator_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_correlator_match_head], 0
    mov     qword [threat_intel_correlator_match_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_correlator_shutdown - Shut down IOC correlator
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_correlator_shutdown
threat_intel_correlator_shutdown:
    push    rbx
    mov     eax, [threat_intel_correlator_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_correlator_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_correlator_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_correlator_status - Return current IOC correlator status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_correlator_status
threat_intel_correlator_status:
    mov     eax, [threat_intel_correlator_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_correlator_state + threat_intel_state_base_t.enabled]
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
; threat_intel_correlator_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_correlator_version
threat_intel_correlator_version:
    mov     rax, threat_intel_correlator_version_str
    ret

; =============================================================================
; threat_intel_correlator_match_event - Match an event against stored IOCs
; Input:  rdi = event pointer, rsi = event length,
;         rdx = event type, rcx = source module ID
; Output: rax = number of matches,
;         rbx = highest severity,
;         rcx = recommended action (TI_ACTION_*)
; =============================================================================
global threat_intel_correlator_match_event
threat_intel_correlator_match_event:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     eax, [threat_intel_correlator_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save event pointer

    ; STEP 1: extract indicators from event (IPs, domains, hashes, URLs, etc.)
    ; STEP 2: for each extracted indicator:
    ;       - call threat_intel_lookup_ioc() to check against store
    ;       - if match found, create ti_match_result_t record
    ;       - track highest severity and recommended action
    ; STEP 3: store match results in match list
    ; STEP 4: increment total_alerts counter

    xor     eax, eax               ; STUB: no matches found
    xor     rbx, rbx               ; no severity
    xor     rcx, rcx               ; no action
    jmp     .done

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    xor     rbx, rbx
    xor     rcx, rcx
    jmp     .done
.err_invalid_arg:
    mov     rax, THREAT_INTEL_ERR_INVALID_ARG
    xor     rbx, rbx
    xor     rcx, rcx
    jmp     .done

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_correlator_score_ioc - Compute confidence score for an IOC
; Input:  rdi = IOC ID, rsi = evidence count, rdx = source count
; Output: rax = confidence score (0-100)
; =============================================================================
global threat_intel_correlator_score_ioc
threat_intel_correlator_score_ioc:
    push    rbx

    mov     eax, [threat_intel_correlator_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: load IOC from store by ID
    ; STEP: factor in evidence count, source diversity, feed reputation
    ; STEP: apply decay based on age of IOC
    ; STEP: return confidence score (0-100)

    mov     eax, 50               ; STUB: default medium confidence
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; =============================================================================
; threat_intel_correlator_update_score - Update IOC score based on new evidence
; Input:  rdi = IOC ID, rsi = new evidence pointer, rdx = evidence length
; Output: rax = updated confidence score (0-100)
; =============================================================================
global threat_intel_correlator_update_score
threat_intel_correlator_update_score:
    push    rbx

    mov     eax, [threat_intel_correlator_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: load IOC from store by ID
    ; STEP: analyze new evidence for corroboration or contradiction
    ; STEP: adjust confidence score upward or downward
    ; STEP: persist updated score to store
    ; STEP: return updated score

    mov     eax, 50               ; STUB: default medium confidence
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: threat_intel_correlator_get_matches - retrieve all match results
; STUB: threat_intel_correlator_clear_matches - clear match result list
; STUB: threat_intel_correlator_cluster - cluster related IOCs into campaigns
; STUB: threat_intel_correlator_attribution - attribute IOCs to threat actors
; STUB: threat_intel_correlator_timeline - build timeline of IOC activity
; STUB: threat_intel_correlator_export_matches - export match results to SIEM

%endif