%ifndef GUARD_SECURITY_USRAUTH_USRAUTH_INC
%define GUARD_SECURITY_USRAUTH_USRAUTH_INC
; =============================================================================
; Tattva OS — security/usrauth/usrauth.inc
; =============================================================================
; Master Schema Header for USRAUTH (Reference Monitor).
;
; Subject, capability, label, token and decision structures shared by every
; usrauth layer.
;
; DESIGN INVARIANT — read before changing anything here:
;
;   Many independent ways to DENY. Exactly ONE way to GRANT.
;
; Effective authority is the INTERSECTION of every layer, never the union. If a
; future layer is added that can independently answer "yes", the model breaks:
; union semantics grant precisely what some other layer meant to withhold. The
; POSIX ACL mask is the canonical illustration — an entry granting rw under a
; mask of r-x must resolve to DENY.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef USRAUTH_INC
%define USRAUTH_INC

%define USRAUTH_VERSION               1
%define USRAUTH_MAX_SUBJECTS          256
%define USRAUTH_MAX_CAPS_PER_SUBJECT  64
%define USRAUTH_MAX_GROUPS            16
%define USRAUTH_MAX_RELATIONS         1024
%define USRAUTH_MAX_TYPES             64
%define USRAUTH_MAX_TE_RULES          512
%define USRAUTH_MAX_CATEGORIES        64      ; MLS compartments, one bit each
%define USRAUTH_RELATION_MAX_DEPTH    8       ; Bounded graph walk

; -----------------------------------------------------------------------------
; USRAUTH_JMP_IF_LAPSED now, deadline, label
;
; The single definition of what "expired" means, used everywhere a deadline is
; consulted. It is a macro rather than a call because the policy walk evaluates
; it once per relation per request, and a call there is pure overhead.
;
; A deadline of 0 means permanent. That case has to be tested FIRST: comparing
; a real clock against 0 makes every permanent grant look infinitely expired,
; which is the failure that turns a working policy table into a total denial.
;
; The comparison is `jae`, so a grant lapses AT its deadline rather than one
; nanosecond after. An expiry time should not still be a valid time.
; -----------------------------------------------------------------------------
%macro USRAUTH_JMP_IF_LAPSED 3
    test %2, %2
    jz %%live
    cmp %1, %2
    jae %3
%%live:
%endmacro
%define USRAUTH_INVALID_HANDLE        0xFFFFFFFF

; -----------------------------------------------------------------------------
; Verbs — the operation being attempted. Kept small and closed; an open verb
; space would make type-enforcement rules impossible to audit.
; -----------------------------------------------------------------------------
%define USRAUTH_VERB_READ             0x0001
%define USRAUTH_VERB_WRITE            0x0002
%define USRAUTH_VERB_EXEC             0x0004
%define USRAUTH_VERB_APPEND           0x0008
%define USRAUTH_VERB_CREATE           0x0010
%define USRAUTH_VERB_DELETE           0x0020
%define USRAUTH_VERB_ADMIN            0x0040      ; Change policy or ownership
%define USRAUTH_VERB_DELEGATE         0x0080      ; Grant to another subject
%define USRAUTH_VERB_MASK             0x00FF

; -----------------------------------------------------------------------------
; Object classes — what kind of thing is being acted on.
; -----------------------------------------------------------------------------
%define USRAUTH_CLASS_FILE            1
%define USRAUTH_CLASS_DIR             2
%define USRAUTH_CLASS_DEVICE          3
%define USRAUTH_CLASS_SOCKET          4
%define USRAUTH_CLASS_PROCESS         5
%define USRAUTH_CLASS_CAPABILITY      6
%define USRAUTH_CLASS_POLICY          7
%define USRAUTH_CLASS_KEY             8

; -----------------------------------------------------------------------------
; Integrity levels (Windows Mandatory Integrity Control / Biba).
;
; A subject may not WRITE to an object of higher integrity. This is what stops
; a low-integrity process from corrupting trusted state even when DAC would
; allow it.
; -----------------------------------------------------------------------------
%define USRAUTH_INTEGRITY_UNTRUSTED   0
%define USRAUTH_INTEGRITY_LOW         1
%define USRAUTH_INTEGRITY_MEDIUM      2       ; Default for ordinary subjects
%define USRAUTH_INTEGRITY_HIGH        3
%define USRAUTH_INTEGRITY_SYSTEM      4

; -----------------------------------------------------------------------------
; Subject flags.
; -----------------------------------------------------------------------------
%define USRAUTH_SUBJ_ACTIVE           (1 << 0)
%define USRAUTH_SUBJ_PRIVILEGED       (1 << 1)   ; May write privileged xattr NS
%define USRAUTH_SUBJ_RESTRICTED       (1 << 2)   ; pledge/unveil applied
%define USRAUTH_SUBJ_ATTESTED         (1 << 3)   ; Identity from measured boot

; -----------------------------------------------------------------------------
; Decision results. Distinct codes per layer so an audit record explains WHY,
; not merely that access failed — the single most useful property of an
; access-control log.
; -----------------------------------------------------------------------------
%define USRAUTH_ALLOW                 0
%define USRAUTH_DENY_MANDATORY       -1      ; L5 type enforcement
%define USRAUTH_DENY_INTEGRITY       -2      ; L2 no write-up
%define USRAUTH_DENY_MLS             -3      ; L5 no read-up / write-down
%define USRAUTH_DENY_CAPABILITY      -4      ; L3 authority not held
%define USRAUTH_DENY_CAVEAT          -5      ; L1 token caveat unsatisfied
%define USRAUTH_DENY_EXPIRED         -6      ; L1/L4 grant lapsed
%define USRAUTH_DENY_POLICY          -7      ; L4 no relation grants it
%define USRAUTH_DENY_REVOKED         -8      ; L1 token epoch stale
%define USRAUTH_DENY_INVALID         -9      ; Malformed request
%define USRAUTH_DENY_FORGED          -10     ; L1 token tag did not authenticate

; -----------------------------------------------------------------------------
; MLS label — Bell-LaPadula classification plus compartments.
;
; Read requires the subject dominate the object (no read-up).
; Write requires the object dominate the subject (no write-down).
; -----------------------------------------------------------------------------
struc usrauth_label_t
    .level:             resd 1      ; Classification, higher is more sensitive
    .categories:        resq 1      ; 64 compartment bits
endstruc

; -----------------------------------------------------------------------------
; Capability — an unforgeable reference carrying its own rights.
;
; Authority is HELD, not looked up by name. That is what makes the confused
; deputy structurally impossible: a subject cannot exercise authority it was
; never handed, even if a name-based check would have said yes.
; -----------------------------------------------------------------------------
struc usrauth_cap_t
    .object_id:         resq 1      ; What this grants authority over
    .object_class:      resd 1      ; USRAUTH_CLASS_*
    .rights:            resd 1      ; USRAUTH_VERB_* bitmask
    .expires_ns:        resq 1      ; 0 = no expiry (discouraged)
    .flags:             resd 1
    .reserved:          resd 1
endstruc

; -----------------------------------------------------------------------------
; Subject — the access token equivalent.
;
; usrauth owns this table and hands out opaque handles, so it does not depend on
; a scheduler existing. When sched/ arrives, a task struct simply carries the
; handle and nothing here changes.
; -----------------------------------------------------------------------------
struc usrauth_subject_t
    .uid:               resd 1
    .gid:               resd 1
    .groups:            resd USRAUTH_MAX_GROUPS  ; Supplementary groups
    .group_count:       resd 1
    .type_id:           resd 1      ; SELinux-style domain
    .integrity:         resd 1      ; USRAUTH_INTEGRITY_*
    .label:             resb usrauth_label_t_size
    .flags:             resd 1      ; USRAUTH_SUBJ_*
    .cap_count:         resd 1
    .caps:              resb USRAUTH_MAX_CAPS_PER_SUBJECT * usrauth_cap_t_size
    .created_ns:        resq 1
    .token_epoch:       resq 1      ; Stale epoch invalidates derived tokens
endstruc

; -----------------------------------------------------------------------------
; Object descriptor — the target side of a decision.
; -----------------------------------------------------------------------------
struc usrauth_object_t
    .object_id:         resq 1
    .object_class:      resd 1
    .type_id:           resd 1      ; Target type for type enforcement
    .owner_uid:         resd 1
    .owner_gid:         resd 1
    .integrity:         resd 1
    .label:             resb usrauth_label_t_size
    .mode:              resd 1      ; POSIX bits, DAC input
endstruc

; -----------------------------------------------------------------------------
; Type-enforcement rule: (subject type, object type, class) -> allowed verbs.
;
; Absence is denial. There is no "deny" rule because there is nothing to
; override — the default answer is already no.
; -----------------------------------------------------------------------------
struc usrauth_te_rule_t
    .subject_type:      resd 1
    .object_type:       resd 1
    .object_class:      resd 1
    .allowed_verbs:     resd 1
endstruc

; -----------------------------------------------------------------------------
; Relation tuple (Zanzibar-style): object#relation@subject.
;
; Answers both "who can reach X" and "what can A reach" — a plain ACL answers
; only the first, which is why access reviews are hard on ACL-only systems.
; -----------------------------------------------------------------------------
struc usrauth_relation_t
    .object_id:         resq 1
    .relation:          resd 1      ; Verb bitmask this relation confers
    .subject_handle:    resd 1      ; Direct subject, or...
    .via_object:        resq 1      ; ...inherit from another object (groups)
    .expires_ns:        resq 1      ; 0 = permanent (must be explicit)
    .flags:             resd 1
    .active:            resd 1
endstruc

; -----------------------------------------------------------------------------
; Token — portable, attenuable, proof-of-possession bound.
; -----------------------------------------------------------------------------
%define USRAUTH_TOKEN_MAGIC           0x55475431      ; "UGT1"
%define USRAUTH_TOKEN_MAX_CAVEATS     8

struc usrauth_caveat_t
    .kind:              resd 1      ; USRAUTH_CAVEAT_*
    .reserved:          resd 1
    .arg_a:             resq 1
    .arg_b:             resq 1
endstruc

%define USRAUTH_CAVEAT_EXPIRES        1   ; arg_a = absolute ns deadline
%define USRAUTH_CAVEAT_VERB_MASK      2   ; arg_a = permitted verb bits
%define USRAUTH_CAVEAT_OBJECT         3   ; arg_a = single permitted object id
%define USRAUTH_CAVEAT_CLASS          4   ; arg_a = permitted object class
%define USRAUTH_CAVEAT_SUBJECT        5   ; arg_a = bound subject handle

struc usrauth_token_t
    .magic:             resd 1
    .version:           resd 1
    .subject_handle:    resd 1
    .caveat_count:      resd 1
    .issued_ns:         resq 1
    .epoch:             resq 1      ; Must match the subject's current epoch
    .caveats:           resb USRAUTH_TOKEN_MAX_CAVEATS * usrauth_caveat_t_size
    .tag:               resb 32     ; HMAC-SHA256 over everything above
endstruc

; -----------------------------------------------------------------------------
; Audit record — hash-chained so tampering is detectable.
; -----------------------------------------------------------------------------
struc usrauth_audit_t
    .seq:               resq 1
    .timestamp_ns:      resq 1
    .subject_handle:    resd 1
    .verdict:           resd 1      ; USRAUTH_ALLOW or a USRAUTH_DENY_* code
    .object_id:         resq 1
    .object_class:      resd 1
    .verb:              resd 1
    .prev_hash:         resb 32     ; Chains to the previous record
    .hash:              resb 32     ; SHA-256 over this record with hash zeroed
endstruc

%endif ; USRAUTH_INC

%endif ; GUARD_SECURITY_USRAUTH_USRAUTH_INC
