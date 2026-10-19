%ifndef GUARD_SECURITY_THREAT_INTEL_DEDUP_ENGINE_ASM
%define GUARD_SECURITY_THREAT_INTEL_DEDUP_ENGINE_ASM

; =============================================================================
; File     : security/threat_intel/src/dedup_engine.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IOC deduplication engine (IOC deduplication)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_dedup_state:     resb threat_intel_state_base_t_size
threat_intel_dedup_head:      resq 1
threat_intel_dedup_count:     resq 1

section .data
alignb 16
threat_intel_dedup_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_dedup_init - Initialize IOC deduplication engine
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_dedup_init
threat_intel_dedup_init:
    push    rbx
    mov     dword [threat_intel_dedup_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_dedup_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_dedup_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_dedup_head], 0
    mov     qword [threat_intel_dedup_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_dedup_shutdown - Shut down IOC deduplication engine
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_dedup_shutdown
threat_intel_dedup_shutdown:
    push    rbx
    mov     eax, [threat_intel_dedup_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_dedup_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_dedup_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_dedup_status - Return current IOC deduplication engine status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_dedup_status
threat_intel_dedup_status:
    mov     eax, [threat_intel_dedup_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_dedup_state + threat_intel_state_base_t.enabled]
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
; threat_intel_dedup_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_dedup_version
threat_intel_dedup_version:
    mov     rax, threat_intel_dedup_version_str
    ret

; STUB: threat_intel_dedup_deduplicate - deduplicate IOCs
; STUB: threat_intel_dedup_get - retrieve dedup record by ID
; STUB: threat_intel_dedup_list - list all dedup records
; STUB: threat_intel_dedup_get_stats - return dedup statistics

%endif