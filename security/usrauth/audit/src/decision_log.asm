%ifndef GUARD_SECURITY_USRAUTH_AUDIT_SRC_DECISION_LOG_ASM
%define GUARD_SECURITY_WAF_SRC_AUDIT_DFIR_ASM

; =============================================================================
; File     : security/usrauth/audit/src/decision_log.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Audit Decision Log - immutable append-only authorization decision
;              log. Every authorization decision made by usrauth is recorded
;              here for non-repudiation and forensic traceability. Log entries
;              are hash-chained so tampering is detectable.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_state:              resb waf_state_base_t_size
waf_decision_log_head:  resq 1      ; append-only linked list head
waf_decision_log_tail:  resq 1      ; tail pointer for O(1) append
waf_decision_count:     resq 1      ; total decisions logged
waf_decision_prev_hash: resq 1      ; previous log hash for chain verification

section .data
alignb 16
waf_version_str:   db WAF_VERSION_STR, 0

section .text

; =============================================================================
; waf_decision_log_init - Initialize audit decision log
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global waf_init
waf_init:
    push    rbx
    mov     dword [waf_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_state + waf_state_base_t.enabled], 1
    mov     qword [waf_decision_log_head], 0
    mov     qword [waf_decision_log_tail], 0
    mov     qword [waf_decision_count], 0
    mov     qword [waf_decision_prev_hash], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_decision_log_shutdown
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

global waf_decision_log_status
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

global waf_decision_log_version
waf_version:
    mov     rax, waf_version_str
    ret

; =============================================================================
; waf_decision_log_append - Append an audit decision record
; Input:  rdi = subject_handle, rsi = verdict, rdx = object_id,
;         rcx = object_class, r8 = verb, r9 = reason_code
; Output: rax = 0 on success, negative on failure
; =============================================================================
global waf_decision_log_append
waf_decision_log_append:
    push    rbx
    mov     eax, [waf_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    ; STUB: allocate decision_log entry, fill fields, compute hash chain,
    ;   append to linked list
    mov     rax, 0
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
