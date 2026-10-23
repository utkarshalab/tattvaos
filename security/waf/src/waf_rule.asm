%ifndef GUARD_SECURITY_WAF_SRC_RULE_ASM
%define GUARD_SECURITY_WAF_SRC_RULE_ASM

; =============================================================================
; File     : security/waf/src/waf_rule.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF Rule Engine - rule compilation, storage, and evaluation
;              for OWASP Top 10 and custom rules.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_rule_state:      resb waf_state_base_t_size
waf_rule_head:       resq 1
waf_rule_count:      resq 1
waf_compiled_head:   resq 1
waf_compiled_count:  resq 1

section .data
alignb 16
waf_rule_version_str: db WAF_VERSION_STR, 0

section .text

global waf_rule_init
waf_rule_init:
    push    rbx
    mov     dword [waf_rule_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_rule_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_rule_state + waf_state_base_t.enabled], 1
    mov     qword [waf_rule_head], 0
    mov     qword [waf_rule_count], 0
    mov     qword [waf_compiled_head], 0
    mov     qword [waf_compiled_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_rule_shutdown
waf_rule_shutdown:
    push    rbx
    mov     eax, [waf_rule_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_rule_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_rule_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_rule_status
waf_rule_status:
    mov     eax, [waf_rule_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_rule_state + waf_state_base_t.enabled]
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

global waf_rule_version
waf_rule_version:
    mov     rax, waf_rule_version_str
    ret

global waf_rule_load
waf_rule_load:
    push    rbx
    mov     eax, [waf_rule_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     eax, eax
    pop     rbx
    ret
.err_cd:
    mov     rax, -2
    pop     rbx
    ret
.err_inv:
    mov     rax, -3
    pop     rbx
    ret

global waf_rule_evaluate
waf_rule_evaluate:
    push    rbx
    mov     eax, [waf_rule_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     rax, rax   ; no rule matched
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

; STUB: waf_rule_load - load rules from configuration
; STUB: waf_rule_evaluate - evaluate rules against request
; STUB: waf_rule_compile - compile rules to match structures
; STUB: waf_rule_match - match request against rules
; STUB: waf_rule_priority - sort rules by priority
; STUB: waf_rule_hit_count - track rule match frequency

%endif
