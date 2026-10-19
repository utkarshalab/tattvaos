%ifndef GUARD_SECURITY_THREAT_INTEL_INGESTOR_ASM
%define GUARD_SECURITY_THREAT_INTEL_INGESTOR_ASM

; =============================================================================
; File     : security/threat_intel/src/ingestor.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: threat feed ingestor (STIX/TAXII, CSV, JSON)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_ingestor_state:      resb threat_intel_state_base_t_size
threat_intel_ingestor_feed_head:  resq 1
threat_intel_ingestor_feed_count: resq 1

section .data
alignb 16
threat_intel_ingestor_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_ingestor_init - Initialize threat feed ingestor
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_ingestor_init
threat_intel_ingestor_init:
    push    rbx
    mov     dword [threat_intel_ingestor_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_ingestor_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_ingestor_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_ingestor_feed_head], 0
    mov     qword [threat_intel_ingestor_feed_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_ingestor_shutdown - Shut down threat feed ingestor
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_ingestor_shutdown
threat_intel_ingestor_shutdown:
    push    rbx
    mov     eax, [threat_intel_ingestor_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_ingestor_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_ingestor_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_ingestor_status - Return current threat feed ingestor status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_ingestor_status
threat_intel_ingestor_status:
    mov     eax, [threat_intel_ingestor_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_ingestor_state + threat_intel_state_base_t.enabled]
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
; threat_intel_ingestor_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_ingestor_version
threat_intel_ingestor_version:
    mov     rax, threat_intel_ingestor_version_str
    ret

; =============================================================================
; threat_intel_ingestor_pull_feed - Pull a threat feed from remote source
; Input:  rdi = feed URL pointer, rsi = feed type (TI_FEED_*),
;         rdx = API key pointer (optional), rcx = API key length
; Output: rax = number of IOCs ingested, negative on failure
; =============================================================================
global threat_intel_ingestor_pull_feed
threat_intel_ingestor_pull_feed:
    push    rbx
    push    r12
    push    r13

    mov     eax, [threat_intel_ingestor_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save feed URL

    ; STUB: validate feed type (TI_FEED_STIX, TAXII, CSV, JSON, PROPRIETARY)
    ; STEP: establish network connection to feed URL
    ; STEP: if API key provided, set authentication header
    ; STEP: download feed content into buffer
    ; STEP: parse feed according to feed_type
    ; STEP: for each IOC in feed:
    ;       - normalize to common schema (ti_ioc_t)
    ;       - set feed_source field
    ;       - call threat_intel_add_ioc()
    ; STEP: update feed record (last_pull, ioc_count, error_count)
    ; STEP: return number of IOCs ingested

    xor     eax, eax
    jmp     .done

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, THREAT_INTEL_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_ingestor_push_feed - Push IOCs to a remote feed
; Input:  rdi = feed URL pointer, rsi = IOC batch pointer,
;         rdx = IOC batch length
; Output: rax = number of IOCs pushed, negative on failure
; =============================================================================
global threat_intel_ingestor_push_feed
threat_intel_ingestor_push_feed:
    push    rbx

    mov     eax, [threat_intel_ingestor_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: serialize IOC batch to feed format
    ; STEP: push to remote feed endpoint
    ; STEP: return number of IOCs pushed

    xor     eax, eax
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; =============================================================================
; threat_intel_ingestor_verify_signature - Verify cryptographic signature of feed
; Input:  rdi = data pointer, rsi = data length,
;         rdx = signature pointer, rcx = signature length
; Output: rax = 1 if valid, 0 if invalid, negative on error
; =============================================================================
global threat_intel_ingestor_verify_signature
threat_intel_ingestor_verify_signature:
    push    rbx

    mov     eax, [threat_intel_ingestor_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: load feed signing key
    ; STEP: verify signature over data
    ; STEP: return 1 if valid, 0 if invalid

    mov     eax, 0               ; STUB: signature verification not implemented
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: threat_intel_ingestor_normalize - normalize raw IOC to common schema
; STUB: threat_intel_ingestor_deduplicate - remove duplicate IOCs
; STUB: threat_intel_ingestor_validate - validate IOC fields
; STUB: threat_intel_ingestor_schedule - schedule next feed pull
; STUB: threat_intel_ingestor_backoff - apply exponential backoff on errors

%endif