%ifndef GUARD_SECURITY_WAF_SRC_RATE_ASM
%define GUARD_SECURITY_WAF_SRC_RATE_ASM

; =============================================================================
; File     : security/waf/src/waf_rate.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF Rate Limiter - per-IP and per-API-key rate limiting
;              with sliding window counters.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_rate_state:     resb waf_state_base_t_size
waf_rate_entry_head: resq 1
waf_rate_entry_count: resq 1
waf_rate_global_rps: resq 1

section .data
alignb 16
waf_rate_version_str: db WAF_VERSION_STR, 0

section .text

global waf_rate_init
waf_rate_init:
    push    rbx
    mov     dword [waf_rate_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_rate_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_rate_state + waf_state_base_t.enabled], 1
    mov     qword [waf_rate_entry_head], 0
    mov     qword [waf_rate_entry_count], 0
    mov     qword [waf_rate_global_rps], WAF_DEFAULT_RATE_LIMIT_RPS
    xor     eax, eax
    pop     rbx
    ret

global waf_rate_shutdown
waf_rate_shutdown:
    push    rbx
    mov     eax, [waf_rate_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_rate_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_rate_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_rate_status
waf_rate_status:
    mov     eax, [waf_rate_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_rate_state + waf_state_base_t.enabled]
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

global waf_rate_version
waf_rate_version:
    mov     rax, waf_rate_version_str
    ret

global waf_rate_check
waf_rate_check:
    push    rbx
    mov     eax, [waf_rate_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     rax, rax   ; within limits
    xor     rbx, rbx   ; no retry after
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

; STUB: waf_rate_check - check rate limit
; STUB: waf_rate_track - track request rate
; STUB: waf_rate_reset - reset rate counter
; STUB: waf_rate_block - block rate-limited client
; STUB: waf_rate_config - configure rate limits
; STUB: waf_rate_stats - compute rate statistics

%endif
