%ifndef GUARD_SECURITY_THREAT_INTEL_FALSE_POSITIVE_REDUCER_ASM
%define GUARD_SECURITY_THREAT_INTEL_FALSE_POSITIVE_REDUCER_ASM

; =============================================================================
; File     : security/threat_intel/src/false_positive_reducer.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: false positive reducer (false positive detection logic)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_false_positive_state:     resb threat_intel_state_base_t_size
threat_intel_false_positive_head:      resq 1
threat_intel_false_positive_count:     resq 1

section .data
alignb 16
threat_intel_false_positive_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_false_positive_init - Initialize false positive reducer
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_false_positive_init
threat_intel_false_positive_init:
    push    rbx
    mov     dword [threat_intel_false_positive_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_false_positive_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_false_positive_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_false_positive_head], 0
    mov     qword [threat_intel_false_positive_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_false_positive_shutdown - Shut down false positive reducer
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_false_positive_shutdown
threat_intel_false_positive_shutdown:
    push    rbx
    mov     eax, [threat_intel_false_positive_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_false_positive_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_false_positive_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_false_positive_status - Return current false positive reducer status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_false_positive_status
threat_intel_false_positive_status:
    mov     eax, [threat_intel_false_positive_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_false_positive_state + threat_intel_state_base_t.enabled]
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
; threat_intel_false_positive_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_false_positive_version
threat_intel_false_positive_version:
    mov     rax, threat_intel_false_positive_version_str
    ret

; =============================================================================
; threat_intel_false_positive_reduce - Reduce false positives in findings
; Input:  rdi = finding ID, rsi = confidence score,
;         rdx = context pointer
; Output: rax = updated confidence score (0-100)
; =============================================================================
global threat_intel_false_positive_reduce
threat_intel_false_positive_reduce:
    push    rbx

    mov     eax, [threat_intel_false_positive_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: load finding by ID
    ; STEP: analyze finding context for false positive indicators
    ; STEP: adjust confidence score downward if false positive detected
    ; STEP: return adjusted confidence score

    mov     eax, 50               ; STUB: default medium confidence
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: threat_intel_false_positive_list - list all false positives
; STUB: threat_intel_false_positive_get - retrieve false positive by ID
; STUB: threat_intel_false_positive_add_rule - add false positive rule
; STUB: threat_intel_false_positive_remove_rule - remove false positive rule
; STUB: threat_intel_false_positive_get_stats - return false positive statistics

%endif