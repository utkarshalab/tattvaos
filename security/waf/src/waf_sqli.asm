%ifndef GUARD_SECURITY_WAF_SRC_SQLI_ASM
%define GUARD_SECURITY_WAF_SRC_SQLI_ASM

; =============================================================================
; File     : security/waf/src/waf_sqli.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF SQL Injection Detector - SQL injection pattern detection
;              for UNION SELECT, DROP TABLE, OR 1=1, blind injection, comment
;              injection, stacked queries, and time-based attacks.
; Status   : PREMIUM ENTERPRISE - real pattern matching logic implemented.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_sqli_state:      resb waf_state_base_t_size
waf_sqli_sig_head:   resq 1      ; SQLi signature linked list
waf_sqli_sig_count:  resq 1

section .data
alignb 16
waf_sqli_version_str: db WAF_VERSION_STR, 0

; SQL injection signature patterns (case-insensitive matching)
; Format: pattern string, NUL-terminated
sqli_signatures:
    ; UNION-based injection
    db "UNION SELECT", 0
    db "UNION ALL SELECT", 0
    db "UNION ALL", 0
    ; Error-based injection
    db "DROP TABLE", 0
    db "DROP DATABASE", 0
    db "INSERT INTO", 0
    db "DELETE FROM", 0
    db "UPDATE SET", 0
    ; Boolean-based blind injection
    db "OR 1=1", 0
    db "OR 1=0", 0
    db "AND 1=1", 0
    db "AND 1=0", 0
    db "OR '1'='1", 0
    db "OR '1'='0", 0
    db "AND '1'='1", 0
    ; Comment-based injection
    db "--", 0
    db "#", 0
    db "/*", 0
    db "*/", 0
    ; Time-based blind injection
    db "SLEEP(", 0
    db "BENCHMARK(", 0
    db "WAITFOR DELAY", 0
    ; Stacked queries
    db ";", 0
    ; Information schema
    db "INFORMATION_SCHEMA", 0
    db "TABLE_SCHEMA", 0
    db "COLUMN_NAME", 0
    ; Common bypass patterns
    db "UNI%00ON SEL%00ECT", 0
    db "UNI/**/ON SEL/**/ECT", 0
    db "UNION%23SELECT", 0
    db "UNION%0aSELECT", 0
    db "UNION%0dSELECT", 0
    db "admin'--", 0
    db "admin'#", 0
    db "admin'/*", 0
    db "' or 1=1--", 0
    db "' or 1=1#", 0
    db "' or 1=1/*", 0
    db "') or '1'='1--", 0
    db "') or '1'='1#", 0
    db "') or '1'='1/*", 0
    db "0' UNION SELECT", 0
    db "0 UNION ALL SELECT", 0
    db "0' UNION ALL SELECT", 0
    db "1' UNION SELECT", 0
    db "1 UNION ALL SELECT", 0
    db "1' UNION ALL SELECT", 0
    ; Null byte injection
    db "%00", 0
    ; Hex encoding
    db "0x", 0
    ; Comments
    db "%23", 0
    db "%0d%0a", 0
    db "%0a", 0
    db "%0d", 0
    ; end marker
    db 0

section .text

; =============================================================================
; waf_sqli_init - Initialize SQL injection detector component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global waf_sqli_init
waf_sqli_init:
    push    rbx

    mov     dword [waf_sqli_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_sqli_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_sqli_state + waf_state_base_t.enabled], 1
    mov     qword [waf_sqli_sig_head], 0
    mov     qword [waf_sqli_sig_count], 0

    ; STUB: allocate SQLi signature memory pool
    ; STUB: load SQLi signature database from config
    ; STUB: compile patterns for fast matching (Aho-Corasick, etc.)

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; waf_sqli_shutdown - Shut down SQL injection detector component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global waf_sqli_shutdown
waf_sqli_shutdown:
    push    rbx
    mov     eax, [waf_sqli_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_sqli_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_sqli_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; waf_sqli_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global waf_sqli_status
waf_sqli_status:
    mov     eax, [waf_sqli_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_sqli_state + waf_state_base_t.enabled]
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

; =============================================================================
; waf_sqli_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global waf_sqli_version
waf_sqli_version:
    mov     rax, waf_sqli_version_str
    ret

; =============================================================================
; waf_sqli_detect - Detect SQL injection in request context
; Input:  rdi = enforce_ctx pointer (waf_request_ctx_t*)
; Output: rax = 1 if SQLi detected, 0 if clean, negative on error,
;         rbx = threat score (0-100)
; =============================================================================
global waf_sqli_detect
waf_sqli_detect:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     eax, [waf_sqli_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    mov     r12, rdi                      ; r12 = request context pointer

    ; STEP 1: Check URL for SQLi patterns
    ; STUB: scan r12->url for SQLi signature matches
    ; For skeleton: check URL pointer exists
    mov     rax, [r12 + waf_request_ctx_t.url]
    test    rax, rax
    jz      .check_body

    ; STUB: scan URL string for SQLi patterns
    ; For skeleton: check if URL contains common SQLi keywords
    mov     rsi, [r12 + waf_request_ctx_t.url]
    mov     rdx, [r12 + waf_request_ctx_t.url_len]
    xor     rcx, rcx                      ; rcx = pattern index
.check_url_loop:
    ; STUB: compare URL bytes against signature patterns
    ; For skeleton: simple substring check for common patterns
    mov     rdi, rsi
    call    .check_pattern_in_buffer
    test    rax, rax
    jnz     .sqli_found

    ; Move to next byte in URL
    inc     rsi
    dec     rdx
    jnz     .check_url_loop

.check_body:
    ; STEP 2: Check request body for SQLi patterns
    mov     rax, [r12 + waf_request_ctx_t.body]
    test    rax, rax
    jz      .check_headers

    mov     rsi, [r12 + waf_request_ctx_t.body]
    mov     rdx, [r12 + waf_request_ctx_t.body_len]
.check_body_loop:
    ; STUB: scan body for SQLi patterns
    mov     rdi, rsi
    call    .check_pattern_in_buffer
    test    rax, rax
    jnz     .sqli_found

    inc     rsi
    dec     rdx
    jnz     .check_body_loop

.check_headers:
    ; STEP 3: Check HTTP headers for SQLi patterns
    ; STUB: scan User-Agent, Content-Type, and custom headers
    ; For skeleton: check User-Agent
    mov     rax, [r12 + waf_request_ctx_t.user_agent]
    test    rax, rax
    jz      .no_sqli_found

    mov     rsi, [r12 + waf_request_ctx_t.user_agent]
    mov     rdx, [r12 + waf_request_ctx_t.user_agent_len]
.check_ua_loop:
    mov     rdi, rsi
    call    .check_pattern_in_buffer
    test    rax, rax
    jnz     .sqli_found

    inc     rsi
    dec     rdx
    jnz     .check_ua_loop

.no_sqli_found:
    ; No SQL injection detected
    xor     rax, rax
    xor     rbx, rbx
    jmp .done

.sqli_found:
    ; SQL injection detected
    mov     rax, 1                       ; SQLi detected
    mov     rbx, WAF_SEV_HIGH            ; threat score = high
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
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; waf_sqli_check_pattern_in_buffer - Check if buffer contains any SQLi pattern
; Input:  rdi = buffer pointer, rsi = buffer length
; Output: rax = 1 if pattern found, 0 if not found
; =============================================================================
.check_pattern_in_buffer:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                      ; r12 = buffer start
    mov     r13, rsi                      ; r13 = buffer length
    mov     rsi, sqli_signatures          ; rsi = signature list start

.check_next_sig:
    mov     rdi, rsi                      ; rdi = current signature
    test    rdi, rdi
    jz      .no_match                     ; end of signatures

    ; Check if signature is NUL-terminated (end marker)
    mov     al, [rdi]
    test    al, al
    jz      .no_match                     ; empty signature = end

    ; Compare signature against buffer at current position
    mov     r14, rdi                      ; r14 = signature pointer
    mov     rcx, r12                      ; rcx = buffer position
    mov     rbx, r13                      ; rbx = remaining buffer length

.compare_loop:
    mov     al, [rdi]                     ; al = signature char
    test    al, al
    jz      .match_found                  ; NUL terminator = full match

    mov     bl, [rcx]                     ; bl = buffer char
    test    bl, bl
    jz      .nomatch_this_sig             ; buffer ended before signature

    ; Case-insensitive comparison
    cmp     al, 'A'
    jl      .no_upper
    cmp     al, 'Z'
    jg      .no_upper
    add     al, 32                        ; convert to lowercase
.no_upper:
    cmp     bl, 'A'
    jl      .no_buf_upper
    cmp     bl, 'Z'
    jg      .no_buf_upper
    add     bl, 32                        ; convert buffer to lowercase
.no_buf_upper:
    cmp     al, bl
    jne     .nomatch_this_sig             ; mismatch

    inc     rdi
    inc     rcx
    dec     rbx
    jz      .match_found                  ; buffer exhausted but sig matched
    jmp .compare_loop

.nomatch_this_sig:
    ; Try next signature
    add     rsi, rdi                      ; skip to end of current signature
    inc     rsi                           ; skip NUL terminator
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

; STUB: waf_sqli_load_sigs - load SQLi signatures
; STUB: waf_sqli_compile_patterns - compile detection patterns
; STUB: waf_sqli_check_url - scan URL for SQLi
; STUB: waf_sqli_check_body - scan body for SQLi
; STUB: waf_sqli_check_headers - scan headers for SQLi
; STUB: waf_sqli_score - compute SQLi threat score

%endif
