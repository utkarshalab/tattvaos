%ifndef GUARD_SECURITY_THREAT_INTEL_STIX_ENGINE_ASM
%define GUARD_SECURITY_THREAT_INTEL_STIX_ENGINE_ASM

; =============================================================================
; File     : security/threat_intel/src/stix_engine.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: STIX 2.1 engine (STIX 2.1 support)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_stix_state:     resb threat_intel_state_base_t_size
threat_intel_stix_head:      resq 1
threat_intel_stix_count:     resq 1

section .data
alignb 16
threat_intel_stix_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_stix_init - Initialize STIX engine
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_stix_init
threat_intel_stix_init:
    push    rbx
    mov     dword [threat_intel_stix_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_stix_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_stix_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_stix_head], 0
    mov     qword [threat_intel_stix_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_stix_shutdown - Shut down STIX engine
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_stix_shutdown
threat_intel_stix_shutdown:
    push    rbx
    mov     eax, [threat_intel_stix_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_stix_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_stix_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_stix_status - Return current STIX engine status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_stix_status
threat_intel_stix_status:
    mov     eax, [threat_intel_stix_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_stix_state + threat_intel_state_base_t.enabled]
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
; threat_intel_stix_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_stix_version
threat_intel_stix_version:
    mov     rax, threat_intel_stix_version_str
    ret

; STUB: threat_intel_stix_import - import STIX data
; STUB: threat_intel_stix_export - export STIX data
; STUB: threat_intel_stix_get - retrieve STIX object by ID
; STUB: threat_intel_stix_list - list all STIX objects
; STUB: threat_intel_stix_get_stats - return STIX statistics

%endif