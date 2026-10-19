%ifndef GUARD_SECURITY_WAF_SRC_API_ASM
%define GUARD_SECURITY_WAF_SRC_API_ASM

; =============================================================================
; File     : security/waf/src/waf_api.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF API Protection - API key validation, JWT validation,
;              schema validation, and API threat protection.
; Status   : PREMIUM ENTERPRISE - skeleton.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_session_state:      resb waf_state_base_t_size
waf_api_key_head:   resq 1
waf_api_key_count:  resq 1
waf_api_rate_head:  resq 1
waf_api_rate_count: resq 1

section .data
alignb 16
waf_session_version_str: db WAF_VERSION_STR, 0

section .text

global waf_session_init
waf_session_init:
    push    rbx
    mov     dword [waf_session_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_session_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_session_state + waf_state_base_t.enabled], 1
    mov     qword [waf_api_key_head], 0
    mov     qword [waf_api_key_count], 0
    mov     qword [waf_api_rate_head], 0
    mov     qword [waf_api_rate_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_session_shutdown
waf_session_shutdown:
    push    rbx
    mov     eax, [waf_session_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_session_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_session_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_session_status
waf_session_status:
    mov     eax, [waf_session_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_session_state + waf_state_base_t.enabled]
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

global waf_session_version
waf_session_version:
    mov     rax, waf_session_version_str
    ret

global waf_session_validate
waf_session_validate:
    push    rbx
    mov     eax, [waf_session_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_cd
    test    rdi, rdi
    jz      .err_inv
    xor     eax, eax   ; authenticated (anonymous)
    xor     rbx, rbx   ; user ID = 0 (anonymous)
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

global waf_session_track
waf_session_track:
    push    rbx
    mov     eax, [waf_session_state + waf_state_base_t.magic]
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
    pop     rbx
    ret
.err_inv:
    mov     rax, -3
    pop     rbx
    ret

; STUB: waf_session_validate - validate session
; STUB: waf_session_track - track session state
; STUB: waf_session_create - create new session
; STUB: waf_session_destroy - destroy session
; STUB: waf_session_renew - renew session expiry
; STUB: waf_session_lookup - lookup session by ID

%endif
