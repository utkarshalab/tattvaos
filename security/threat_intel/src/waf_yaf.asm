%ifndef GUARD_SECURITY_VULN_SCAN_WAF_YAF_ASM
%define GUARD_SECURITY_VULN_SCAN_WAF_YAF_ASM

; =============================================================================
; File     : security/vuln_scan/src/waf_yaf.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: vulnerability scanner WAF YARA rule engine
; Status   : PREMIUM ENTERPRISE - skeleton with full API surface.
; =============================================================================

bits 64
DEFAULT REL

%include "include/vuln_scan.inc"

section .bss
alignb 16
vs_waf_yaf_state:     resb vuln_scan_state_base_t_size
vs_waf_yaf_rule_head: resq 1
vs_waf_yaf_rule_count: resq 1

section .data
alignb 16
vs_waf_yaf_version_str: db VULN_SCAN_VERSION_STR, 0

section .text

; =============================================================================
; vs_waf_yaf_init - Initialize WAF YARA rule engine
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global vs_waf_yaf_init
vs_waf_yaf_init:
    push    rbx
    mov     dword [vs_waf_yaf_state + vuln_scan_state_base_t.magic], VULN_SCAN_STATE_MAGIC
    mov     dword [vs_waf_yaf_state + vuln_scan_state_base_t.version], VULN_SCAN_VERSION_MAJOR
    mov     byte [vs_waf_yaf_state + vuln_scan_state_base_t.enabled], 1
    mov     qword [vs_waf_yaf_rule_head], 0
    mov     qword [vs_waf_yaf_rule_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; vs_waf_yaf_shutdown - Shut down WAF YARA rule engine
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global vs_waf_yaf_shutdown
vs_waf_yaf_shutdown:
    push    rbx
    mov     eax, [vs_waf_yaf_state + vuln_scan_state_base_t.magic]
    cmp     eax, VULN_SCAN_STATE_MAGIC
    jnz     .not_init
    mov     dword [vs_waf_yaf_state + vuln_scan_state_base_t.magic], VULN_SCAN_STATE_MAGIC_FREED
    mov     byte [vs_waf_yaf_state + vuln_scan_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; vs_waf_yaf_status - Return current WAF YARA rule engine status
; Input:  none
; Output: rax = status code
; =============================================================================
global vs_waf_yaf_status
vs_waf_yaf_status:
    mov     eax, [vs_waf_yaf_state + vuln_scan_state_base_t.magic]
    cmp     eax, VULN_SCAN_STATE_MAGIC
    jnz     .not_init
    mov     al, [vs_waf_yaf_state + vuln_scan_state_base_t.enabled]
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
; vs_waf_yaf_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global vs_waf_yaf_version
vs_waf_yaf_version:
    mov     rax, vs_waf_yaf_version_str
    ret

; STUB: vs_waf_yaf_add_rule - add YARA rule
; STUB: vs_waf_yaf_remove_rule - remove YARA rule
; STUB: vs_waf_yaf_list_rules - list all YARA rules
; STUB: vs_waf_yaf_get_stats - return YARA rule statistics

%endif