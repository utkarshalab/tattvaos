%ifndef GUARD_SECURITY_WAF_SRC_SIEM_ASM
%define GUARD_SECURITY_WAF_SRC_SIEM_ASM

; =============================================================================
; File     : security/waf/src/waf_siem.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF SIEM Exporter - WAF event export to SIEM systems in CEF,
;              LEEF, JSON, or SYSLOG formats.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_siem_state:         resb waf_state_base_t_size
waf_siem_conn_ptr:      resq 1
waf_siem_queue_head:    resq 1
waf_siem_queue_count:   resq 1
waf_siem_last_export:   resq 1

section .data
alignb 16
waf_siem_version_str: db WAF_VERSION_STR, 0

section .text

global waf_siem_init
waf_siem_init:
    push    rbx
    mov     dword [waf_siem_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_siem_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_siem_state + waf_state_base_t.enabled], 1
    mov     qword [waf_siem_conn_ptr], 0
    mov     qword [waf_siem_queue_head], 0
    mov     qword [waf_siem_queue_count], 0
    mov     qword [waf_siem_last_export], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_siem_shutdown
waf_siem_shutdown:
    push    rbx
    mov     eax, [waf_siem_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_siem_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_siem_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_siem_status
waf_siem_status:
    mov     eax, [waf_siem_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_siem_state + waf_state_base_t.enabled]
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

global waf_siem_version
waf_siem_version:
    mov     rax, waf_siem_version_str
    ret

global waf_siem_export
waf_siem_export:
    push    rbx
    mov     eax, [waf_siem_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    mov     rax, -1   ; queued, not exported yet
    xor     rbx, rbx
    pop     rbx
    ret
.err_cd:
    mov     rax, -2
    xor     rbx, rbx
    pop     rbx
    ret
.err_inv:
    mov     rax, -3
    xor     rbx, rbx
    pop     rbx
    ret

; STUB: waf_siem_export - export events to SIEM
; STUB: waf_siem_connect - connect to SIEM system
; STUB: waf_siem_disconnect - disconnect from SIEM
; STUB: waf_siem_format - format event for SIEM
; STUB: waf_siem_batch - batch SIEM events
; STUB: waf_siem_retry - retry failed SIEM export

%endif
