%ifndef GUARD_SECURITY_SOAR_SRC_THREAT_INTEL_INTEGRATION_ASM
%define GUARD_SECURITY_SOAR_SRC_THREAT_INTEL_INTEGRATION_ASM

; =============================================================================
; File     : security/soar/src/threat_intel_integration.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: SOAR Threat Intel Integration - connects to threat intelligence
;              feeds, enriches alerts with IOC data, and correlates against
;              known threats.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/soar.inc"

section .bss
alignb 16
soar_ti_state:        resb soar_state_base_t_size
soar_ti_feed_head:    resq 1
soar_ti_feed_count:   resq 1

section .data
alignb 16
soar_ti_version_str:  db SOAR_VERSION_STR, 0

section .text

; =============================================================================
; soar_threat_intel_init - Initialize threat intel integration
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global soar_threat_intel_init
soar_threat_intel_init:
    push    rbx
    mov     dword [soar_ti_state + soar_state_base_t.magic], SOAR_STATE_MAGIC
    mov     dword [soar_ti_state + soar_state_base_t.version], SOAR_VERSION_MAJOR
    mov     byte [soar_ti_state + soar_state_base_t.enabled], 1
    mov     qword [soar_ti_feed_head], 0
    mov     qword [soar_ti_feed_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; soar_threat_intel_shutdown - Shut down threat intel integration
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global soar_threat_intel_shutdown
soar_threat_intel_shutdown:
    push    rbx
    mov     eax, [soar_ti_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init
    mov     dword [soar_ti_state + soar_state_base_t.magic], SOAR_STATE_MAGIC_FREED
    mov     byte [soar_ti_state + soar_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; soar_threat_intel_status - Return current threat intel integration status
; Input:  none
; Output: rax = status code
; =============================================================================
global soar_threat_intel_status
soar_threat_intel_status:
    mov     eax, [soar_ti_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init
    mov     al, [soar_ti_state + soar_state_base_t.enabled]
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
; soar_threat_intel_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global soar_threat_intel_version
soar_threat_intel_version:
    mov     rax, soar_ti_version_str
    ret

; =============================================================================
; soar_threat_intel_enrich_alert - Enrich alert with threat intel IOC data
; Input:  rdi = alert context pointer, rsi = alert type,
;         rdx = severity, rcx = source IP
; Output: rax = enrichment score (0-100), rbx = matched IOC count
; =============================================================================
global soar_threat_intel_enrich_alert
soar_threat_intel_enrich_alert:
    push    rbx
    push    r12

    mov     eax, [soar_ti_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save alert context pointer

    ; STUB: query threat intel feeds for IOC matches
    ; STEP: match source/dest IP against known IOCs
    ; STEP: match domains, URLs, file hashes
    ; STEP: calculate enrichment confidence score
    ; STEP: attach IOC data to alert context

    xor     eax, eax               ; STUB: no enrichment match
    xor     rbx, rbx
    jmp     .done

.err_component_down:
    mov     rax, -1
    xor     rbx, rbx
    jmp     .done
.err_invalid_arg:
    mov     rax, -2
    xor     rbx, rbx
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: soar_threat_intel_subscribe_feed - subscribe to a threat intel feed
; STUB: soar_threat_intel_unsubscribe_feed - unsubscribe from a feed
; STUB: soar_threat_intel_get_ioc - retrieve IOC by indicator
; STUB: soar_threat_intel_list_iocs - list all IOCs
; STUB: soar_threat_intel_get_stats - return integration statistics

%endif