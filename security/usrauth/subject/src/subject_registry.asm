%ifndef GUARD_SECURITY_WAF_SRC_SUBJECT_REGISTRY_ASM
%define GUARD_SECURITY_WAF_SRC_SUBJECT_REGISTRY_ASM

; =============================================================================
; File     : security/usrauth/subject/src/subject_registry.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Subject Registry - high-level subject registry that combines
;              subject table management with subject lookup by various
;              identifiers (UID, email, etc.).
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_state:         resb waf_state_base_t_size
waf_registry_head: resq 1
waf_registry_count: resq 1

section .data
alignb 16
waf_version_str:   db WAF_VERSION_STR, 0

section .text

global waf_registry_init
waf_init:
    push    rbx
    mov     dword [waf_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_state + waf_state_base_t.enabled], 1
    mov     qword [waf_registry_head], 0
    mov     qword [waf_registry_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_registry_shutdown
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

global waf_registry_status
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

global waf_registry_version
waf_version:
    mov     rax, waf_version_str
    ret

global waf_registry_lookup_by_uid
waf_registry_lookup_by_uid:
    push    rbx
    mov     eax, [waf_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     rax, rax
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

%endif
