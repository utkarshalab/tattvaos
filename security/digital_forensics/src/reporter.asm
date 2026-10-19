%ifndef GUARD_SECURITY_DIGITAL_FORENSICS_REPORTER_ASM
%define GUARD_SECURITY_DIGITAL_FORENSICS_REPORTER_ASM

; =============================================================================
; File     : security/digital_forensics/src/reporter.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: forensic report generator (machine + human readable)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/dfir.inc"

section .bss
alignb 16
dfir_reporter_state:     resb dfir_state_base_t_size
dfir_reporter_report_head: resq 1
dfir_reporter_report_count: resq 1

section .data
alignb 16
dfir_reporter_version_str: db DFIR_VERSION_STR, 0

section .text

; =============================================================================
; dfir_reporter_init - Initialize forensic report generator
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global dfir_reporter_init
dfir_reporter_init:
    push    rbx
    mov     dword [dfir_reporter_state + dfir_state_base_t.magic], DFIR_STATE_MAGIC
    mov     dword [dfir_reporter_state + dfir_state_base_t.version], DFIR_VERSION_MAJOR
    mov     byte [dfir_reporter_state + dfir_state_base_t.enabled], 1
    mov     qword [dfir_reporter_report_head], 0
    mov     qword [dfir_reporter_report_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; dfir_reporter_shutdown - Shut down forensic report generator
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global dfir_reporter_shutdown
dfir_reporter_shutdown:
    push    rbx
    mov     eax, [dfir_reporter_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init
    mov     dword [dfir_reporter_state + dfir_state_base_t.magic], DFIR_STATE_MAGIC_FREED
    mov     byte [dfir_reporter_state + dfir_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; dfir_reporter_status - Return current forensic report generator status
; Input:  none
; Output: rax = status code
; =============================================================================
global dfir_reporter_status
dfir_reporter_status:
    mov     eax, [dfir_reporter_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init
    mov     al, [dfir_reporter_state + dfir_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_init:
    mov     eax, -2
    ret

; =============================================================================
; dfir_reporter_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global dfir_reporter_version
dfir_reporter_version:
    mov     rax, dfir_reporter_version_str
    ret

; =============================================================================
; dfir_reporter_generate_pdf - Generate PDF forensic report
; Input:  rdi = case ID, rsi = output path pointer,
;         rdx = output path length
; Output: rax = report ID on success, negative error code on failure
; =============================================================================
global dfir_reporter_generate_pdf
dfir_reporter_generate_pdf:
    push    rbx
    push    r12

    mov     eax, [dfir_reporter_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rsi              ; save output path

    ; STEP 1: Validate case ID exists
    ; STEP 2: Gather case details, evidence list, analyses, custody entries
    ; STEP 3: Render PDF report with header, evidence table, timeline, findings
    ; STEP 4: Cryptographically sign report
    ; STEP 5: Write PDF to output path
    ; STEP 6: Create report record and increment counter

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

; =============================================================================
; dfir_reporter_generate_json - Generate JSON forensic report
; Input:  rdi = case ID, rsi = output path pointer,
;         rdx = output path length
; Output: rax = report ID on success, negative error code on failure
; =============================================================================
global dfir_reporter_generate_json
dfir_reporter_generate_json:
    push    rbx

    mov     eax, [dfir_reporter_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    ; STEP 1: Validate case ID exists
    ; STEP 2: Serialize case data to JSON structure
    ; STEP 3: Include evidence hashes, custody chain, analysis verdicts
    ; STEP 4: Sign JSON report
    ; STEP 5: Write JSON to output path

    mov     rax, 2               ; STUB: return report ID 2
    pop     rbx
    ret

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    pop     rbx
    ret

; =============================================================================
; dfir_reporter_generate_html - Generate HTML forensic report
; Input:  rdi = case ID, rsi = output path pointer,
;         rdx = output path length
; Output: rax = report ID on success, negative error code on failure
; =============================================================================
global dfir_reporter_generate_html
dfir_reporter_generate_html:
    push    rbx

    mov     eax, [dfir_reporter_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    ; STEP 1: Validate case ID exists
    ; STEP 2: Render HTML report with CSS styling
    ; STEP 3: Include interactive timeline and evidence gallery
    ; STEP 4: Sign HTML report
    ; STEP 5: Write HTML to output path

    mov     rax, 3               ; STUB: return report ID 3
    pop     rbx
    ret

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: dfir_reporter_sign_report - cryptographically sign report file
; STUB: dfir_reporter_verify_report - verify report signature
; STUB: dfir_reporter_list_reports - list reports for a case
; STUB: dfir_reporter_get_report - retrieve report by ID
; STUB: dfir_reporter_export_case_package - export complete case package
; STUB: dfir_reporter_get_stats - return report statistics

%endif