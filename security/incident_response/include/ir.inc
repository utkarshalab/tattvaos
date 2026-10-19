%ifndef GUARD_SECURITY_INCIDENT_RESPONSE_IR_INC
%define GUARD_SECURITY_INCIDENT_RESPONSE_IR_INC

; =============================================================================
; File     : security/incident_response/include/ir.inc
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Incident Response - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              IR component (core, triage, containment, eradication, recovery,
;              playbooks).
;
; DESIGN INVARIANT:
;   Incident Response follows a structured lifecycle: triage, contain,
;   eradicate, recover. Every incident is assigned a severity, tracked through
;   defined phases, and closed only after post-incident review. Response
;   actions are fail-closed: if containment cannot be verified, the incident
;   remains open and escalated.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE SKELETON - full feature set including incident
;         lifecycle management, containment actions, eradication procedures,
;         recovery workflows, and playbook execution defined.
; =============================================================================

%ifndef IR_INC
%define IR_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define IR_VERSION_MAJOR   1
%define IR_VERSION_MINOR   0
%define IR_VERSION_PATCH   0
%define IR_VERSION_STR     "1.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define IR_STATE_MAGIC             0x49525350   ; "IRSP"
%define IR_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define IR_CORE          (1 << 0)
%define IR_TRIAGE        (1 << 1)
%define IR_CONTAINMENT   (1 << 2)
%define IR_ERADICATION   (1 << 3)
%define IR_RECOVERY      (1 << 4)
%define IR_PLAYBOOKS     (1 << 5)
%define IR_ALL           0x3F

; -----------------------------------------------------------------------------
; Incident severity
; -----------------------------------------------------------------------------
%define IR_SEV_INFO      1
%define IR_SEV_LOW       2
%define IR_SEV_MEDIUM    3
%define IR_SEV_HIGH      4
%define IR_SEV_CRITICAL  5

; -----------------------------------------------------------------------------
; Incident status
; -----------------------------------------------------------------------------
%define IR_STATUS_NEW           1
%define IR_STATUS_TRIAGED       2
%define IR_STATUS_CONTAINED     3
%define IR_STATUS_ERADICATED    4
%define IR_STATUS_RECOVERED     5
%define IR_STATUS_CLOSED        6
%define IR_STATUS_REOPENED      7

; -----------------------------------------------------------------------------
; Incident priority
; -----------------------------------------------------------------------------
%define IR_PRIORITY_LOW     1
%define IR_PRIORITY_MEDIUM  2
%define IR_PRIORITY_HIGH    3
%define IR_PRIORITY_CRITICAL 4

; -----------------------------------------------------------------------------
; Containment actions
; -----------------------------------------------------------------------------
%define IR_CONTAIN_ISOLATE_HOST      1
%define IR_CONTAIN_REVOKE_SESSION    2
%define IR_CONTAIN_BLOCK_INDICATOR   3
%define IR_CONTAIN_DISABLE_ACCOUNT   4
%define IR_CONTAIN_BLOCK_IP          5
%define IR_CONTAIN_DISABLE_SERVICE   6

; -----------------------------------------------------------------------------
; Eradication actions
; -----------------------------------------------------------------------------
%define IR_ERAD_REMOVE_MALWARE       1
%define IR_ERAD_DISABLE_PERSISTENCE  2
%define IR_ERAD_PATCH_VULNERABILITY  3
%define IR_ERAD_RESET_CREDENTIALS    4
%define IR_ERAD_REMOVE_BACKDOOR      5
%define IR_ERAD_REBUILD_SYSTEM       6

; -----------------------------------------------------------------------------
; Recovery actions
; -----------------------------------------------------------------------------
%define IR_RECOVER_RESTORE_BACKUP    1
%define IR_RECOVER_VALIDATE_INTEGRITY 2
%define IR_RECOVER_MONITOR_ACTIVITY   3
%define IR_RECOVER_UPDATE_DETECTION   4
%define IR_RECOVER_CONDUCT_REVIEW     5

; -----------------------------------------------------------------------------
; Playbook types
; -----------------------------------------------------------------------------
%define IR_PLAYBOOK_PHISHING      1
%define IR_PLAYBOOK_MALWARE       2
%define IR_PLAYBOOK_RANSOMWARE    3
%define IR_PLAYBOOK_DDoS          4
%define IR_PLAYBOOK_INSIDER_THREAT 5
%define IR_PLAYBOOK_DATA_BREACH   6
%define IR_PLAYBOOK_APT           7

; -----------------------------------------------------------------------------
; Error codes
; -----------------------------------------------------------------------------
%define IR_ERR_SUCCESS        0
%define IR_ERR_GENERAL        1
%define IR_ERR_NOT_INIT       2
%define IR_ERR_INVALID_ARG    3
%define IR_ERR_RESOURCE       4
%define IR_ERR_ACCESS         5
%define IR_ERR_NOT_FOUND      6
%define IR_ERR_CONTAINMENT    7
%define IR_ERR_ERADICATION    8

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define IR_DEFAULT_MAX_INCIDENTS      100000
%define IR_DEFAULT_MAX_PLAYBOOKS      1000
%define IR_DEFAULT_SLA_CRITICAL_MIN   15
%define IR_DEFAULT_SLA_HIGH_MIN       60
%define IR_DEFAULT_SLA_MEDIUM_MIN     240
%define IR_DEFAULT_SLA_LOW_MIN        1440

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro IR_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro IR_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define IR_LIST_INIT(head)  head

%macro IR_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro IR_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro IR_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc ir_state_base_t
    .magic:         resd 1      ; IR_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_events:  resq 1      ; total events processed
    .stats_actions: resq 1      ; total actions executed
    .stats_errors:  resq 1      ; total errors logged
endstruc

; -----------------------------------------------------------------------------
; Incident record
; -----------------------------------------------------------------------------
struc ir_incident_t
    .incident_id:   resq 1      ; unique incident identifier
    .title:         resb 256    ; NUL-terminated incident title
    .severity:      resd 1      ; IR_SEV_*
    .priority:      resd 1      ; IR_PRIORITY_*
    .status:        resd 1      ; IR_STATUS_*
    .source_ip:     resd 1      ; source IP address
    .dest_ip:       resd 1      ; destination IP address
    .created_ns:    resq 1      ; incident creation timestamp
    .triaged_ns:    resq 1      ; triage completion timestamp
    .contained_ns:  resq 1      ; containment completion timestamp
    .eradicated_ns: resq 1      ; eradication completion timestamp
    .recovered_ns:  resq 1      ; recovery completion timestamp
    .closed_ns:     resq 1      ; incident closure timestamp
    .assigned_to:   resb 128    ; NUL-terminated assigned analyst
    .description:   resb 1024   ; NUL-terminated incident description
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Containment action record
; -----------------------------------------------------------------------------
struc ir_containment_t
    .action_id:     resq 1      ; unique action identifier
    .incident_id:   resq 1      ; associated incident identifier
    .action_type:   resd 1      ; IR_CONTAIN_*
    .target:        resb 256    ; NUL-terminated containment target
    .status:        resd 1      ; action status
    .executed_ns:   resq 1      ; execution timestamp
    .verified_ns:   resq 1      ; verification timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Eradication action record
; -----------------------------------------------------------------------------
struc ir_eradication_t
    .action_id:     resq 1      ; unique action identifier
    .incident_id:   resq 1      ; associated incident identifier
    .action_type:   resd 1      ; IR_ERAD_*
    .target:        resb 256    ; NUL-terminated eradication target
    .status:        resd 1      ; action status
    .executed_ns:   resq 1      ; execution timestamp
    .verified_ns:   resq 1      ; verification timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Recovery action record
; -----------------------------------------------------------------------------
struc ir_recovery_t
    .action_id:     resq 1      ; unique action identifier
    .incident_id:   resq 1      ; associated incident identifier
    .action_type:   resd 1      ; IR_RECOVER_*
    .target:        resb 256    ; NUL-terminated recovery target
    .status:        resd 1      ; action status
    .executed_ns:   resq 1      ; execution timestamp
    .verified_ns:   resq 1      ; verification timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Playbook record
; -----------------------------------------------------------------------------
struc ir_playbook_t
    .playbook_id:   resq 1      ; unique playbook identifier
    .name:          resb 128    ; NUL-terminated playbook name
    .type:          resd 1      ; IR_PLAYBOOK_*
    .version:       resd 1      ; playbook version
    .enabled:       resb 1      ; playbook is enabled
    .pad:           resb 3      ; alignment
    .step_count:    resd 1      ; number of steps in playbook
    .steps:         resq 1      ; pointer to steps array
    .created_ns:    resq 1      ; creation timestamp
    .updated_ns:    resq 1      ; last update timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Global IR state
; -----------------------------------------------------------------------------
struc ir_global_state_t
    .magic:                 resd 1
    .version:               resd 1
    .enabled:               resb 1
    .fail_mode:             resb 1      ; fail-closed or fail-open
    .pad:                   resb 2
    .components:            resd 1      ; bitmask of initialized components
    .spinlock:              resq 1
    .max_incidents:         resq 1
    .max_playbooks:         resq 1
    .sla_critical_min:      resd 1      ; SLA for critical incidents (minutes)
    .sla_high_min:          resd 1      ; SLA for high incidents (minutes)
    .sla_medium_min:        resd 1      ; SLA for medium incidents (minutes)
    .sla_low_min:           resd 1      ; SLA for low incidents (minutes)
    .pad2:                  resd 2
    .total_incidents:       resq 1      ; total incidents created
    .total_contained:       resq 1      ; total incidents contained
    .total_eradicated:      resq 1      ; total incidents eradicated
    .total_recovered:       resq 1      ; total incidents recovered
    .total_closed:          resq 1      ; total incidents closed
    .core_state:            resq 1
    .triage_state:          resq 1
    .containment_state:     resq 1
    .eradication_state:     resq 1
    .recovery_state:        resq 1
    .playbooks_state:       resq 1
endstruc

%endif ; IR_INC
%endif ; GUARD_SECURITY_INCIDENT_RESPONSE_IR_INC