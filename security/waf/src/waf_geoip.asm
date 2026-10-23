%ifndef GUARD_SECURITY_WAF_SRC_GEOIP_ASM
%define GUARD_SECURITY_WAF_SRC_GEOIP_ASM

; =============================================================================
; File     : security/waf/src/waf_geoip.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF GeoIP Filter - geographic IP filtering. Blocks or allows
;              traffic based on source/destination country.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_geoip_state:     resb waf_state_base_t_size
waf_geoip_entry_head: resq 1
waf_geoip_entry_count: resq 1
waf_geoip_blocked_head: resq 1
waf_geoip_blocked_count: resq 1

section .data
alignb 16
waf_geoip_version_str: db WAF_VERSION_STR, 0

section .text

global waf_geoip_init
waf_geoip_init:
    push    rbx
    mov     dword [waf_geoip_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_geoip_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_geoip_state + waf_state_base_t.enabled], 1
    mov     qword [waf_geoip_entry_head], 0
    mov     qword [waf_geoip_entry_count], 0
    mov     qword [waf_geoip_blocked_head], 0
    mov     qword [waf_geoip_blocked_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_geoip_shutdown
waf_geoip_shutdown:
    push    rbx
    mov     eax, [waf_geoip_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_geoip_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_geoip_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_geoip_status
waf_geoip_status:
    mov     eax, [waf_geoip_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_geoip_state + waf_state_base_t.enabled]
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

global waf_geoip_version
waf_geoip_version:
    mov     rax, waf_geoip_version_str
    ret

global waf_geoip_lookup
waf_geoip_lookup:
    push    rbx
    mov     eax, [waf_geoip_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     rax, rax   ; unknown country
    xor     rbx, rbx   ; unknown continent
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

global waf_geoip_is_blocked
waf_geoip_is_blocked:
    push    rbx
    mov     eax, [waf_geoip_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     rax, rax   ; not blocked
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

; STUB: waf_geoip_lookup - look up IP geolocation
; STUB: waf_geoip_is_blocked - check if geo is blocked
; STUB: waf_geoip_load_db - load geolocation database
; STUB: waf_geoip_update - update geolocation data
; STUB: waf_geoip_country - get country code
; STUB: waf_geoip_region - get region code

%endif
