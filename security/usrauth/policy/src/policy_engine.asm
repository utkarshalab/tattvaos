%ifndef GUARD_SECURITY_WAF_SRC_POLICY_ENGINE_ASM
%define GUARD_SECURITY_WAF_SRC_POLICY_ENGINE_ASM

; =============================================================================
; File     : security/usrauth/policy/src/policy_engine.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Policy Engine - evaluates ABAC/ReBAC policies against subject,
;              resource, and action context to produce authorization decisions.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_state:            resb waf_state_base_t_size
waf_policy_engine_policy_head: resq 1
waf_policy_engine_rule_count: resq 1

section .data
alignb 16
waf_version_str:   db WAF_VERSION_STR, 0

section .text

global waf_policy_engine_init
waf_init:
    push    rbx
    mov     dword [waf_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_state + waf_state_base_t.enabled], 1
    mov     qword [waf_policy_engine_policy_head], 0
    mov     qword [waf_policy_engine_rule_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_policy_engine_shutdown
waf_shutdown:
    push    rbx
    mov     eax, [waf_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_policy_engine_status
waf_status:
    mov     eax, [waf_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_state + waf_state_base_t.enabled]
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

global waf_policy_engine_version
waf_version:
    mov     rax, waf_version_str
    ret

global waf_policy_engine_evaluate
waf_policy_evaluate:
    push    rbx
    mov     eax, [waf_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     eax, rax
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

%endif
