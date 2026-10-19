%ifndef GUARD_SECURITY_SOAR_INC_SOAR_INC
%define GUARD_SECURITY_SOAR_INC_SOAR_INC

; =============================================================================
; File     : security/soar/include/soar.inc
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Security Orchestration, Automation & Response - master schema
;              header. Constants, structures, macros, and error codes shared by
;              every SOAR component.
;
; DESIGN INVARIANT:
;   SOAR is the orchestration layer. It receives alerts from IDS/IPS/malwarescan,
;   evaluates playbooks, and executes automated response actions (block IP,
;   quarantine host, revoke session, etc.).
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE - full SOAR feature set including playbook engine,
;         alert ingestion, case management, automation, and integrations defined.
; =============================================================================

%ifndef SOAR_INC
%define SOAR_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define SOAR_VERSION_MAJOR   2
%define SOAR_VERSION_MINOR   0
%define SOAR_VERSION_PATCH   0
%define SOAR_VERSION_STR     "2.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define SOAR_STATE_MAGIC             0x534f4152   ; "SOAR"
%define SOAR_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define SOAR_CORE_ENGINE            (1 << 0)
%define SOAR_PLAYBOOK_ENGINE        (1 << 1)
%define SOAR_ALERT_INGESTOR         (1 << 2)
%define SOAR_ACTION_ENGINE          (1 << 3)
%define SOAR_PLAYBOOK_COMPILER      (1 << 4)
%define SOAR_CASE_MANAGER           (1 << 5)
%define SOAR_AUTOMATION_ENGINE      (1 << 6)
%define SOAR_INTEGRATION_ENGINE     (1 << 7)
%define SOAR_SCHEDULER              (1 << 8)
%define SOAR_METRICS_ENGINE         (1 << 9)
%define SOAR_THREAT_INTEL_INTEGRATION (1 << 10)
%define SOAR_VULNERABILITY_INTEGRATION (1 << 11)
%define SOAR_ASSET_INVENTORY           (1 << 12)
%define SOAR_RISK_SCORING_ENGINE       (1 << 13)
%define SOAR_NOTIFICATION_ENGINE       (1 << 14)
%define SOAR_EVIDENCE_COLLECTOR        (1 << 15)
%define SOAR_REMEDIATION_ENGINE        (1 << 16)
%define SOAR_COMPLIANCE_REPORTER       (1 << 17)
%define SOAR_FORENSIC_INTEGRATOR       (1 << 18)
%define SOAR_MALWARE_ANALYZER          (1 << 19)
%define SOAR_USER_BEHAVIOR_ANALYTICS   (1 << 20)
%define SOAR_DECOY_MANAGER             (1 << 21)
%define SOAR_THREAT_HUNTING_INTEGRATION (1 << 22)
%define SOAR_INCIDENT_TIMELINE_BUILDER (1 << 23)
%define SOAR_PLAYBOOK_TESTER           (1 << 24)
%define SOAR_ASSET_CRITICALITY_SCORER  (1 << 25)
%define SOAR_ALL                       0x3FFFFFF

; -----------------------------------------------------------------------------
; SOAR actions
; -----------------------------------------------------------------------------
%define SOAR_ACTION_ALERT           0      ; create alert
%define SOAR_ACTION_BLOCK_IP        1      ; block IP address
%define SOAR_ACTION_QUARANTINE_HOST 2      ; quarantine host
%define SOAR_ACTION_REVOKE_SESSION  3      ; revoke session
%define SOAR_ACTION_CREATE_TICKET   4      ; create ticket in ticketing system
%define SOAR_ACTION_SEND_NOTIFICATION 5    ; send notification
%define SOAR_ACTION_ISOLATE_HOST    6      ; isolate host from network
%define SOAR_ACTION_COLLECT_EVIDENCE 7     ; collect forensic evidence
%define SOAR_ACTION_UPDATE_POLICY   8      ; update firewall/IPS/WAF policy

; -----------------------------------------------------------------------------
; SOAR verdicts
; -----------------------------------------------------------------------------
%define SOAR_VERDICT_ALLOW          0
%define SOAR_VERDICT_BLOCK          -1
%define SOAR_VERDICT_QUARANTINE     -2
%define SOAR_VERDICT_ERROR          -100

; -----------------------------------------------------------------------------
; Fail modes
; -----------------------------------------------------------------------------
%define SOAR_FAIL_CLOSED             0
%define SOAR_FAIL_OPEN               1

; -----------------------------------------------------------------------------
; Enforcement reasons
; -----------------------------------------------------------------------------
%define SOAR_REASON_NONE             0
%define SOAR_REASON_POLICY_VIOLATION 10
%define SOAR_REASON_INVALID_REQUEST  11
%define SOAR_REASON_RATE_LIMIT       12
%define SOAR_REASON_GEOIP_BLOCKED    13

; -----------------------------------------------------------------------------
; Action statuses
; -----------------------------------------------------------------------------
%define SOAR_ACTION_PENDING         0
%define SOAR_ACTION_IN_PROGRESS     1
%define SOAR_ACTION_COMPLETED       2
%define SOAR_ACTION_FAILED          3
%define SOAR_ACTION_SKIPPED         4

; -----------------------------------------------------------------------------
; Case statuses
; -----------------------------------------------------------------------------
%define SOAR_CASE_OPEN              0
%define SOAR_CASE_INVESTIGATING     1
%define SOAR_CASE_RESOLVED          2
%define SOAR_CASE_CLOSED            3
%define SOAR_CASE_ESCALATED         4

; -----------------------------------------------------------------------------
; Playbook types
; -----------------------------------------------------------------------------
%define SOAR_PLAYBOOK_MANUAL        0
%define SOAR_PLAYBOOK_AUTOMATED     1
%define SOAR_PLAYBOOK_HYBRID        2

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define SOAR_DEFAULT_MAX_RULES          10000
%define SOAR_DEFAULT_MAX_CASES          50000
%define SOAR_DEFAULT_MAX_ALERTS         100000
%define SOAR_DEFAULT_MAX_ACTIONS        100000
%define SOAR_DEFAULT_MAX_PLAYBOOKS      1000
%define SOAR_DEFAULT_MAX_ACTIONS_PER_PLAYBOOK 50
%define SOAR_DEFAULT_DEFAULT_TIMEOUT_MS 300000   ; 5 minutes

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro SOAR_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro SOAR_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define SOAR_LIST_INIT(head)  head

%macro SOAR_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro SOAR_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Action execution macro
; -----------------------------------------------------------------------------
%macro SOAR_EXECUTE_ACTION 5
    ; %1=action_type, %2=target, %3=parameters, %4=timeout_ms, %5=callback
    ; STUB: execute action through enforcer component
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro SOAR_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc soar_state_base_t
    .magic:         resd 1      ; SOAR_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_events:  resq 1      ; total events processed
    .stats_actions: resq 1      ; total actions executed
    .stats_cases:   resq 1      ; total cases created
endstruc

; -----------------------------------------------------------------------------
; Enforcement/action context (input to soar_execute)
; -----------------------------------------------------------------------------
struc soar_event_ctx_t
    .timestamp_ns:  resq 1      ; event timestamp
    .source_module: resd 1      ; 1=ids, 2=ips, 3=malwarescan, 4=waf
    .alert_type:    resd 1
    .src_ip:        resd 1
    .dst_ip:        resd 1
    .src_port:      resd 1
    .dst_port:      resd 1
    .protocol:      resd 1
    .severity:      resd 1
    .threat_score:  resd 1      ; 0-100
    .context_ptr:   resq 1      ; opaque context blob
    .context_size:  resd 1
    .session_id:    resq 1      ; associated session
endstruc

; -----------------------------------------------------------------------------
; Action result (output from soar_execute_action)
; -----------------------------------------------------------------------------
struc soar_action_result_t
    .action_type:   resd 1
    .status:        resd 1      ; SOAR_ACTION_*
    .target:        resq 1      ; target identifier
    .duration_ms:   resq 1
    .error_code:    resd 1
    .pad:           resd 3
    .executed_ns:   resq 1
endstruc

; -----------------------------------------------------------------------------
; Playbook rule
; -----------------------------------------------------------------------------
struc soar_rule_t
    .rule_id:       resq 1
    .rule_name:     resb 128
    .rule_type:     resd 1      ; SOAR_PLAYBOOK_*
    .trigger:       resq 1      ; trigger condition pointer
    .trigger_len:   resd 1
    .action_count:  resd 1
    .action_list:   resq 1      ; array of action IDs
    .priority:      resd 1
    .enabled:       resb 1
    .pad:           resb 3
    .hit_count:     resq 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Case/incident record
; -----------------------------------------------------------------------------
struc soar_case_t
    .case_id:       resq 1
    .title:         resb 256
    .severity:      resd 1
    .status:        resd 1      ; SOAR_CASE_*
    .src_ip:        resd 1
    .dst_ip:        resd 1
    .alert_count:   resq 1
    .action_count:  resq 1
    .created_ns:    resq 1
    .updated_ns:    resq 1
    .resolved_ns:   resq 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Action record
; -----------------------------------------------------------------------------
struc soar_action_t
    .action_id:     resq 1
    .case_id:       resq 1
    .action_type:   resd 1
    .status:        resd 1
    .target:        resq 1
    .created_ns:    resq 1
    .completed_ns:  resq 1
    .error_code:    resd 1
    .pad:           resb 3
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Trigger condition
; -----------------------------------------------------------------------------
struc soar_trigger_t
    .trigger_id:    resq 1
    .trigger_type:  resd 1      ; 1=alert_type, 2=severity, 3=src_ip, 4=pattern
    .pattern_ptr:   resq 1
    .pattern_len:   resd 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Global SOAR state
; -----------------------------------------------------------------------------
struc soar_global_state_t
    .magic:             resd 1
    .version:           resd 1
    .enabled:           resb 1
    .fail_mode:         resb 1      ; SOAR_FAIL_CLOSED or SOAR_FAIL_OPEN
    .pad:               resb 2
    .components:        resd 1      ; bitmask of initialized components
    .spinlock:          resq 1
    .max_rules:         resq 1
    .max_cases:         resq 1
    .max_alerts:        resq 1
    .max_actions:       resq 1
    .default_timeout_ms:resq 1
    .total_events:      resq 1
    .total_actions:     resq 1
    .total_cases:       resq 1
    .total_requests:    resq 1
    .core_state:        resq 1
    .playbook_state:    resq 1
    .alert_state:       resq 1
    .action_state:      resq 1
    .case_state:        resq 1
    .automation_state:  resq 1
    .integration_state: resq 1
    .scheduler_state:   resq 1
    .metrics_state:     resq 1
    .threat_intel_state:        resq 1
    .vulnerability_state:       resq 1
    .asset_state:               resq 1
    .risk_scoring_state:        resq 1
    .notification_state:        resq 1
    .evidence_state:            resq 1
    .remediation_state:         resq 1
    .compliance_state:          resq 1
    .forensic_state:            resq 1
    .malware_state:             resq 1
    .uba_state:                 resq 1
    .decoy_state:               resq 1
    .threat_hunting_state:      resq 1
    .timeline_state:            resq 1
    .playbook_tester_state:     resq 1
    .asset_criticality_state:   resq 1
endstruc

; -----------------------------------------------------------------------------
; Extern declarations (cross-component references)
; -----------------------------------------------------------------------------


















%endif ; SOAR_INC
%endif ; GUARD_SECURITY_SOAR_INC_SOAR_INC
