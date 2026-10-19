%ifndef GUARD_SECURITY_WAF_SRC_CORE_ASM
%define GUARD_SECURITY_WAF_SRC_CORE_ASM

; =============================================================================
; File     : security/waf/src/waf_core.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF Core Engine - central orchestration, state management,
;              and component coordination for the Web Application Firewall.
; Status   : PREMIUM ENTERPRISE - skeleton with data structures defined.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_core_state:       resb waf_state_base_t_size
waf_core_config_head: resq 1
waf_core_config_count: resq 1
waf_core_health_head: resq 1

section .data
alignb 16
waf_core_version_str: db WAF_VERSION_STR, 0

section .text

global waf_core_init
waf_core_init:
    push    rbx
    mov     dword [waf_core_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_core_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_core_state + waf_state_base_t.enabled], 1
    mov     qword [waf_core_config_head], 0
    mov     qword [waf_core_config_count], 0
    mov     qword [waf_core_health_head], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_core_shutdown
waf_core_shutdown:
    push    rbx
    mov     eax, [waf_core_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_core_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_core_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_core_status
waf_core_status:
    mov     eax, [waf_core_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_core_state + waf_state_base_t.enabled]
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

global waf_core_version
waf_core_version:
    mov     rax, waf_core_version_str
    ret

; STUB: waf_core_register - register component with core
; STUB: waf_core_health_check - evaluate component health
; STUB: waf_core_reload_config - hot-reload configuration
; STUB: waf_core_metrics_export - emit core metrics
; STUB: waf_core_graceful_degrade - fail-safe degradation
; STUB: waf_core_state_sync - sync state across nodes

%endif
