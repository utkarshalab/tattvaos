%ifndef GUARD_SECURITY_WAF_SRC_HTTP_ASM
%define GUARD_SECURITY_WAF_SRC_HTTP_ASM

; =============================================================================
; File     : security/waf/src/waf_http.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF HTTP Inspector - HTTP/HTTPS request parsing, header
;              extraction, URL parsing, and body analysis.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_http_state:      resb waf_state_base_t_size
waf_http_parser_head: resq 1
waf_http_parser_count: resq 1

section .data
alignb 16
waf_http_version_str: db WAF_VERSION_STR, 0

section .text

global waf_http_init
waf_http_init:
    push    rbx
    mov     dword [waf_http_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_http_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_http_state + waf_state_base_t.enabled], 1
    mov     qword [waf_http_parser_head], 0
    mov     qword [waf_http_parser_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_http_shutdown
waf_http_shutdown:
    push    rbx
    mov     eax, [waf_http_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_http_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_http_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_http_status
waf_http_status:
    mov     eax, [waf_http_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_http_state + waf_state_base_t.enabled]
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

global waf_http_version
waf_http_version:
    mov     rax, waf_http_version_str
    ret

global waf_http_parse
waf_http_parse:
    push    rbx
    mov     eax, [waf_http_state + waf_state_base_t.magic]
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

global waf_http_extract
waf_http_extract:
    push    rbx
    mov     eax, [waf_http_state + waf_state_base_t.magic]
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

; STUB: waf_http_parse - parse HTTP request
; STUB: waf_http_extract - extract request fields
; STUB: waf_http_normalize - normalize request data
; STUB: waf_http_validate - validate request structure
; STUB: waf_http_session_track - track HTTP session
; STUB: waf_http_body_inspect - inspect request body

%endif
