%ifndef GUARD_SECURITY_ZERO_TRUST_INC_ZERO_TRUST_INC
%define GUARD_SECURITY_ZERO_TRUST_INC_ZERO_TRUST_INC

; =============================================================================
; File     : security/zero_trust/include/zero_trust.inc
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Zero Trust Architecture - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              zero_trust component.
;
; DESIGN INVARIANT:
;   Zero Trust sits ON TOP of usrauth's intersection model. usrauth's DENY is
;   final and short-circuits zero_trust evaluation. zero_trust can only ADD
;   more denials (dynamic policy, session, posture, micro-segmentation).
;
;   Every component exposes:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM SKELETON - data structures, state machines, API contracts,
;         error codes defined. Logic bodies marked STUB with TODO comments.
; =============================================================================

%ifndef ZERO_TRUST_INC
%define ZERO_TRUST_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define ZERO_TRUST_VERSION_MAJOR   1
%define ZERO_TRUST_VERSION_MINOR   0
%define ZERO_TRUST_VERSION_PATCH   0
%define ZERO_TRUST_VERSION_STR     "1.0.0-enterprise-skeleton"

; -----------------------------------------------------------------------------
; Magic numbers for state structure validation
; -----------------------------------------------------------------------------
%define ZT_STATE_MAGIC             0x5A545255   ; "ZTRU"
%define ZT_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask for enabled/disabled components)
; -----------------------------------------------------------------------------
%define ZT_COMP_POLICY_ENGINE      (1 << 0)
%define ZT_COMP_POLICY_ADMIN       (1 << 1)
%define ZT_COMP_ENFORCEMENT_POINT  (1 << 2)
%define ZT_COMP_CONTINUOUS_AUTH    (1 << 3)
%define ZT_COMP_SESSION_MANAGER    (1 << 4)
%define ZT_COMP_MICRO_SEGMENTATION (1 << 5)
%define ZT_COMP_POSTURE_CHECKER    (1 << 6)
%define ZT_COMP_ALL                0x7F

; -----------------------------------------------------------------------------
; Verdict codes (reuse usrauth.inc values where applicable)
; -----------------------------------------------------------------------------
%define ZT_VERDICT_ALLOW           0
%define ZT_VERDICT_DENY_BASE      -100

%define ZT_DENY_NO_SESSION        -101   ; no active trust session
%define ZT_DENY_SESSION_EXPIRED   -102   ; session TTL lapsed
%define ZT_DENY_SESSION_REVOKED   -103   ; session explicitly revoked
%define ZT_DENY_POSTURE_FAIL      -104   ; device posture non-compliant
%define ZT_DENY_SEGMENT_BLOCKED   -105   ; micro-segment boundary denied
%define ZT_DENY_REAUTH_REQUIRED   -106   ; context change requires re-auth
%define ZT_DENY_POLICY_NOT_FOUND  -107   ; no matching dynamic policy
%define ZT_DENY_POLICY_DENY       -108   ; dynamic policy explicitly denies
%define ZT_DENY_COMPONENT_DOWN    -109   ; required component not initialized
%define ZT_DENY_INVALID_REQUEST   -110   ; malformed access request
%define ZT_DENY_OUT_OF_MEMORY     -111   ; state allocation failed

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define ZT_DEFAULT_SESSION_TTL_NS       30000000000    ; 30 seconds
%define ZT_DEFAULT_REAUTH_INTERVAL_NS   60000000000    ; 60 seconds
%define ZT_DEFAULT_MAX_SESSIONS         10000
%define ZT_DEFAULT_POLICY_CACHE_TTL_NS  5000000000     ; 5 seconds
%define ZT_DEFAULT_MAX_POLICIES         1000
%define ZT_DEFAULT_MAX_SEGMENTS         1000
%define ZT_DEFAULT_MAX_BOUNDARIES       500

; -----------------------------------------------------------------------------
; Spinlock macros (compile to PAUSE on x86-64; real lock in implementation)
; -----------------------------------------------------------------------------
%macro ZT_SPIN_LOCK 1
    ; %1 = lock variable address (in register or memory)
    ; STUB: architecture placeholder - acquire spinlock
%endmacro

%macro ZT_SPIN_UNLOCK 1
    ; %1 = lock variable address
    ; STUB: architecture placeholder - release spinlock
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros (intrusive, for session/policy/segment lists)
; -----------------------------------------------------------------------------
%define ZT_LIST_INIT(head)  head

%macro ZT_LIST_ADD 2
    ; %1 = node pointer, %2 = head pointer
    ; STUB: insert node at head of intrusive list
%endmacro

%macro ZT_LIST_REMOVE 2
    ; %1 = node pointer, %2 = head pointer
    ; STUB: remove node from intrusive list
%endmacro

%macro ZT_LIST_FOR_EACH 2
    ; %1 = iterator register, %2 = head pointer
    ; STUB: iterate list elements
%endmacro

; -----------------------------------------------------------------------------
; Audit integration - call usrauth audit decision log
; -----------------------------------------------------------------------------
%macro ZT_AUDIT_LOG 7
    ; %1=subject_handle, %2=verdict, %3=object_id, %4=object_class,
    ; %5=verb, %6=reason_code, %7=session_id
    ; STUB: emit audit record through usrauth/audit decision_log
%endmacro

; -----------------------------------------------------------------------------
; Return value helper: set rax = code, preserve rbx if needed
; -----------------------------------------------------------------------------
%macro ZT_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc zt_state_base_t
    .magic:         resd 1      ; ZT_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock (STUB)
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_calls:   resq 1      ; total calls
    .stats_denies:  resq 1      ; total denials
    .stats_allows:  resq 1      ; total allows
endstruc

; -----------------------------------------------------------------------------
; Access request context (input to zt_evaluate_access)
; -----------------------------------------------------------------------------
struc zt_request_ctx_t
    .subject_handle:   resd 1
    .object_id:        resq 1
    .object_class:     resd 1
    .verb:             resd 1      ; USRAUTH_VERB_*
    .context_flags:    resd 1      ; ZT_CTX_* flags
    .session_id:       resq 1      ; 0 = no session
    .context_ptr:      resq 1      ; opaque context blob
    .context_size:     resd 1
    .timestamp_ns:     resq 1      ; request timestamp
endstruc

%define ZT_CTX_NEW_CONNECTION   (1 << 0)
%define ZT_CTX_NEW_DEVICE       (1 << 1)
%define ZT_CTX_NEW_LOCATION     (1 << 1)
%define ZT_CTX_ANOMALY_DETECTED (1 << 2)
%define ZT_CTX_PRIVILEGED_OP    (1 << 3)

; -----------------------------------------------------------------------------
; Verdict result (output from zt_evaluate_access)
; -----------------------------------------------------------------------------
struc zt_verdict_t
    .verdict:       resd 1      ; ZT_VERDICT_ALLOW or ZT_DENY_*
    .reason_code:   resd 1      ; detailed denial reason
    .session_id:    resq 1      ; associated session (if any)
    .required_reauth: resb 1    ; caller must re-authenticate
    .pad:           resb 7
    .evaluated_ns:  resq 1      ; evaluation timestamp
endstruc

; -----------------------------------------------------------------------------
; Dynamic policy rule
; -----------------------------------------------------------------------------
struc zt_policy_rule_t
    .rule_id:           resq 1
    .subject_pattern:   resq 1      ; subject match (0 = any)
    .object_pattern:    resq 1      ; object match (0 = any)
    .object_class:      resd 1      ; class filter (0 = any)
    .verb_mask:         resd 1      ; required verb bits
    .context_required:  resd 1      ; context flags that must be set
    .context_forbidden: resd 1      ; context flags that must NOT be set
    .action:            resd 1      ; ZT_POLICY_ALLOW / DENY / REQUIRE_AUTH
    .ttl_ns:            resq 1      ; rule lifetime (0 = permanent)
    .priority:          resd 1      ; higher wins
    .hit_count:         resq 1      ; stats
    .next:              resq 1      ; linked list
endstruc

%define ZT_POLICY_ACTION_ALLOW       0
%define ZT_POLICY_ACTION_DENY        1
%define ZT_POLICY_ACTION_REQUIRE_AUTH 2

; -----------------------------------------------------------------------------
; Trust session
; -----------------------------------------------------------------------------
struc zt_session_t
    .session_id:       resq 1
    .subject_handle:   resd 1
    .object_id:        resq 1      ; 0 = any object
    .verb_mask:        resd 1      ; allowed verbs (0 = any)
    .created_ns:       resq 1
    .expires_ns:       resq 1      ; 0 = permanent (discouraged)
    .posture_hash:     resb 32     ; SHA-256 of device posture at creation
    .revoked:          resb 1
    .reauth_required:  resb 1
    .pad:              resb 6
    .stats_hits:       resq 1
    .next:             resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Micro-segment
; -----------------------------------------------------------------------------
struc zt_segment_t
    .segment_id:       resq 1
    .name:             resb 64     ; segment name (NUL-terminated)
    .subnet_start:     resq 1      ; network range start (STUB)
    .subnet_end:       resq 1      ; network range end (STUB)
    .isolated:         resb 1      ; no cross-segment traffic by default
    .pad:              resb 7
    .stats_flows:      resq 1
    .next:             resq 1
endstruc

; -----------------------------------------------------------------------------
; Enforcement boundary
; -----------------------------------------------------------------------------
struc zt_boundary_t
    .boundary_id:      resq 1
    .segment_src:      resq 1
    .segment_dst:      resq 1
    .verb_mask:        resd 1      ; verbs allowed across boundary
    .enabled:          resb 1
    .pad:              resb 3
    .stats_enforced:   resq 1
    .next:             resq 1
endstruc

; -----------------------------------------------------------------------------
; Posture check requirement
; -----------------------------------------------------------------------------
struc zt_posture_req_t
    .req_id:           resq 1
    .check_type:       resd 1      ; ZT_POSTURE_*
    .required_value:   resq 1
    .optional:         resb 1
    .pad:              resb 7
    .next:             resq 1
endstruc

%define ZT_POSTURE_MEASURED_BOOT   1
%define ZT_POSTURE_TPM_ATTESTATION 2
%define ZT_POSTURE_PATCH_LEVEL     3
%define ZT_POSTURE_SERVICES        4

; -----------------------------------------------------------------------------
; Global zero_trust state
; -----------------------------------------------------------------------------
struc zt_global_state_t
    .magic:             resd 1
    .version:           resd 1
    .enabled:           resb 1
    .pad:               resb 3
    .components:        resd 1      ; bitmask of initialized components
    .spinlock:          resq 1
    .session_ttl_ns:    resq 1
    .reauth_interval_ns:resq 1
    .max_sessions:      resq 1
    .active_sessions:   resq 1
    .total_requests:    resq 1
    .total_allows:      resq 1
    .total_denies:      resq 1
    .policy_engine_state:    resq 1
    .policy_admin_state:     resq 1
    .enforcement_state:      resq 1
    .continuous_auth_state:  resq 1
    .session_manager_state:  resq 1
    .micro_seg_state:        resq 1
    .posture_checker_state:  resq 1
endstruc

; -----------------------------------------------------------------------------
; Extern declarations (cross-component references)
; -----------------------------------------------------------------------------

%endif ; ZERO_TRUST_INC
%endif ; GUARD_SECURITY_ZERO_TRUST_INC_ZERO_TRUST_INC
