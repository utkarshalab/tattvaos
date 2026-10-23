%ifndef GUARD_SECURITY_THREAT_INTEL_CAMPAIGN_TRACKER_ASM
%define GUARD_SECURITY_THREAT_INTEL_CAMPAIGN_TRACKER_ASM

; =============================================================================
; File     : security/threat_intel/src/campaign_tracker.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: campaign tracking (threat campaign tracking)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_campaign_state:     resb threat_intel_state_base_t_size
threat_intel_campaign_head:      resq 1
threat_intel_campaign_count:     resq 1

section .data
alignb 16
threat_intel_campaign_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_campaign_init - Initialize campaign tracking
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_campaign_init
threat_intel_campaign_init:
    push    rbx
    mov     dword [threat_intel_campaign_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_campaign_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_campaign_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_campaign_head], 0
    mov     qword [threat_intel_campaign_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_campaign_shutdown - Shut down campaign tracking
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_campaign_shutdown
threat_intel_campaign_shutdown:
    push    rbx
    mov     eax, [threat_intel_campaign_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_campaign_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_campaign_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_campaign_status - Return current campaign tracking status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_campaign_status
threat_intel_campaign_status:
    mov     eax, [threat_intel_campaign_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_campaign_state + threat_intel_state_base_t.enabled]
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
; threat_intel_campaign_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_campaign_version
threat_intel_campaign_version:
    mov     rax, threat_intel_campaign_version_str
    ret

; STUB: threat_intel_campaign_create - create campaign
; STUB: threat_intel_campaign_get - retrieve campaign by ID
; STUB: threat_intel_campaign_list - list all campaigns
; STUB: threat_intel_campaign_get_stats - return campaign statistics

%endif