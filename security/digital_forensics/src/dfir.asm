%ifndef GUARD_SECURITY_DIGITAL_FORENSICS_DFIR_ASM
%define GUARD_SECURITY_DIGITAL_FORENSICS_DFIR_ASM

; =============================================================================
; File     : security/digital_forensics/src/dfir.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Digital Forensics & Incident Response - main dispatcher.
;              Coordinates evidence acquisition, forensic analysis,
;              chain-of-custody management, and forensic reporting.
; Status   : PREMIUM ENTERPRISE SKELETON - full state machine, component
;              lifecycle, evidence management, and data structures for 5
;              components. Logic bodies marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/dfir.inc"

section .bss
alignb 16
dfir_global_state:  resb dfir_global_state_t_size   ; zero-initialized global state

section .data
alignb 16
dfir_version_str:   db DFIR_VERSION_STR, 0

section .text

; =============================================================================
; dfir_init - Initialize Digital Forensics subsystem
; Input:  none
; Output: rax = 0 on success, negative error code on failure
;         Initializes global state, loads config, registers components in
;         dependency order: custody -> acquirer -> analyzer -> reporter.
; =============================================================================
global dfir_init
dfir_init:
    push    rbx
    push    r12
    push    r13
    push    r14

    ; Double-init guard: check magic
    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    ; Zero the global state structure
    xor     eax, eax
    mov     rcx, dfir_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, dfir_global_state
    rep     stosd

    ; Set magic and version
    mov     eax, DFIR_STATE_MAGIC
    mov     dword [dfir_global_state + dfir_global_state_t.magic], eax
    mov     eax, (DFIR_VERSION_MAJOR << 16) | DFIR_VERSION_MINOR
    mov     [dfir_global_state + dfir_global_state_t.version], eax

    ; Set default configuration values
    mov     rax, DFIR_DEFAULT_MAX_EVIDENCE
    mov     qword [dfir_global_state + dfir_global_state_t.max_evidence], rax
    mov     rax, DFIR_DEFAULT_MAX_CASES
    mov     qword [dfir_global_state + dfir_global_state_t.max_cases], rax
    mov     rax, DFIR_DEFAULT_MAX_CUSTODY_ENTRIES
    mov     qword [dfir_global_state + dfir_global_state_t.max_custody_entries], rax
    mov     eax, DFIR_DEFAULT_HASH_ALGORITHM
    mov     dword [dfir_global_state + dfir_global_state_t.default_hash_alg], eax
    mov     dword [dfir_global_state + dfir_global_state_t.write_blocked], DFIR_DEFAULT_WRITE_BLOCKED

    ; Default fail mode: CLOSED (secure)
    mov     dword [dfir_global_state + dfir_global_state_t.fail_mode], 0

    ; STUB: register components in dependency order:
    ;   custody -> acquirer -> analyzer -> reporter
    ; Each component's init() must succeed before proceeding to the next.

    mov     byte [dfir_global_state + dfir_state_base_t.enabled], 1
    xor     eax, eax             ; success
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_shutdown - Shut down Digital Forensics
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global dfir_shutdown
dfir_shutdown:
    push    rbx

    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init

    mov     dword [dfir_global_state + dfir_global_state_t.magic], DFIR_STATE_MAGIC_FREED
    mov     byte [dfir_global_state + dfir_state_base_t.enabled], 0
    xor     eax, eax
.not_init:
    pop     rbx
    ret

; =============================================================================
; dfir_status - Return current Digital Forensics status
; Input:  none
; Output: rax = status code (0 = enabled, nonzero = disabled/not initialized)
; =============================================================================
global dfir_status
dfir_status:
    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [dfir_global_state + dfir_state_base_t.enabled]
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
; dfir_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global dfir_version
dfir_version:
    mov     rax, dfir_version_str
    ret

; =============================================================================
; dfir_create_case - Create a new forensic case
; Input:  rdi = case title pointer, rsi = investigator pointer,
;         rdx = title length, rcx = investigator length
; Output: rax = case ID on success, negative error code on failure
; =============================================================================
global dfir_create_case
dfir_create_case:
    push    rbx
    push    r12
    push    r13

    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg
    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save case title pointer

    ; STUB: allocate case record from pool
    ; STUB: validate title/investigator length
    ; STUB: assign case ID (increment counter)
    ; STUB: insert into case linked list
    ; STUB: set created_ns timestamp
    ; STUB: increment total_cases counter

    mov     rax, 1               ; STUB: return case ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, DFIR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_acquire_evidence - Acquire evidence from a source
; Input:  rdi = case ID, rsi = source path pointer,
;         rdx = source path length, rcx = acquisition type (DFIR_ACQ_*)
; Output: rax = evidence ID on success, negative error code on failure
; =============================================================================
global dfir_acquire_evidence
dfir_acquire_evidence:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save case ID
    mov     r13, rsi              ; save source path

    ; STEP 1: Validate case exists
    ; STEP 2: Check write-blocked mode
    ; STEP 3: Compute hash of source (SHA-256/SHA-512/BLAKE3)
    ; STEP 4: Acquire evidence (write-blocked where possible)
    ; STEP 5: Store evidence record
    ; STEP 6: Create custody entry (COLLECT action)
    ; STEP 7: Increment total_evidence counter

    mov     rax, 1               ; STUB: return evidence ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, DFIR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_analyze_evidence - Analyze evidence for forensic artifacts
; Input:  rdi = evidence ID, rsi = analyzer type,
;         rdx = analysis depth
; Output: rax = analysis ID on success, negative error code on failure
; =============================================================================
global dfir_analyze_evidence
dfir_analyze_evidence:
    push    rbx
    push    r12

    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: validate evidence ID exists
    ; STUB: resolve analyzer component
    ; STUB: call dfir_analyzer_run(evidence_id, analyzer_type, depth)
    ; STEP: store analysis result
    ; STEP: increment total_analyses counter

    mov     rax, 1               ; STUB: return analysis ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_custody_transfer - Record chain-of-custody transfer
; Input:  rdi = evidence ID, rsi = actor pointer,
;         rdx = action (DFIR_CUSTODY_*), rcx = location pointer
; Output: rax = entry ID on success, negative error code on failure
; =============================================================================
global dfir_custody_transfer
dfir_custody_transfer:
    push    rbx
    push    r12
    push    r13

    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save evidence ID
    mov     r13, rsi              ; save actor pointer

    ; STEP 1: Validate evidence ID exists
    ; STEP 2: Create custody entry record
    ; STEP 3: Cryptographically sign custody entry
    ; STEP 4: Link entry to evidence chain
    ; STEP 5: Increment total_custody_entries counter

    mov     rax, 1               ; STUB: return entry ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, DFIR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_generate_report - Generate forensic report for a case
; Input:  rdi = case ID, rsi = report format,
;         rdx = output path pointer
; Output: rax = report ID on success, negative error code on failure
; =============================================================================
global dfir_generate_report
dfir_generate_report:
    push    rbx
    push    r12

    mov     eax, [dfir_global_state + dfir_global_state_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rdx, rdx
    jz      .err_invalid_arg

    mov     r12, rdx              ; save output path

    ; STEP 1: Validate case ID exists
    ; STEP 2: Gather all evidence for case
    ; STEP 3: Gather all analyses for case
    ; STEP 4: Gather all custody entries for case
    ; STEP 5: Render report in requested format
    ; STEP 6: Cryptographically sign report
    ; STEP 7: Write report to output path
    ; STEP 8: Increment total_reports counter

    mov     rax, 1               ; STUB: return report ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, DFIR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: dfir_verify_evidence_integrity - verify evidence hash integrity
; STUB: dfir_list_cases - enumerate all cases
; STUB: dfir_list_evidence - enumerate evidence for a case
; STUB: dfir_list_custody - enumerate custody entries for evidence
; STUB: dfir_close_case - close and archive a case
; STUB: dfir_destroy_evidence - securely destroy evidence
; STUB: dfir_export_case - export case package for legal proceedings
; STUB: dfir_acquire_network - acquire network traffic capture
; STUB: dfir_acquire_mobile - acquire mobile device image
; STUB: dfir_analyze_memory - analyze memory image for artifacts
; STUB: dfir_analyze_network - analyze network capture for indicators
; STUB: dfir_custody_export_chain - export custody chain for legal proceedings
; STUB: dfir_custody_get_entry - retrieve custody entry by ID
; STUB: dfir_reporter_sign_report - cryptographically sign report file
; STUB: dfir_reporter_verify_report - verify report signature
; STUB: dfir_reporter_list_reports - list reports for a case
; STUB: dfir_reporter_get_report - retrieve report by ID
; STUB: dfir_reporter_export_case_package - export complete case package
; STUB: dfir_reporter_get_stats - return report statistics
; STUB: dfir_core_register_component - register component with core
; STUB: dfir_core_health_check - evaluate component health status
; STUB: dfir_core_reload_config - hot-reload forensic configuration
; STUB: dfir_core_metrics_export - emit core metrics to SIEM
; STUB: dfir_core_graceful_degrade - fail-safe degradation path
; STUB: dfir_core_archive_case - archive closed case to cold storage
; STUB: dfir_acquirer_acquire_network_tap - acquire from network tap
; STUB: dfir_acquirer_acquire_cloud_snapshot - acquire cloud VM snapshot
; STUB: dfir_acquirer_acquire_removable_media - acquire USB/removable media
; STUB: dfir_analyzer_recover_deleted - recover deleted files from slack space
; STUB: dfir_analyzer_extract_metadata - extract file metadata (EXIF, etc.)
; STUB: dfir_analyzer_detect_encryption - detect encrypted containers
; STUB: dfir_analyzer_crack_password - attempt password cracking (dictionary)

%endif