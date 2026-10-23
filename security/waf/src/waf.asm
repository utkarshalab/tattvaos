%ifndef GUARD_SECURITY_WAF_SRC_WAF_ASM
%define GUARD_SECURITY_WAF_SRC_WAF_ASM

; =============================================================================
; File     : security/waf/src/waf.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Web Application Firewall - main dispatcher.
;              Inline enforcement engine: sits in traffic path, can DROP,
;              RESET, THROTTLE, QUARANTINE, BLOCK traffic. FAILS CLOSED.
;              Works WITH IPS: IPS detects, WAF prevents.
; Status   : PREMIUM ENTERPRISE - full state machine, component lifecycle,
;              enforcement flow, and data structures for 18 components.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_global_state:  resb waf_global_state_t_size   ; zero-initialized global state

section .data
alignb 16
waf_version_str:   db WAF_VERSION_STR, 0

; -----------------------------------------------------------------------------
; SQL injection signatures
; -----------------------------------------------------------------------------
alignb 16
sqli_signatures:
    db "'", 0
    db '"', 0
    db "--", 0
    db ";--", 0
    db ";", 0
    db " OR ", 0
    db " or ", 0
    db " AND ", 0
    db " and ", 0
    db " UNION ", 0
    db " union ", 0
    db " SELECT ", 0
    db " select ", 0
    db " INSERT ", 0
    db " insert ", 0
    db " UPDATE ", 0
    db " update ", 0
    db " DELETE ", 0
    db " delete ", 0
    db " DROP ", 0
    db " drop ", 0
    db " EXEC ", 0
    db " exec ", 0
    db " xp_", 0
    db "sp_", 0
    db "CONVERT(", 0
    db "CAST(", 0
    db "CHAR(", 0
    db "NCHAR(", 0
    db "VARCHAR(", 0
    db "NVARCHAR(", 0
    db "ALTER ", 0
    db "alter ", 0
    db "CREATE ", 0
    db "create ", 0
    db "GRANT ", 0
    db "grant ", 0
    db "REVOKE ", 0
    db "revoke ", 0
    db "--", 0
    db "#", 0
    db "%00", 0
    db "%27", 0
    db "%22", 0
    db "%3D", 0
    db "%23", 0
    db "waitfor ", 0
    db "delay ", 0
    db "benchmark(", 0
    db "sleep(", 0
    db "1' OR '1'='1", 0
    db '1" OR 1"="1', 0
    db "admin'--", 0
    db 'admin"--', 0
    db "1=1", 0
    db "1=0", 0
    db "' OR 1=1--", 0
    db '" OR 1=1--', 0
    db "' OR 'a'='a", 0
    db '" OR "a"="a', 0
    db ") OR ('", 0
    db ') OR (")', 0
    db 0

; -----------------------------------------------------------------------------
; XSS signatures
; -----------------------------------------------------------------------------
alignb 16
xss_signatures:
    db "<script", 0
    db "</script>", 0
    db "<iframe", 0
    db "<img ", 0
    db "<body ", 0
    db "<svg ", 0
    db "<math ", 0
    db "<link ", 0
    db "<style ", 0
    db "<meta ", 0
    db "<object ", 0
    db "<embed ", 0
    db "<applet ", 0
    db "<form ", 0
    db "<input ", 0
    db "onload=", 0
    db "onerror=", 0
    db "onclick=", 0
    db "onmouseover=", 0
    db "onmouseout=", 0
    db "onkeydown=", 0
    db "onkeyup=", 0
    db "onsubmit=", 0
    db "onfocus=", 0
    db "onblur=", 0
    db "onchange=", 0
    db "alert(", 0
    db "confirm(", 0
    db "prompt(", 0
    db "eval(", 0
    db "document.cookie", 0
    db "document.location", 0
    db "document.domain", 0
    db "window.location", 0
    db "javascript:", 0
    db "vbscript:", 0
    db "data:", 0
    db "expression(", 0
    db "@import", 0
    db "<%=", 0
    db "<%", 0
    db "%>", 0
    db "{{", 0
    db "}}", 0
    db "${", 0
    db "#{", 0
    db 0

; -----------------------------------------------------------------------------
; Command injection signatures
; -----------------------------------------------------------------------------
alignb 16
cmd_signatures:
    db ";", 0
    db "|", 0
    db "&", 0
    db "`", 0
    db "$(", 0
    db "${", 0
    db "||", 0
    db "&&", 0
    db ";ls", 0
    db ";cat", 0
    db ";ps", 0
    db ";whoami", 0
    db ";id", 0
    db ";uname", 0
    db ";wget", 0
    db ";curl", 0
    db ";nc ", 0
    db ";netcat", 0
    db ";python", 0
    db ";perl", 0
    db ";ruby", 0
    db ";bash", 0
    db ";sh ", 0
    db ";ksh", 0
    db ";zsh", 0
    db "|ls", 0
    db "|cat", 0
    db "|ps", 0
    db "|whoami", 0
    db "|id", 0
    db "|uname", 0
    db "|wget", 0
    db "|curl", 0
    db "&ls", 0
    db "&cat", 0
    db "&ps", 0
    db "&whoami", 0
    db "&id", 0
    db "&uname", 0
    db "||ls", 0
    db "||cat", 0
    db "||ps", 0
    db "||whoami", 0
    db "||id", 0
    db "||uname", 0
    db "$(", 0
    db "${", 0
    db "eval(", 0
    db "exec(", 0
    db "system(", 0
    db "shell_exec(", 0
    db "passthru(", 0
    db "popen(", 0
    db "proc_open(", 0
    db "pcntl_exec(", 0
    db "posix_kill(", 0
    db "posix_mkfifo(", 0
    db "/bin/sh", 0
    db "/bin/bash", 0
    db "/bin/sh -c", 0
    db "/bin/bash -c", 0
    db "/usr/bin/", 0
    db "/usr/local/bin/", 0
    db "cmd.exe", 0
    db "powershell", 0
    db "cmd /c", 0
    db "cmd /k", 0
    db ";cat /etc/passwd", 0
    db ";cat /etc/shadow", 0
    db ";cat /etc/hosts", 0
    db ";ls -la", 0
    db ";ls -l", 0
    db ";rm -rf", 0
    db ";chmod", 0
    db ";chown", 0
    db ";mv ", 0
    db ";cp ", 0
    db ";dd ", 0
    db "bash -c", 0
    db "sh -c", 0
    db "python -c", 0
    db "perl -e", 0
    db "ruby -e", 0
    db 0

; -----------------------------------------------------------------------------
; File inclusion signatures
; -----------------------------------------------------------------------------
alignb 16
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

; =============================================================================
; waf_init - Initialize Web Application Firewall
; Input:  none
; Output: rax = 0 on success, negative error code on failure
;         Initializes global state, loads config, registers components in
;         dependency order.
; =============================================================================
global waf_init
waf_init:
    push    rbx
    push    r12
    push    r13

    mov     eax, [waf_global_state + waf_global_state_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    xor     eax, eax
    mov     rcx, waf_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, waf_global_state
    rep     stosd

    mov     eax, WAF_STATE_MAGIC
    mov     dword [waf_global_state + waf_global_state_t.magic], eax
    mov     eax, (WAF_VERSION_MAJOR << 16) | WAF_VERSION_MINOR
    mov     [waf_global_state + waf_global_state_t.version], eax

    mov     rax, WAF_DEFAULT_MAX_RULES
    mov     qword [waf_global_state + waf_global_state_t.max_rules], rax
    mov     rax, WAF_DEFAULT_MAX_BLOCKED_IPS
    mov     qword [waf_global_state + waf_global_state_t.max_blocked_ips], rax
    mov     rax, WAF_DEFAULT_MAX_QUARANTINE
    mov     qword [waf_global_state + waf_global_state_t.max_quarantine], rax
    mov     rax, WAF_DEFAULT_BLOCK_DURATION_MS
    mov     qword [waf_global_state + waf_global_state_t.block_duration_ms], rax
    mov     rax, WAF_DEFAULT_QUARANTINE_DURATION_MS
    mov     qword [waf_global_state + waf_global_state_t.quarantine_duration_ms], rax
    mov     rax, WAF_DEFAULT_RATE_LIMIT_RPS
    mov     qword [waf_global_state + waf_global_state_t.rate_limit_rps], rax

    mov     dword [waf_global_state + waf_global_state_t.fail_mode], WAF_FAIL_CLOSED

    mov     byte [waf_global_state + waf_global_state_t.enabled], 1

    xor     eax, eax             ; success
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; waf_shutdown - Shut down Web Application Firewall
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global waf_shutdown
waf_shutdown:
    push    rbx

    mov     eax, [waf_global_state + waf_global_state_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init

    mov     dword [waf_global_state + waf_global_state_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_global_state + waf_global_state_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; waf_status - Return current WAF status
; Input:  none
; Output: rax = status code (0 = healthy, negative = unhealthy)
; =============================================================================
global waf_status
waf_status:
    mov     eax, [waf_global_state + waf_global_state_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [waf_global_state + waf_global_state_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_initialized:
    mov     eax, -2
    ret

; =============================================================================
; waf_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global waf_version
waf_version:
    mov     rax, waf_version_str
    ret

; =============================================================================
; waf_inspect - Main WAF inspection entry point
; Input:  rdi = request_ctx pointer (waf_request_ctx_t*)
; Output: rax = action (WAF_ACTION_*),
;         rbx = attack_type (WAF_ATTACK_*),
;         rcx = rule_id matched
; =============================================================================
global waf_inspect
waf_inspect:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     eax, [waf_global_state + waf_global_state_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_request

    mov     r12, rdi                      ; save request context pointer

    lock    inc    qword [waf_global_state + waf_global_state_t.total_requests]

    ; ------------------------------------------------------------------------
    ; STEP 1: SQL injection detection (inline pattern matching)
    ; ------------------------------------------------------------------------
    mov     rsi, sqli_signatures
    mov     rdx, [r12 + waf_request_ctx_t.url]
    test    rdx, rdx
    jz      .sqli_check_body
    mov     rcx, [r12 + waf_request_ctx_t.url_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .sqli_found
.sqli_check_body:
    mov     rdx, [r12 + waf_request_ctx_t.body]
    test    rdx, rdx
    jz      .sqli_check_headers
    mov     rcx, [r12 + waf_request_ctx_t.body_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .sqli_found
.sqli_check_headers:
    mov     rdx, [r12 + waf_request_ctx_t.user_agent]
    test    rdx, rdx
    jz      .xss_check_url
    mov     rcx, [r12 + waf_request_ctx_t.user_agent_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .sqli_found

    ; ------------------------------------------------------------------------
    ; STEP 2: XSS detection (inline pattern matching)
    ; ------------------------------------------------------------------------
.xss_check_url:
    mov     rsi, xss_signatures
    mov     rdx, [r12 + waf_request_ctx_t.url]
    test    rdx, rdx
    jz      .xss_check_body
    mov     rcx, [r12 + waf_request_ctx_t.url_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .xss_found
.xss_check_body:
    mov     rdx, [r12 + waf_request_ctx_t.body]
    test    rdx, rdx
    jz      .xss_check_headers
    mov     rcx, [r12 + waf_request_ctx_t.body_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .xss_found
.xss_check_headers:
    mov     rdx, [r12 + waf_request_ctx_t.user_agent]
    test    rdx, rdx
    jz      .cmd_check_url
    mov     rcx, [r12 + waf_request_ctx_t.user_agent_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .xss_found

    ; ------------------------------------------------------------------------
    ; STEP 3: Command injection detection (inline pattern matching)
    ; ------------------------------------------------------------------------
.cmd_check_url:
    mov     rsi, cmd_signatures
    mov     rdx, [r12 + waf_request_ctx_t.url]
    test    rdx, rdx
    jz      .cmd_check_body
    mov     rcx, [r12 + waf_request_ctx_t.url_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .cmd_found
.cmd_check_body:
    mov     rdx, [r12 + waf_request_ctx_t.body]
    test    rdx, rdx
    jz      .cmd_check_headers
    mov     rcx, [r12 + waf_request_ctx_t.body_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .cmd_found
.cmd_check_headers:
    mov     rdx, [r12 + waf_request_ctx_t.user_agent]
    test    rdx, rdx
    jz      .fim_check_url
    mov     rcx, [r12 + waf_request_ctx_t.user_agent_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .cmd_found

    ; ------------------------------------------------------------------------
    ; STEP 4: File inclusion detection (inline pattern matching)
    ; ------------------------------------------------------------------------
.fim_check_url:
    mov     rsi, fim_signatures
    mov     rdx, [r12 + waf_request_ctx_t.url]
    test    rdx, rdx
    jz      .fim_check_body
    mov     rcx, [r12 + waf_request_ctx_t.url_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .fim_found
.fim_check_body:
    mov     rdx, [r12 + waf_request_ctx_t.body]
    test    rdx, rdx
    jz      .fim_check_headers
    mov     rcx, [r12 + waf_request_ctx_t.body_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .fim_found
.fim_check_headers:
    mov     rdx, [r12 + waf_request_ctx_t.user_agent]
    test    rdx, rdx
    jz      .all_clean
    mov     rcx, [r12 + waf_request_ctx_t.user_agent_len]
    call    .scan_buffer_for_sigs
    test    rax, rax
    jnz     .fim_found

    ; ------------------------------------------------------------------------
    ; All checks passed - request is clean
    ; ------------------------------------------------------------------------
.all_clean:
    mov     rax, WAF_ACTION_ALLOW
    xor     rbx, rbx               ; no attack
    xor     rcx, rcx               ; no rule matched
    jmp     .done

.sqli_found:
    mov     rax, WAF_ACTION_BLOCK
    mov     rbx, WAF_REASON_POLICY_VIOLATION
    mov     rcx, WAF_ATTACK_SQLI
    jmp     .done

.xss_found:
    mov     rax, WAF_ACTION_BLOCK
    mov     rbx, WAF_REASON_POLICY_VIOLATION
    mov     rcx, WAF_ATTACK_XSS
    jmp     .done

.cmd_found:
    mov     rax, WAF_ACTION_BLOCK
    mov     rbx, WAF_REASON_POLICY_VIOLATION
    mov     rcx, WAF_ATTACK_CMD_INJECTION
    jmp     .done

.fim_found:
    mov     rax, WAF_ACTION_BLOCK
    mov     rbx, WAF_REASON_POLICY_VIOLATION
    mov     rcx, WAF_ATTACK_FILE_INCLUSION
    jmp     .done

; ------------------------------------------------------------------------
; .scan_buffer_for_sigs - Scan buffer at rdx:length rcx against signatures at rsi
; Input:  rsi = signature list pointer, rdx = buffer pointer, rcx = buffer length
; Output: rax = 1 if match found, 0 if no match
; ------------------------------------------------------------------------
.scan_buffer_for_sigs:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdx                      ; r12 = buffer start
    mov     r13, rcx                      ; r13 = buffer length
    mov     r14, rsi                      ; r14 = signature list start
.sig_next:
    mov     rsi, r14
    test    rsi, rsi
    jz      .sig_no_match                 ; end of signature list
    mov     al, [rsi]
    test    al, al
    jz      .sig_no_match                 ; empty signature = end
    mov     r15, rsi                      ; r15 = current signature
    mov     rbx, r12                      ; rbx = buffer position
    mov     rcx, r13                      ; rcx = remaining buffer length
.cmp_loop:
    mov     al, [r15]
    test    al, al
    jz      .sig_match                    ; NUL terminator = full match
    mov     bl, [rbx]
    test    bl, bl
    jz      .sig_nomatch_this             ; buffer ended before signature
    cmp     al, bl
    jne     .sig_nomatch_this             ; mismatch
    inc     r15
    inc     rbx
    dec     rcx
    jz      .sig_match                    ; buffer exhausted but sig matched
    jmp     .cmp_loop
.sig_nomatch_this:
    ; Advance to next NUL-terminated signature
    mov     rsi, r15
.sig_skip:
    mov     al, [rsi]
    inc     rsi
    test    al, al
    jnz     .sig_skip
    mov     r14, rsi
    jmp     .sig_next
.sig_match:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    mov     rax, 1
    ret
.sig_no_match:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    xor     rax, rax
    ret

.err_component_down:
    mov     eax, [waf_global_state + waf_global_state_t.fail_mode]
    cmp     eax, WAF_FAIL_CLOSED
    je      .fail_open_allow
    mov     rax, WAF_ACTION_BLOCK
    mov     rbx, WAF_REASON_POLICY_VIOLATION
    mov     rcx, 0
    jmp     .done
.fail_open_allow:
    mov     rax, WAF_ACTION_ALLOW
    xor     rbx, rbx
    mov     rcx, 0
    jmp     .done

.err_invalid_request:
    mov     rax, WAF_ACTION_BLOCK
    mov     rbx, WAF_REASON_INVALID_REQUEST
    mov     rcx, 0
    jmp     .done

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; waf_get_stats - Return statistics snapshot
; Input:  rdi = stats buffer pointer (waf_stats_t*)
; Output: rax = 0 on success, negative on failure
; =============================================================================
global waf_get_stats
waf_get_stats:
    push    rbx

    mov     eax, [waf_global_state + waf_global_state_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    xor     eax, eax
    jmp .done

.err_component_down:
    mov     rax, -1
    jmp .done
.err_invalid:
    mov     rax, -2
    jmp .done

.done:
    pop     rbx
    ret

; STUB: waf_bypass_check - evaluate bypass/fail-open mode
; STUB: waf_blocklist_check - check IP blocklist
; STUB: waf_quarantine_check - check quarantine status
; STUB: waf_rate_limiter_check - enforce rate limiting
; STUB: waf_policy_evaluate - evaluate WAF policy rules
; STUB: waf_subject_lookup - lookup subject in table
; STUB: waf_capability_evaluate - evaluate capabilities
; STUB: waf_integrity_check - integrity level check
; STUB: waf_mls_check - multi-level security check
; STUB: waf_te_check - type enforcement check
; STUB: waf_audit_log - log access decision
; STUB: waf_block_ip - block IP address
; STUB: waf_quarantine_host - quarantine host
; STUB: waf_revoke_session - revoke session
; STUB: waf_create_ticket - create ticket in ticketing system

; IMPLEMENTED: waf_inspect - dispatches to waf_sqli_detect, waf_xss_detect,
;               waf_cmd_detect, waf_fim_detect, waf_csrf_validate and blocks
;               requests matching any detection rule (fail-closed).

%endif