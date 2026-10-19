%ifndef GUARD_SECURITY_THREAT_INTEL_KILL_CHAIN_ENGINE_ASM
%define GUARD_SECURITY_THREAT_INTEL_KILL_CHAIN_ENGINE_ASM

; =============================================================================
; File     : security/threat_intel/src/kill_chain_engine.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: kill chain engine (kill chain analysis)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_kill_chain_state:     resb threat_intel_state_base_t_size
threat_intel_kill_chain_head:      resq 1
threat_intel_kill_chain_count:     resq 1

section .data
alignb 16
threat_intel_kill_chain_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_kill_chain_init - Initialize kill chain engine
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_kill_chain_init
threat_intel_kill_chain_init:
    push    rbx
    mov     dword [threat_intel_kill_chain_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_kill_chain_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_kill_chain_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_kill_chain_head], 0
    mov     qword [threat_intel_kill_chain_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_kill_chain_shutdown - Shut down kill chain engine
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_kill_chain_shutdown
threat_intel_kill_chain_shutdown:
    push    rbx
    mov     eax, [threat_intel_kill_chain_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_kill_chain_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_kill_chain_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_kill_chain_status - Return current kill chain engine status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_kill_chain_status
threat_intel_kill_chain_status:
    mov     eax, [threat_intel_kill_chain_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_kill_chain_state + threat_intel_state_base_t.enabled]
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
; threat_intel_kill_chain_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_kill_chain_version
threat_intel_kill_chain_version:
    mov     rax, threat_intel_kill_chain_version_str
    ret

; STUB: threat_intel_kill_chain_map - map IOC to kill chain stage
; STUB: threat_intel_kill_chain_get - retrieve kill chain by ID
; STUB: threat_intel_kill_chain_list - list all kill chain mappings
; STUB: threat_intel_kill_chain_get_stats - return kill chain statistics

%endif