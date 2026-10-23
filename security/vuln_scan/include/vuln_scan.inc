%ifndef GUARD_SECURITY_VULN_SCAN_VULN_SCAN_INC
%define GUARD_SECURITY_VULN_SCAN_VULN_SCAN_INC

; =============================================================================
; File     : security/vuln_scan/include/vuln_scan.inc
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Vulnerability Scan - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              vuln_scan component (core, scanner, assessor, database, reporter).
;
; DESIGN INVARIANT:
;   Vulnerability Scan discovers, assesses, and reports vulnerabilities across
;   the attack surface. Every finding is scored using CVSS, tracked through
;   remediation, and reported for compliance. Scanning is non-destructive;
;   findings are validated before reporting.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE - full vulnerability scanning feature set including
;         discovery, assessment, reporting, and remediation tracking defined.
; =============================================================================

%ifndef VULN_SCAN_INC
%define VULN_SCAN_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define VULN_SCAN_VERSION_MAJOR   1
%define VULN_SCAN_VERSION_MINOR   0
%define VULN_SCAN_VERSION_PATCH   0
%define VULN_SCAN_VERSION_STR     "1.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define VULN_SCAN_STATE_MAGIC             0x56554C53   ; "VULS"
%define VULN_SCAN_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define VULN_SCAN_CORE        (1 << 0)
%define VULN_SCAN_SCANNER   (1 << 1)
%define VULN_SCAN_ASSESSOR  (1 << 2)
%define VULN_SCAN_DATABASE  (1 << 3)
%define VULN_SCAN_REPORTER  (1 << 4)
%define VULN_SCAN_ALL       0x1F

; -----------------------------------------------------------------------------
; Scan types
; -----------------------------------------------------------------------------
%define VULN_SCAN_TYPE_NETWORK     1   ; network vulnerability scan
%define VULN_SCAN_TYPE_HOST        2   ; host vulnerability scan
%define VULN_SCAN_TYPE_APPLICATION 3   ; application vulnerability scan
%define VULN_SCAN_TYPE_CONTAINER   4   ; container vulnerability scan
%define VULN_SCAN_TYPE_CLOUD       5   ; cloud vulnerability scan

; -----------------------------------------------------------------------------
; Severity levels (CVSS-based)
; -----------------------------------------------------------------------------
%define VULN_SCAN_SEV_NONE       0
%define VULN_SCAN_SEV_LOW        1
%define VULN_SCAN_SEV_MEDIUM     2
%define VULN_SCAN_SEV_HIGH       3
%define VULN_SCAN_SEV_CRITICAL   4

; -----------------------------------------------------------------------------
; Scan status
; -----------------------------------------------------------------------------
%define VULN_SCAN_STATUS_QUEUED      1
%define VULN_SCAN_STATUS_RUNNING     2
%define VULN_SCAN_STATUS_COMPLETED   3
%define VULN_SCAN_STATUS_FAILED      4
%define VULN_SCAN_STATUS_CANCELLED   5

; -----------------------------------------------------------------------------
; Finding status
; -----------------------------------------------------------------------------
%define VULN_SCAN_FINDING_OPEN         1
%define VULN_SCAN_FINDING_IN_PROGRESS  2
%define VULN_SCAN_FINDING_REMEDIATED   3
%define VULN_SCAN_FINDING_FALSE_POSITIVE 4
%define VULN_SCAN_FINDING_RISK_ACCEPTED 5

; -----------------------------------------------------------------------------
; Error codes
; -----------------------------------------------------------------------------
%define VULN_SCAN_ERR_SUCCESS         0
%define VULN_SCAN_ERR_GENERAL         1
%define VULN_SCAN_ERR_NOT_INIT        2
%define VULN_SCAN_ERR_INVALID_ARG     3
%define VULN_SCAN_ERR_RESOURCE        4
%define VULN_SCAN_ERR_ACCESS          5
%define VULN_SCAN_ERR_NOT_FOUND       6
%define VULN_SCAN_ERR_SCAN_FAILED     7
%define VULN_SCAN_ERR_TARGET_UNREACHABLE 8

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define VULN_SCAN_DEFAULT_MAX_TARGETS   10000
%define VULN_SCAN_DEFAULT_MAX_FINDINGS  100000
%define VULN_SCAN_DEFAULT_MAX_SCANS     10000
%define VULN_SCAN_DEFAULT_SCAN_TIMEOUT  3600   ; seconds

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro VULN_SCAN_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro VULN_SCAN_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define VULN_SCAN_LIST_INIT(head)  head

%macro VULN_SCAN_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro VULN_SCAN_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro VULN_SCAN_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc vuln_scan_state_base_t
    .magic:         resd 1      ; VULN_SCAN_STATE_MAGIC for validation
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
; Scan target record
; -----------------------------------------------------------------------------
struc vuln_scan_target_t
    .target_id:     resq 1      ; unique target identifier
    .type:          resd 1      ; VULN_SCAN_TYPE_*
    .address:       resb 256    ; NUL-terminated target address (IP, URL, etc.)
    .port:          resd 1      ; target port
    .status:        resd 1      ; VULN_SCAN_STATUS_*
    .last_scan_ns:  resq 1      ; last scan timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Vulnerability finding record
; -----------------------------------------------------------------------------
struc vuln_scan_finding_t
    .finding_id:    resq 1      ; unique finding identifier
    .target_id:     resq 1      ; associated target identifier
    .cve_id:        resb 32     ; NUL-terminated CVE identifier
    .cwe_id:        resd 1      ; CWE identifier
    .severity:      resd 1      ; VULN_SCAN_SEV_*
    .cvss_score:    resd 1      ; CVSS score (0.0-10.0)
    .status:        resd 1      ; VULN_SCAN_FINDING_*
    .description:   resb 1024   ; NUL-terminated finding description
    .discovered_ns: resq 1      ; discovery timestamp
    .remediated_ns: resq 1      ; remediation timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Scan record
; -----------------------------------------------------------------------------
struc vuln_scan_scan_t
    .scan_id:       resq 1      ; unique scan identifier
    .type:          resd 1      ; VULN_SCAN_TYPE_*
    .target_id:     resq 1      ; associated target identifier
    .status:        resd 1      ; VULN_SCAN_STATUS_*
    .started_ns:    resq 1      ; scan start timestamp
    .completed_ns:  resq 1      ; scan completion timestamp
    .finding_count: resq 1      ; number of findings
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Vulnerability database record
; -----------------------------------------------------------------------------
struc vuln_scan_db_entry_t
    .cve_id:        resq 1      ; unique CVE identifier
    .cve_name:      resb 64     ; NUL-terminated CVE name
    .cwe_id:        resd 1      ; associated CWE identifier
    .severity:      resd 1      ; VULN_SCAN_SEV_*
    .cvss_score:    resd 1      ; CVSS score
    .description:   resb 1024   ; NUL-terminated description
    .published_ns:  resq 1      ; publication timestamp
    .modified_ns:   resq 1      ; last modification timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Report record
; -----------------------------------------------------------------------------
struc vuln_scan_report_t
    .report_id:     resq 1      ; unique report identifier
    .scan_id:       resq 1      ; associated scan identifier
    .format:        resd 1      ; report format (PDF, JSON, HTML, CSV)
    .target_count:  resq 1      ; number of targets scanned
    .finding_count: resq 1      ; number of findings
    .generated_ns:  resq 1      ; report generation timestamp
    .path:          resb 512    ; NUL-terminated report file path
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Global Vulnerability Scan state
; -----------------------------------------------------------------------------
struc vuln_scan_global_state_t
    .magic:                 resd 1
    .version:               resd 1
    .enabled:               resb 1
    .fail_mode:             resb 1      ; fail-closed or fail-open
    .pad:                   resb 2
    .components:            resd 1      ; bitmask of initialized components
    .spinlock:              resq 1
    .max_targets:           resq 1
    .max_findings:          resq 1
    .max_scans:             resq 1
    .scan_timeout:          resq 1      ; default scan timeout (seconds)
    .pad2:                  resd 2
    .total_targets:         resq 1      ; total targets registered
    .total_scans:           resq 1      ; total scans performed
    .total_findings:        resq 1      ; total findings discovered
    .total_reports:         resq 1      ; total reports generated
    .core_state:            resq 1
    .scanner_state:         resq 1
    .assessor_state:        resq 1
    .database_state:        resq 1
    .reporter_state:        resq 1
endstruc

%endif ; VULN_SCAN_INC
%endif ; GUARD_SECURITY_VULN_SCAN_VULN_SCAN_INC