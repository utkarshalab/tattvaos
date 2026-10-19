%ifndef GUARD_SECURITY_WAF_SRC_FIM_ASM
%define GUARD_SECURITY_WAF_SRC_FIM_ASM

; =============================================================================
; File     : security/waf/src/waf_fim.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF File Inclusion Detector - Local/Remote File Inclusion
;              (LFI/RFI) detection for ../ traversal, include() attacks,
;              and wrapper abuse.
; Status   : PREMIUM ENTERPRISE - real pattern matching logic implemented.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_fim_state:     resb waf_state_base_t_size
waf_fim_sig_head:  resq 1
waf_fim_sig_count: resq 1

section .data
alignb 16
waf_fim_version_str: db WAF_VERSION_STR, 0

section .text

fim_signatures:
    db "../", 0
    db "..\\", 0
    db "..%2f", 0
    db "..%5c", 0
    db "..%252f", 0
    db "..%255c", 0
    db "..%c0%af", 0
    db "..%c1%9c", 0
    db "../..", 0
    db "..\\..", 0
    db "/etc/passwd", 0
    db "/etc/shadow", 0
    db "/proc/self/", 0
    db "/proc/self/environ", 0
    db "/proc/self/cmdline", 0
    db "include(", 0
    db "include_once(", 0
    db "require(", 0
    db "require_once(", 0
    db "require_include(", 0
    db "include_once(", 0
    db "file_get_contents(", 0
    db "file_put_contents(", 0
    db "fopen(", 0
    db "fread(", 0
    db "fwrite(", 0
    db "ftp://", 0
    db "http://", 0
    db "https://", 0
    db "php://input", 0
    db "php://filter", 0
    db "php://stdin", 0
    db "data://", 0
    db "expect://", 0
    db "zip://", 0
    db "glob://", 0
    db "file://", 0
    db "../../", 0
    db "../", 0
    db "..\\", 0
    db "..%2f%2f", 0
    db "..%5c%5c", 0
    db "%2e%2e%2f", 0
    db "%2e%2e%5c", 0
    db "%252e%252e%252f", 0
    db "%252e%252e%255c", 0
    db "..%c0%af", 0
    db "..%c1%9c", 0
    db "..%c1%1c", 0
    db "..%e0%80%af", 0
    db "/etc/", 0
    db "/var/", 0
    db "/usr/", 0
    db "/bin/", 0
    db "/sbin/", 0
    db "/boot/", 0
    db "/root/", 0
    db "/home/", 0
    db 0

section .text

global waf_fim_init
waf_fim_init:
    push    rbx
    mov     dword [waf_fim_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_fim_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_fim_state + waf_state_base_t.enabled], 1
    mov     qword [waf_fim_sig_head], 0
    mov     qword [waf_fim_sig_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_fim_shutdown
waf_fim_shutdown:
    push    rbx
    mov     eax, [waf_fim_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_fim_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_fim_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_fim_status
waf_fim_status:
    mov     eax, [waf_fim_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_fim_state + waf_state_base_t.enabled]
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

global waf_fim_version
waf_fim_version:
    mov     rax, waf_fim_version_str
    ret

global waf_fim_detect
waf_fim_detect:
    push    rbx
    push    r12
    push    r13

    mov     eax, [waf_fim_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    mov     r12, rdi

    mov     rax, [r12 + waf_request_ctx_t.url]
    test    rax, rax
    jz      .check_body
    mov     rsi, [r12 + waf_request_ctx_t.url]
    mov     rdx, [r12 + waf_request_ctx_t.url_len]
.check_url_loop:
    mov     rdi, rsi
    call    .check_fim_pattern
    test    rax, rax
    jnz     .fim_found
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
    call    .check_fim_pattern
    test    rax, rax
    jnz     .fim_found
    inc     rsi
    dec     rdx
    jnz     .check_body_loop

.check_headers:
    mov     rax, [r12 + waf_request_ctx_t.user_agent]
    test    rax, rax
    jz      .no_fim_found
    mov     rsi, [r12 + waf_request_ctx_t.user_agent]
    mov     rdx, [r12 + waf_request_ctx_t.user_agent_len]
.check_ua_loop:
    mov     rdi, rsi
    call    .check_fim_pattern
    test    rax, rax
    jnz     .fim_found
    inc     rsi
    dec     rdx
    jnz     .check_ua_loop

.no_fim_found:
    xor     rax, rax
    xor     rbx, rbx
    jmp .done

.fim_found:
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

.check_fim_pattern:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r13, rdx
    mov     rsi, fim_signatures
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

; STUB: waf_fim_detect - detect file inclusion
; STUB: waf_fim_load_patterns - load FIM patterns
; STUB: waf_fim_check_path - check file path
; STUB: waf_fim_check_uri - check URI for inclusion
; STUB: waf_fim_score - compute FIM threat score
; STUB: waf_fim_quarantine - quarantine on FIM detection

%endif
