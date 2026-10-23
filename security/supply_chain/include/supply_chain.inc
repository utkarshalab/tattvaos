%ifndef GUARD_SECURITY_SUPPLY_CHAIN_SUPPLY_CHAIN_INC
%define GUARD_SECURITY_SUPPLY_CHAIN_SUPPLY_CHAIN_INC

; =============================================================================
; File     : security/supply_chain/include/supply_chain.inc
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Supply Chain - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              supply chain component (core, sbom, provenance, attestation,
;              verification).
;
; DESIGN INVARIANT:
;   Supply Chain Security ensures the integrity and provenance of software
;   components from build to deployment. Every artifact is signed, every
;   dependency is tracked in an SBOM, and every build is attested by a trusted
;   signer. Components are verified before loading; unverified components are
;   rejected.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE - full supply chain security feature set including
;         SBOM, provenance tracking, attestation, and component verification
;         defined.
; =============================================================================

%ifndef SUPPLY_CHAIN_INC
%define SUPPLY_CHAIN_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_VERSION_MAJOR   1
%define SUPPLY_CHAIN_VERSION_MINOR   0
%define SUPPLY_CHAIN_VERSION_PATCH   0
%define SUPPLY_CHAIN_VERSION_STR     "1.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_STATE_MAGIC             0x53434841   ; "SCHA"
%define SUPPLY_CHAIN_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_CORE         (1 << 0)
%define SUPPLY_CHAIN_SBOM         (1 << 1)
%define SUPPLY_CHAIN_PROVENANCE   (1 << 2)
%define SUPPLY_CHAIN_ATTESTATION  (1 << 3)
%define SUPPLY_CHAIN_VERIFICATION (1 << 4)
%define SUPPLY_CHAIN_ALL          0x1F

; -----------------------------------------------------------------------------
; Artifact types
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_ARTIFACT_SOURCE     1   ; source code
%define SUPPLY_CHAIN_ARTIFACT_BINARY     2   ; compiled binary
%define SUPPLY_CHAIN_ARTIFACT_LIBRARY    3   ; shared library
%define SUPPLY_CHAIN_ARTIFACT_CONTAINER  4   ; container image
%define SUPPLY_CHAIN_ARTIFACT_CONFIG     5   ; configuration file
%define SUPPLY_CHAIN_ARTIFACT_DOCUMENT   6   ; documentation

; -----------------------------------------------------------------------------
; Artifact states
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_ARTIFACT_UNKNOWN   0
%define SUPPLY_CHAIN_ARTIFACT_TRUSTED   1
%define SUPPLY_CHAIN_ARTIFACT_UNTRUSTED 2
%define SUPPLY_CHAIN_ARTIFACT_REVOKED   3
%define SUPPLY_CHAIN_ARTIFACT_EXPIRED   4

; -----------------------------------------------------------------------------
; Verification status
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_VERIFY_PENDING   1
%define SUPPLY_CHAIN_VERIFY_VERIFIED  2
%define SUPPLY_CHAIN_VERIFY_FAILED    3
%define SUPPLY_CHAIN_VERIFY_SKIPPED   4

; -----------------------------------------------------------------------------
; Error codes
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_ERR_SUCCESS         0
%define SUPPLY_CHAIN_ERR_GENERAL         1
%define SUPPLY_CHAIN_ERR_NOT_INIT        2
%define SUPPLY_CHAIN_ERR_INVALID_ARG     3
%define SUPPLY_CHAIN_ERR_RESOURCE        4
%define SUPPLY_CHAIN_ERR_ACCESS          5
%define SUPPLY_CHAIN_ERR_NOT_FOUND       6
%define SUPPLY_CHAIN_ERR_VERIFY_FAILED   7
%define SUPPLY_CHAIN_ERR_SIGNATURE       8
%define SUPPLY_CHAIN_ERR_CERT_EXPIRED    9

; -----------------------------------------------------------------------------
; SBOM formats
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_SBOM_SPDX   1
%define SUPPLY_CHAIN_SBOM_CYCLONEDX 2
%define SUPPLY_CHAIN_SBOM_SWID    3

; -----------------------------------------------------------------------------
; Signer trust levels
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_TRUST_UNKNOWN  0
%define SUPPLY_CHAIN_TRUST_LOW      1
%define SUPPLY_CHAIN_TRUST_MEDIUM   2
%define SUPPLY_CHAIN_TRUST_HIGH     3
%define SUPPLY_CHAIN_TRUST_ROOT     4

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_DEFAULT_MAX_ARTIFACTS   100000
%define SUPPLY_CHAIN_DEFAULT_MAX_SBOMS       10000
%define SUPPLY_CHAIN_DEFAULT_MAX_ATTESTATIONS 50000
%define SUPPLY_CHAIN_DEFAULT_MAX_PROVENANCE  50000

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro SUPPLY_CHAIN_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro SUPPLY_CHAIN_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define SUPPLY_CHAIN_LIST_INIT(head)  head

%macro SUPPLY_CHAIN_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro SUPPLY_CHAIN_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro SUPPLY_CHAIN_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc supply_chain_state_base_t
    .magic:         resd 1      ; SUPPLY_CHAIN_STATE_MAGIC for validation
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
; Artifact record
; -----------------------------------------------------------------------------
struc supply_chain_artifact_t
    .artifact_id:   resq 1      ; unique artifact identifier
    .type:          resd 1      ; SUPPLY_CHAIN_ARTIFACT_*
    .name:          resb 256    ; NUL-terminated artifact name
    .version:       resb 128    ; NUL-terminated artifact version
    .hash_alg:      resd 1      ; hash algorithm used
    .hash_value:    resb 64     ; hash value (SHA-256)
    .size_bytes:    resq 1      ; artifact size in bytes
    .state:         resd 1      ; SUPPLY_CHAIN_ARTIFACT_*
    .trust_level:   resd 1      ; SUPPLY_CHAIN_TRUST_*
    .created_ns:    resq 1      ; creation timestamp
    .expires_ns:    resq 1      ; expiration timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; SBOM record
; -----------------------------------------------------------------------------
struc supply_chain_sbom_t
    .sbom_id:       resq 1      ; unique SBOM identifier
    .artifact_id:   resq 1      ; associated artifact identifier
    .format:        resd 1      ; SUPPLY_CHAIN_SBOM_*
    .component_count: resq 1     ; number of components
    .generated_ns:  resq 1      ; generation timestamp
    .path:          resb 512    ; NUL-terminated SBOM file path
    .signed:        resb 1      ; SBOM is cryptographically signed
    .pad:           resb 7      ; alignment
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Provenance record
; -----------------------------------------------------------------------------
struc supply_chain_provenance_t
    .provenance_id: resq 1      ; unique provenance identifier
    .artifact_id:   resq 1      ; associated artifact identifier
    .signer_id:     resq 1      ; signer identifier
    .build_env:     resb 256    ; NUL-terminated build environment
    .build_tools:   resb 512    ; NUL-terminated build tools
    .build_ns:      resq 1      ; build timestamp
    .materials:     resb 1024   ; NUL-terminated build materials list
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Attestation record
; -----------------------------------------------------------------------------
struc supply_chain_attestation_t
    .attestation_id: resq 1     ; unique attestation identifier
    .artifact_id:    resq 1     ; associated artifact identifier
    .signer_id:      resq 1     ; signer identifier
    .signature_alg:  resd 1     ; signature algorithm
    .signature:      resb 64    ; cryptographic signature
    .signed_ns:      resq 1     ; signing timestamp
    .expires_ns:     resq 1     ; signature expiration
    .next:           resq 1     ; linked list
endstruc

; -----------------------------------------------------------------------------
; Verification record
; -----------------------------------------------------------------------------
struc supply_chain_verification_t
    .verification_id: resq 1    ; unique verification identifier
    .artifact_id:     resq 1    ; associated artifact identifier
    .verifier_id:     resq 1    ; verifier identifier
    .status:          resd 1    ; SUPPLY_CHAIN_VERIFY_*
    .verified_ns:     resq 1    ; verification timestamp
    .error_msg:       resb 256  ; NUL-terminated error message (if failed)
    .next:            resq 1    ; linked list
endstruc

; -----------------------------------------------------------------------------
; Global Supply Chain state
; -----------------------------------------------------------------------------
struc supply_chain_global_state_t
    .magic:                 resd 1
    .version:               resd 1
    .enabled:               resb 1
    .fail_mode:             resb 1      ; fail-closed or fail-open
    .pad:                   resb 2
    .components:            resd 1      ; bitmask of initialized components
    .spinlock:              resq 1
    .max_artifacts:         resq 1
    .max_sboms:             resq 1
    .max_attestations:      resq 1
    .max_provenance:        resq 1
    .pad2:                  resd 2
    .total_artifacts:       resq 1      ; total artifacts tracked
    .total_sboms:           resq 1      ; total SBOMs generated
    .total_attestations:    resq 1      ; total attestations created
    .total_provenance:      resq 1      ; total provenance records
    .total_verifications:   resq 1      ; total verifications performed
    .total_rejected:        resq 1      ; total artifacts rejected
    .core_state:            resq 1
    .sbom_state:            resq 1
    .provenance_state:      resq 1
    .attestation_state:     resq 1
    .verification_state:    resq 1
endstruc

%endif ; SUPPLY_CHAIN_INC
%endif ; GUARD_SECURITY_SUPPLY_CHAIN_SUPPLY_CHAIN_INC