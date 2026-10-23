%ifndef GUARD_SECURITY_THREAT_INTEL_THREAT_INTEL_ASM
%define GUARD_SECURITY_THREAT_INTEL_THREAT_INTEL_ASM

; =============================================================================
; File     : security/threat_intel/src/threat_intel.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Threat Intelligence - main dispatcher.
;              Ingests IOCs from feeds, correlates events against IOCs,
;              evaluates threat scoring, enriches IOCs, performs attribution,
;              creates playbooks, exports intel, and maintains threat state.
; Status   : PREMIUM ENTERPRISE SKELETON - full state machine, component
;              lifecycle, threat management, and data structures for 30
;              components. Logic bodies marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_global_state:  resb threat_intel_global_state_t_size   ; zero-initialized global state

section .data
alignb 16
threat_intel_version_str:   db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_init - Initialize Threat Intelligence subsystem
; Input:  none
; Output: rax = 0 on success, negative error code on failure
;         Initializes global state, loads config, registers components in
;         dependency order: store -> ingestor -> correlator -> scoring_engine
;         -> enrichment_engine -> false_positive_reducer -> attribution_engine
;         -> playbook_engine -> distribution_engine -> reputation_engine ->
;         geoip_engine -> darkweb_engine -> c2_engine -> malware_attribution ->
;         campaign_tracker -> lifecycle_manager -> feed_aggregator ->
;         dedup_engine -> stix_engine -> taxii_engine -> mitre_attack_engine ->
;         mitre_d3fend_engine -> kill_chain_engine -> diamond_model_engine ->
;         sigma_engine -> yara_engine -> threat_hunting_engine.
; Each component's init() must succeed before proceeding to the next.
; =============================================================================
global threat_intel_init
threat_intel_init:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Double-init guard: check magic
    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    ; Zero the global state structure
    xor     eax, eax
    mov     rcx, threat_intel_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, threat_intel_global_state
    rep     stosd

    ; Set magic and version
    mov     eax, THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_global_state + threat_intel_global_state_t.magic], eax
    mov     eax, (THREAT_INTEL_VERSION_MAJOR << 16) | THREAT_INTEL_VERSION_MINOR
    mov     [threat_intel_global_state + threat_intel_global_state_t.version], eax

    ; Set default configuration values
    mov     rax, THREAT_INTEL_DEFAULT_MAX_IOCS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_iocs], rax
    mov     rax, THREAT_INTEL_DEFAULT_MAX_FEEDS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_feeds], rax
    mov     rax, THREAT_INTEL_DEFAULT_MAX_FINDINGS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_findings], rax
    mov     rax, THREAT_INTEL_DEFAULT_MAX_CASES
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_cases], rax
    mov     rax, THREAT_INTEL_DEFAULT_MAX_PLAYBOOKS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_playbooks], rax
    mov     rax, THREAT_INTEL_DEFAULT_MAX_ACTIONS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_actions], rax
    mov     rax, THREAT_INTEL_DEFAULT_MAX_ALERTS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.max_alerts], rax
    mov     eax, THREAT_INTEL_DEFAULT_CONFIDENCE_THRESHOLD
    mov     dword [threat_intel_global_state + threat_intel_global_state_t.confidence_threshold], eax
    mov     rax, THREAT_INTEL_DEFAULT_IOC_TTL_SECONDS
    mov     qword [threat_intel_global_state + threat_intel_global_state_t.ioc_ttl], rax

    ; Default fail mode: CLOSED (secure)
    mov     dword [threat_intel_global_state + threat_intel_global_state_t.fail_mode], 0

    ; STUB: register components in dependency order:
    ;   store -> ingestor -> correlator -> scoring_engine ->
;     enrichment_engine -> false_positive_reducer -> attribution_engine ->
;     playbook_engine -> distribution_engine -> reputation_engine ->
;     geoip_engine -> darkweb_engine -> c2_engine -> malware_attribution ->
;     campaign_tracker -> lifecycle_manager -> feed_aggregator ->
;     dedup_engine -> stix_engine -> taxii_engine -> mitre_attack_engine ->
;     mitre_d3fend_engine -> kill_chain_engine -> diamond_model_engine ->
;     sigma_engine -> yara_engine -> threat_hunting_engine
    ; Each component's init() must succeed before proceeding to the next.

    mov     byte [threat_intel_global_state + threat_intel_state_base_t.enabled], 1
    xor     eax, eax             ; success
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_shutdown - Shut down Threat Intelligence
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_shutdown
threat_intel_shutdown:
    push    rbx

    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init

    mov     dword [threat_intel_global_state + threat_intel_global_state_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_global_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
.not_init:
    pop     rbx
    ret

; =============================================================================
; threat_intel_status - Return current Threat Intelligence status
; Input:  none
; Output: rax = status code (0 = enabled, nonzero = disabled/not initialized)
; =============================================================================
global threat_intel_status
threat_intel_status:
    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [threat_intel_global_state + threat_intel_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_initialized:
    mov     eax, -2
    ret

; =============================================================================
; threat_intel_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_version
threat_intel_version:
    mov     rax, threat_intel_version_str
    ret

; =============================================================================
; threat_intel_register_ingredient - Register an IOC in the store
; Input:  rdi = IOC pointer (ti_ioc_t*)
; Output: rax = IOC ID on success, negative error code on failure
; =============================================================================
global threat_intel_register_ingredient
threat_intel_register_ingredient:
    push    rbx
    push    r12

    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save IOC pointer

    ; STUB: validate IOC type field
    ; STUB: check for duplicate IOC
    ; STUB: assign IOC ID (increment counter)
    ; STUB: insert into IOC linked list
    ; STUB: set first_seen and last_seen timestamps
    ; STUB: increment total_iocs counter

    mov     rax, 1               ; STUB: return IOC ID 1
    jmp     .done

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, THREAT_INTEL_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_lookup - Look up an IOC in the store
; Input:  rdi = indicator pointer, rsi = indicator length,
;         rdx = IOC type (TI_IOC_TYPE_*)
; Output: rax = verdict (TI_VERDICT_*),
;         rbx = matched IOC ID,
;         rcx = confidence score
; =============================================================================
global threat_intel_lookup
threat_intel_lookup:
    push    rbx
    push    r12
    push    r13

    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save indicator pointer

    ; STUB: compute hash of indicator
    ; STUB: lookup in hash table
    ; STUB: on match, verify indicator equality (constant-time compare)
    ; STUB: on match, return verdict, IOC ID, confidence
    ; STUB: on no match, return TI_VERDICT_UNKNOWN

    mov     eax, TI_VERDICT_UNKNOWN
    xor     rbx, rbx
    xor     rcx, rcx
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
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_subscribe - Subscribe to an intel topic
; Input:  rdi = topic pointer, rsi = topic length
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_subscribe
threat_intel_subscribe:
    push    rbx
    push    r12

    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save topic pointer

    ; STUB: resolve exporter component
    ; STEP: call ti_exporter_subscribe(topic, topic_len)
    ; STEP: increment subscription count

    mov     rax, THREAT_INTEL_ERR_SUCCESS
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

; =============================================================================
; threat_intel_match - Correlate an event against IOCs
; Input:  rdi = event pointer, rsi = event length,
;         rdx = event type, rcx = source module ID
; Output: rax = number of matches,
;         rbx = highest severity,
;         rcx = recommended action
; =============================================================================
global threat_intel_match
threat_intel_match:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     eax, [threat_intel_global_state + threat_intel_global_state_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save event pointer

    ; STUB: resolve correlator component
    ; STEP: call ti_correlator_match_event(event, event_len, event_type, source)
    ; STEP: return match count, highest severity, recommended action

    xor     eax, eax
    xor     rbx, rbx
    xor     rcx, rcx
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

; STUB: threat_intel_rate_score - rate IOC score
; STUB: threat_intel_enrich_ioc - enrich IOC with external data
; STUB: threat_intel_check_fail_closed - check fail-closed mode
; STUB: threat_intel_export_report - export threat intel report
; STUB: threat_intel_get_stats - return threat intel statistics

%endif