%ifndef GUARD_SECURITY_WAF_SRC_RULEC_ASM
%define GUARD_SECURITY_WAF_SRC_RULEC_ASM

; =============================================================================
; File     : security/waf/src/waf_rulec.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF Custom Rule Compiler - compiles custom WAF rules into
;              efficient match structures (Aho-Corasick, regex, etc.).
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_rulec_state:      resb waf_state_base_t_size
waf_rulec_rule_head:  resq 1
waf_rulec_rule_count: resq 1
waf_rulec_compiled_head: resq 1

section .data
alignb 16
waf_rulec_version_str: db WAF_VERSION_STR, 0

section .text

global waf_rulec_init
waf_rulec_init:
    push    rbx
    mov     dword [waf_rulec_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_rulec_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_rulec_state + waf_state_base_t.enabled], 1
    mov     qword [waf_rulec_rule_head], 0
    mov     qword [waf_rulec_rule_count], 0
    mov     qword [waf_rulec_compiled_head], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_rulec_shutdown
waf_rulec_shutdown:
    push    rbx
    mov     eax, [waf_rulec_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_rulec_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_rulec_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_rulec_status
waf_rulec_status:
    mov     eax, [waf_rulec_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_rulec_state + waf_state_base_t.enabled]
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

global waf_rulec_version
waf_rulec_version:
    mov     rax, waf_rulec_version_str
    ret

global waf_rulec_compile
waf_rulec_compile:
    push    rbx
    mov     eax, [waf_rulec_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     eax, eax   ; rule compiled
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

; STUB: waf_rulec_compile - compile rules to match structures
; STUB: waf_rulec_load - load compiled rules
; STUB: waf_rulec_optimize - optimize match structures
; STUB: waf_rulec_serialize - serialize compiled rules
; STUB: waf_rulec_deserialize - deserialize compiled rules
; STUB: waf_rulec_validate - validate compiled rules

%endif
