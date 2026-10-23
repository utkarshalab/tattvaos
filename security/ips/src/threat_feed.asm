%ifndef GUARD_SECURITY_IPS_SRC_THREAT_FEED_ASM
%define GUARD_SECURITY_IPS_SRC_THREAT_FEED_ASM

; =============================================================================
; File     : security/ips/src/threat_feed.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Threat Feed - threat intelligence integration. Ingests
;              STIX/TAXII feeds, IOC lists, and reputation data. Correlates
;              observed traffic against known threat indicators.
; Status   : PREMIUM ENTERPRISE - feed management, IOC checking,
;             authenticated feed downloads defined.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_threat_feed_state:       resb ips_state_base_t_size
ips_threat_feed_feed_head:   resq 1      ; threat feed linked list
ips_threat_feed_feed_count:  resq 1
ips_threat_feed_ioc_head:    resq 1      ; IOC linked list
ips_threat_feed_ioc_count:   resq 1

section .data
alignb 16
ips_threat_feed_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_threat_feed_init - Initialize threat feed component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_threat_feed_init
ips_threat_feed_init:
    push    rbx

    mov     dword [ips_threat_feed_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_threat_feed_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_threat_feed_state + ips_state_base_t.enabled], 1

    mov     qword [ips_threat_feed_feed_head], 0
    mov     qword [ips_threat_feed_feed_count], 0
    mov     qword [ips_threat_feed_ioc_head], 0
    mov     qword [ips_threat_feed_ioc_count], 0

    ; STUB: allocate threat feed memory pool
    ; STUB: configure feed URLs and authentication
    ; STUB: load existing IOC database
    ; STUB: schedule feed updates

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_threat_feed_shutdown - Shut down threat feed component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_threat_feed_shutdown
ips_threat_feed_shutdown:
    push    rbx

    mov     eax, [ips_threat_feed_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: free all threat feeds
    ; STUB: free all IOC entries
    ; STUB: cancel scheduled updates

    mov     dword [ips_threat_feed_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_threat_feed_state + ips_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_threat_feed_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_threat_feed_status
ips_threat_feed_status:
    mov     eax, [ips_threat_feed_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_threat_feed_state + ips_state_base_t.enabled]
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
; ips_threat_feed_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_threat_feed_version
ips_threat_feed_version:
    mov     rax, ips_threat_feed_version_str
    ret

; =============================================================================
; ips_threat_feed_update - Update threat feeds from configured sources
; Input:  none
; Output: rax = number of new IOCs (positive) or negative on error
; =============================================================================
global ips_threat_feed_update
ips_threat_feed_update:
    push    rbx

    mov     eax, [ips_threat_feed_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    ; STUB: connect to each configured feed URL
    ; STUB: authenticate if required
    ; STUB: download and parse IOCs (STIX/TAXII/CSV/etc.)
    ; STUB: insert new IOCs into database
    ; STUB: mark stale IOCs for removal
    ; For skeleton: no new IOCs
    xor     eax, eax
    pop     rbx
    ret

.err_component_down:
    mov     rax, -2
    pop     rbx
    ret

; =============================================================================
; ips_threat_feed_check_ioc - Check an indicator against threat feeds
; Input:  rdi = IOC type (1=IP, 2=domain, 3=URL, 4=hash),
;         rsi = IOC value pointer (NUL-terminated)
; Output: rax = 1 if malicious, 0 if clean, -1 if unknown,
;         rbx = threat score (0-100), rcx = feed source ID
; =============================================================================
global ips_threat_feed_check_ioc
ips_threat_feed_check_ioc:
    push    rbx

    mov     eax, [ips_threat_feed_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rsi, rsi
    jz      .err_invalid

    ; STUB: search IOC database for match
    ; STUB: return malicious/clean/unknown status
    ; For skeleton: IOC unknown
    mov     rax, -1   ; unknown
    xor     rbx, rbx
    xor     rcx, rcx
    jmp .done

.err_component_down:
    mov     rax, -2
    xor     rbx, rbx
    xor     rcx, rcx
    jmp .done
.err_invalid:
    mov     rax, -3
    xor     rbx, rbx
    xor     rcx, rcx
    jmp .done

.done:
    pop     rbx
    ret

%endif
