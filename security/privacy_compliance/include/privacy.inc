%ifndef GUARD_SECURITY_PRIVACY_COMPLIANCE_PRIVACY_INC
%define GUARD_SECURITY_PRIVACY_COMPLIANCE_PRIVACY_INC

; =============================================================================
; File     : security/privacy_compliance/include/privacy.inc
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Privacy Compliance - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              privacy component (core, dlp_engine, consent, classifier,
;              reporter).
;
; DESIGN INVARIANT:
;   Privacy Compliance enforces data protection regulations (GDPR, CCPA, HIPAA)
;   through data classification, consent management, DLP inspection, and
;   regulatory reporting. All personal data handling is logged and auditable.
;   Consent is required for processing; withdrawal of consent stops processing.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE - full privacy compliance feature set including
;         DLP, consent management, data classification, and regulatory
;         reporting defined.
; =============================================================================

%ifndef PRIVACY_INC
%define PRIVACY_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define PRIVACY_VERSION_MAJOR   1
%define PRIVACY_VERSION_MINOR   0
%define PRIVACY_VERSION_PATCH   0
%define PRIVACY_VERSION_STR     "1.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define PRIVACY_STATE_MAGIC             0x50524956   ; "PRIV"
%define PRIVACY_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define PRIVACY_CORE        (1 << 0)
%define PRIVACY_DLP         (1 << 1)
%define PRIVACY_CONSENT     (1 << 2)
%define PRIVACY_CLASSIFIER  (1 << 3)
%define PRIVACY_REPORTER    (1 << 4)
%define PRIVACY_ALL         0x1F

; -----------------------------------------------------------------------------
; Data classification levels
; -----------------------------------------------------------------------------
%define PRIVACY_CLASS_PUBLIC       1
%define PRIVACY_CLASS_INTERNAL     2
%define PRIVACY_CLASS_CONFIDENTIAL 3
%define PRIVACY_CLASS_RESTRICTED   4

; -----------------------------------------------------------------------------
; Consent types
; -----------------------------------------------------------------------------
%define PRIVACY_CONSENT_MARKETING      1
%define PRIVACY_CONSENT_ANALYTICS      2
%define PRIVACY_CONSENT_FUNCTIONAL     3
%define PRIVACY_CONSENT_PERSONALIZATION 4

; -----------------------------------------------------------------------------
; Consent states
; -----------------------------------------------------------------------------
%define PRIVACY_CONSENT_GRANTED   1
%define PRIVACY_CONSENT_DENIED    2
%define PRIVACY_CONSENT_WITHDRAWN 3
%define PRIVACY_CONSENT_EXPIRED   4

; -----------------------------------------------------------------------------
; DLP actions
; -----------------------------------------------------------------------------
%define PRIVACY_DLP_ALLOW      1
%define PRIVACY_DLP_BLOCK      2
%define PRIVACY_DLP_ENCRYPT    3
%define PRIVACY_DLP_REDACT     4
%define PRIVACY_DLP_QUARANTINE 5

; -----------------------------------------------------------------------------
; Regulatory frameworks
; -----------------------------------------------------------------------------
%define PRIVACY_REG_GDPR   1
%define PRIVACY_REG_CCPA   2
%define PRIVACY_REG_HIPAA  3
%define PRIVACY_REG_PCI_DSS 4

; -----------------------------------------------------------------------------
; Error codes
; -----------------------------------------------------------------------------
%define PRIVACY_ERR_SUCCESS        0
%define PRIVACY_ERR_GENERAL        1
%define PRIVACY_ERR_NOT_INIT       2
%define PRIVACY_ERR_INVALID_ARG    3
%define PRIVACY_ERR_RESOURCE       4
%define PRIVACY_ERR_ACCESS         5
%define PRIVACY_ERR_NOT_FOUND      6
%define PRIVACY_ERR_CONSENT_DENIED 7
%define PRIVACY_ERR_POLICY_VIOLATION 8

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define PRIVACY_DEFAULT_MAX_DATA_SUBJECTS   1000000
%define PRIVACY_DEFAULT_MAX_CONSENTS        500000
%define PRIVACY_DEFAULT_MAX_DLP_POLICIES    5000
%define PRIVACY_DEFAULT_DSR_RESPONSE_DAYS   30

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro PRIVACY_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro PRIVACY_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define PRIVACY_LIST_INIT(head)  head

%macro PRIVACY_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro PRIVACY_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro PRIVACY_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc privacy_state_base_t
    .magic:         resd 1      ; PRIVACY_STATE_MAGIC for validation
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
; Data subject record
; -----------------------------------------------------------------------------
struc privacy_data_subject_t
    .subject_id:    resq 1      ; unique data subject identifier
    .email:         resb 256    ; NUL-terminated email address
    .external_id:   resb 128    ; NUL-terminated external system ID
    .consent_status:resd 1      ; PRIVACY_CONSENT_*
    .created_ns:    resq 1      ; subject creation timestamp
    .updated_ns:    resq 1      ; last update timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Consent record
; -----------------------------------------------------------------------------
struc privacy_consent_t
    .consent_id:    resq 1      ; unique consent identifier
    .subject_id:    resq 1      ; associated data subject
    .type:          resd 1      ; PRIVACY_CONSENT_*
    .state:         resd 1      ; PRIVACY_CONSENT_*
    .granted_ns:    resq 1      ; consent granted timestamp
    .withdrawn_ns:  resq 1      ; consent withdrawn timestamp
    .expires_ns:    resq 1      ; consent expiration timestamp
    .purpose:       resb 256    ; NUL-terminated purpose description
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; DLP policy record
; -----------------------------------------------------------------------------
struc privacy_dlp_policy_t
    .policy_id:     resq 1      ; unique policy identifier
    .name:          resb 128    ; NUL-terminated policy name
    .action:        resd 1      ; PRIVACY_DLP_*
    .pattern:       resb 512    ; NUL-terminated detection pattern
    .pattern_type:  resd 1      ; pattern type (regex, keyword, hash)
    .enabled:       resb 1      ; policy is enabled
    .pad:           resb 3      ; alignment
    .created_ns:    resq 1      ; policy creation timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; DLP incident record
; -----------------------------------------------------------------------------
struc privacy_dlp_incident_t
    .incident_id:   resq 1      ; unique DLP incident identifier
    .policy_id:     resq 1      ; associated policy identifier
    .subject_id:    resq 1      ; associated data subject (if any)
    .action_taken:  resd 1      ; PRIVACY_DLP_*
    .severity:      resd 1      ; incident severity
    .detected_ns:   resq 1      ; detection timestamp
    .resolved_ns:   resq 1      ; resolution timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Regulatory report record
; -----------------------------------------------------------------------------
struc privacy_report_t
    .report_id:     resq 1      ; unique report identifier
    .regulation:    resd 1      ; PRIVACY_REG_*
    .report_type:   resd 1      ; report type
    .period_start:  resq 1      ; reporting period start
    .period_end:    resq 1      ; reporting period end
    .generated_ns:  resq 1      ; report generation timestamp
    .path:          resb 512    ; NUL-terminated report file path
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Global Privacy state
; -----------------------------------------------------------------------------
struc privacy_global_state_t
    .magic:                 resd 1
    .version:               resd 1
    .enabled:               resb 1
    .fail_mode:             resb 1      ; fail-closed or fail-open
    .pad:                   resb 2
    .components:            resd 1      ; bitmask of initialized components
    .spinlock:              resq 1
    .max_data_subjects:     resq 1
    .max_consents:          resq 1
    .max_dlp_policies:      resq 1
    .dsr_response_days:     resd 1      ; DSR response deadline (days)
    .pad2:                  resd 3
    .total_subjects:        resq 1      ; total data subjects
    .total_consents:        resq 1      ; total consents
    .total_dlp_incidents:   resq 1      ; total DLP incidents
    .total_reports:         resq 1      ; total reports generated
    .core_state:            resq 1
    .dlp_state:             resq 1
    .consent_state:         resq 1
    .classifier_state:      resq 1
    .reporter_state:        resq 1
endstruc

%endif ; PRIVACY_INC
%endif ; GUARD_SECURITY_PRIVACY_COMPLIANCE_PRIVACY_INC