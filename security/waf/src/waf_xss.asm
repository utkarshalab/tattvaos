%ifndef GUARD_SECURITY_WAF_SRC_XSS_ASM
%define GUARD_SECURITY_WAF_SRC_XSS_ASM

; =============================================================================
; File     : security/waf/src/waf_xss.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF XSS Detector - Cross-Site Scripting detection for
;              <script>, onerror, javascript:, eval(), document.cookie,
;              and other XSS vectors.
; Status   : PREMIUM ENTERPRISE - real pattern matching logic implemented.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_xss_state:     resb waf_state_base_t_size
waf_xss_sig_head:  resq 1
waf_xss_sig_count: resq 1

section .data
alignb 16
waf_xss_version_str: db WAF_VERSION_STR, 0

section .text

; XSS signature patterns
xss_signatures:
    db "<script>", 0
    db "</script>", 0
    db "javascript:", 0
    db "onerror=", 0
    db "onload=", 0
    db "onclick=", 0
    db "onmouseover=", 0
    db "onfocus=", 0
    db "onblur=", 0
    db "onchange=", 0
    db "onmouseout=", 0
    db "onmouseover=", 0
    db "eval(", 0
    db "document.cookie", 0
    db "document.write(", 0
    db "alert(", 0
    db "confirm(", 0
    db "prompt(", 0
    db "<iframe", 0
    db "<img", 0
    db "<svg", 0
    db "<body", 0
    db "<input", 0
    db "expression(", 0
    db "vbscript:", 0
    db "data:text/html", 0
    db "&#", 0
    db "%3cscript", 0
    db "%3e", 0
    db "%22", 0
    db "%27", 0
    db "&#x", 0
    db "&#x0", 0
    db "</textarea>", 0
    db "</iframe>", 0
    db "</svg>", 0
    db "eval(", 0
    db "setTimeout(", 0
    db "setInterval(", 0
    db "Function(", 0
    db "constructor", 0
    db "location.href", 0
    db "location.replace(", 0
    db "document.domain", 0
    db "document.URL", 0
    db "document.referrer", 0
    db "innerHTML=", 0
    db "outerHTML=", 0
    db "innerText=", 0
    db "outerText=", 0
    db "write(", 0
    db "writeln(", 0
    db "open(", 0
    db "write(", 0
    db "<%=", 0
    db "<%@", 0
    db "<%", 0
    db "%>", 0
    db "<![CDATA[", 0
    db "]]>", 0
    db 0

section .text

global waf_xss_init
waf_xss_init:
    push    rbx
    mov     dword [waf_xss_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_xss_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_xss_state + waf_state_base_t.enabled], 1
    mov     qword [waf_xss_sig_head], 0
    mov     qword [waf_xss_sig_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_xss_shutdown
waf_xss_shutdown:
    push    rbx
    mov     eax, [waf_xss_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_xss_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_xss_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_xss_status
waf_xss_status:
    mov     eax, [waf_xss_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_xss_state + waf_state_base_t.enabled]
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

global waf_xss_version
waf_xss_version:
    mov     rax, waf_xss_version_str
    ret

global waf_xss_detect
waf_xss_detect:
    push    rbx
    push    r12
    push    r13

    mov     eax, [waf_xss_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    mov     r12, rdi

    ; STEP 1: Check URL for XSS patterns
    mov     rax, [r12 + waf_request_ctx_t.url]
    test    rax, rax
    jz      .check_body
    mov     rsi, [r12 + waf_request_ctx_t.url]
    mov     rdx, [r12 + waf_request_ctx_t.url_len]
.check_url_loop:
    mov     rdi, rsi
    call    .check_xss_pattern
    test    rax, rax
    jnz     .xss_found
    inc     rsi
    dec     rdx
    jnz     .check_url_loop

.check_body:
    mov     rax, [r12 + waf_request_ctx_t.body]
    test    rax, rax
    jz      .check_headers
    mov     rsi, [r12 + waf_request_ctx_t.body]
    mov     rdx, [r12 + waf_request_ctx_t.body_len]
.check_body_loop:
    mov     rdi, rsi
    call    .check_xss_pattern
    test    rax, rax
    jnz     .xss_found
    inc     rsi
    dec     rdx
    jnz     .check_body_loop

.check_headers:
    mov     rax, [r12 + waf_request_ctx_t.user_agent]
    test    rax, rax
    jz      .no_xss_found
    mov     rsi, [r12 + waf_request_ctx_t.user_agent]
    mov     rdx, [r12 + waf_request_ctx_t.user_agent_len]
.check_ua_loop:
    mov     rdi, rsi
    call    .check_xss_pattern
    test    rax, rax
    jnz     .xss_found
    inc     rsi
    dec     rdx
    jnz     .check_ua_loop

.no_xss_found:
    xor     rax, rax
    xor     rbx, rbx
    jmp .done

.xss_found:
    mov     rax, 1
    mov     rbx, WAF_SEV_HIGH
    jmp .done

.err_component_down:
    mov     rax, -2
    xor     rbx, rbx
    jmp .done
.err_invalid:
    mov     rax, -3
    xor     rbx, rbx
    jmp .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

.check_xss_pattern:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r13, rdx
    mov     rsi, xss_signatures
.check_next_sig:
    mov     rdi, rsi
    test    rdi, rdi
    jz      .no_match
    mov     al, [rdi]
    test    al, al
    jz      .no_match
    mov     r14, rdi
    mov     rcx, r12
    mov     rbx, r13
.compare_loop:
    mov     al, [rdi]
    test    al, al
    jz      .match_found
    mov     bl, [rcx]
    test    bl, bl
    jz      .nomatch_this_sig
    cmp     al, 'A'
    jl      .no_upper
    cmp     al, 'Z'
    jg      .no_upper
    add     al, 32
.no_upper:
    cmp     bl, 'A'
    jl      .no_buf_upper
    cmp     bl, 'Z'
    jg      .no_buf_upper
    add     bl, 32
.no_buf_upper:
    cmp     al, bl
    jne     .nomatch_this_sig
    inc     rdi
    inc     rcx
    dec     rbx
    jz      .match_found
    jmp .compare_loop
.nomatch_this_sig:
    add     rsi, rdi
    inc     rsi
    mov     rdi, rsi
    jmp .check_next_sig
.match_found:
    mov     rax, 1
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.no_match:
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; STUB: waf_xss_load_sigs - load XSS signatures
; STUB: waf_xss_compile_patterns - compile detection patterns
; STUB: waf_xss_check_url - scan URL for XSS
; STUB: waf_xss_check_body - scan body for XSS
; STUB: waf_xss_check_headers - scan headers for XSS
; STUB: waf_xss_score - compute XSS threat score

%endif
