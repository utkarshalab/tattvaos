%ifndef GUARD_SECURITY_DIGITAL_FORENSICS_DFIR_INC
%define GUARD_SECURITY_DIGITAL_FORENSICS_DFIR_INC

; =============================================================================
; File     : security/digital_forensics/include/dfir.inc
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Digital Forensics - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              DFIR component (core, acquirer, analyzer, custody, reporter).
;
; DESIGN INVARIANT:
;   Digital Forensics acquires, analyzes, and reports on digital evidence
;   while maintaining an unbroken chain of custody. All acquisitions are
;   write-blocked where possible; all evidence is hashed at acquisition time;
;   all custody transfers are cryptographically signed. The subsystem fails
;   closed: if hashing or signing is unavailable, acquisition aborts.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE SKELETON - full schema defined, logic bodies
;         marked STUB for implementation.
; =============================================================================

%ifndef DFIR_INC
%define DFIR_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define DFIR_VERSION_MAJOR   1
%define DFIR_VERSION_MINOR   0
%define DFIL_VERSION_PATCH   0
%define DFIR_VERSION_STR     "1.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define DFIR_STATE_MAGIC             0x44464952   ; "DFIR"
%define DFIR_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define DFIR_CORE        (1 << 0)
%define DFIR_ACQUIRER    (1 << 1)
%define DFIR_ANALYZER    (1 << 2)
%define DFIR_CUSTODY     (1 << 3)
%define DFIR_REPORTER    (1 << 4)
%define DFIR_ALL         0x1F

; -----------------------------------------------------------------------------
; Acquisition types
; -----------------------------------------------------------------------------
%define DFIR_ACQ_DISK          1   ; physical disk imaging
%define DFIR_ACQ_MEMORY        2   ; RAM acquisition
%define DFIR_ACQ_FILE          3   ; file-level acquisition
%define DFIR_ACQ_NETWORK       4   ; network capture
%define DFIR_ACQ_MOBILE        5   ; mobile device acquisition

; -----------------------------------------------------------------------------
; Evidence states
; -----------------------------------------------------------------------------
%define DFIR_EVIDENCE_ACQUIRED   1
%define DFIR_EVIDENCE_ANALYZED   2
%define DFIR_EVIDENCE_REVIEWED   3
%define DFIR_EVIDENCE_RELEASED   4
%define DFIR_EVIDENCE_DESTROYED  5

; -----------------------------------------------------------------------------
; Verdicts
; -----------------------------------------------------------------------------
%define DFIR_VERDICT_CLEAN       0
%define DFIR_VERDICT_SUSPICIOUS  1
%define DFIR_VERDICT_MALICIOUS   2
%define DFIR_VERDICT_INCONCLUSIVE 3

; -----------------------------------------------------------------------------
; Custody actions
; -----------------------------------------------------------------------------
%define DFIR_CUSTODY_COLLECT     1
%define DFIR_CUSTODY_TRANSFER    2
%define DFIR_CUSTODY_ACCESS      3
%define DFIR_CUSTODY_RETURN      4
%define DFIR_CUSTODY_DESTROY     5

; -----------------------------------------------------------------------------
; Error codes
; -----------------------------------------------------------------------------
%define DFIR_ERR_SUCCESS         0
%define DFIR_ERR_GENERAL         1
%define DFIR_ERR_NOT_INIT        2
%define DFIR_ERR_INVALID_ARG     3
%define DFIR_ERR_RESOURCE        4
%define DFIR_ERR_ACCESS          5
%define DFIR_ERR_NOT_FOUND       6
%define DFIR_ERR_WRITE_BLOCKED   7
%define DFIR_ERR_HASH_MISMATCH   8
%define DFIR_ERR_CUSTODY_BREAK   9

; -----------------------------------------------------------------------------
; Hash algorithms
; -----------------------------------------------------------------------------
%define DFIR_HASH_SHA256         1
%define DFIR_HASH_SHA512         2
%define DFIR_HASH_BLAKE3         3

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define DFIR_DEFAULT_MAX_EVIDENCE       10000
%define DFIR_DEFAULT_MAX_CASES          1000
%define DFIR_DEFAULT_MAX_CUSTODY_ENTRIES 50000
%define DFIR_DEFAULT_HASH_ALGORITHM     DFIR_HASH_SHA256
%define DFIR_DEFAULT_WRITE_BLOCKED      1

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro DFIR_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro DFIR_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define DFIR_LIST_INIT(head)  head

%macro DFIR_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro DFIR_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro DFIR_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc dfir_state_base_t
    .magic:         resd 1      ; DFIR_STATE_MAGIC for validation
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
; Case / investigation record
; -----------------------------------------------------------------------------
struc dfir_case_t
    .case_id:       resq 1      ; unique case identifier
    .title:         resb 256    ; NUL-terminated case title
    .investigator:  resb 128    ; NUL-terminated investigator name
    .created_ns:    resq 1      ; case creation timestamp
    .closed_ns:     resq 1      ; case closure timestamp
    .evidence_count:resq 1      ; number of evidence items
    .status:        resd 1      ; case status
    .severity:      resd 1      ; case severity
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Evidence item record
; -----------------------------------------------------------------------------
struc dfir_evidence_t
    .evidence_id:   resq 1      ; unique evidence identifier
    .case_id:       resq 1      ; owning case identifier
    .type:          resd 1      ; DFIR_ACQ_*
    .state:         resd 1      ; DFIR_EVIDENCE_*
    .source_path:   resb 512    ; NUL-terminated source path
    .dest_path:     resb 512    ; NUL-terminated destination path
    .hash_alg:      resd 1      ; DFIR_HASH_*
    .hash_sha256:   resb 32     ; SHA-256 hash of evidence
    .hash_sha512:   resb 64     ; SHA-512 hash of evidence
    .size_bytes:    resq 1      ; evidence size in bytes
    .acquired_ns:   resq 1      ; acquisition timestamp
    .write_blocked: resb 1      ; write-blocked during acquisition
    .pad:           resb 7      ; alignment
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Chain-of-custody entry record
; -----------------------------------------------------------------------------
struc dfir_custody_t
    .entry_id:      resq 1      ; unique custody entry identifier
    .evidence_id:   resq 1      ; associated evidence identifier
    .action:        resd 1      ; DFIR_CUSTODY_*
    .actor:         resb 128    ; NUL-terminated actor name
    .timestamp_ns:  resq 1      ; action timestamp
    .location:      resb 256    ; NUL-terminated location
    .purpose:       resb 512    ; NUL-terminated purpose
    .signature:     resb 64     ; cryptographic signature of entry
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Analysis result record
; -----------------------------------------------------------------------------
struc dfir_analysis_t
    .analysis_id:   resq 1      ; unique analysis identifier
    .evidence_id:   resq 1      ; associated evidence identifier
    .analyzer_type: resd 1      ; type of analysis performed
    .verdict:       resd 1      ; DFIR_VERDICT_*
    .confidence:    resd 1      ; 0-100 confidence score
    .findings:      resb 1024   ; NUL-terminated findings summary
    .findings_len:  resd 1      ; length of findings
    .analyzed_ns:   resq 1      ; analysis timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Report record
; -----------------------------------------------------------------------------
struc dfir_report_t
    .report_id:     resq 1      ; unique report identifier
    .case_id:       resq 1      ; associated case identifier
    .format:        resd 1      ; report format (PDF, JSON, HTML, CSV)
    .generated_ns:  resq 1      ; report generation timestamp
    .generator:     resb 128    ; NUL-terminated report generator
    .path:          resb 512    ; NUL-terminated report file path
    .signed:        resb 1      ; report is cryptographically signed
    .pad:           resb 7      ; alignment
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Global DFIR state
; -----------------------------------------------------------------------------
struc dfir_global_state_t
    .magic:                 resd 1
    .version:               resd 1
    .enabled:               resb 1
    .fail_mode:             resb 1      ; fail-closed or fail-open
    .pad:                   resb 2
    .components:            resd 1      ; bitmask of initialized components
    .spinlock:              resq 1
    .max_evidence:          resq 1
    .max_cases:             resq 1
    .max_custody_entries:   resq 1
    .default_hash_alg:      resd 1      ; default hash algorithm
    .write_blocked:         resb 1      ; write-blocked acquisition enabled
    .pad2:                  resb 3
    .total_cases:           resq 1      ; total cases created
    .total_evidence:        resq 1      ; total evidence items
    .total_custody_entries: resq 1      ; total custody entries
    .total_analyses:        resq 1      ; total analyses performed
    .total_reports:         resq 1      ; total reports generated
    .core_state:            resq 1
    .acquirer_state:        resq 1
    .analyzer_state:        resq 1
    .custody_state:         resq 1
    .reporter_state:        resq 1
endstruc

%endif ; DFIR_INC
%endif ; GUARD_SECURITY_DIGITAL_FORENSICS_DFIR_INC