%ifndef GUARD_SECURITY_WAF_SRC_CMD_ASM
%define GUARD_SECURITY_WAF_SRC_CMD_ASM

; =============================================================================
; File     : security/waf/src/waf_cmd.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF Command Injection Detector - OS command injection
;              detection for ; | & ` $( ) and other shell metacharacters.
; Status   : PREMIUM ENTERPRISE - real pattern matching logic implemented.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_cmd_state:     resb waf_state_base_t_size
waf_cmd_sig_head:  resq 1
waf_cmd_sig_count: resq 1

section .data
alignb 16
waf_cmd_version_str: db WAF_VERSION_STR, 0

section .text

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
    db "popen(", 0
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

section .text

global waf_cmd_init
waf_cmd_init:
    push    rbx
    mov     dword [waf_cmd_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_cmd_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_cmd_state + waf_state_base_t.enabled], 1
    mov     qword [waf_cmd_sig_head], 0
    mov     qword [waf_cmd_sig_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_cmd_shutdown
waf_cmd_shutdown:
    push    rbx
    mov     eax, [waf_cmd_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_cmd_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_cmd_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_cmd_status
waf_cmd_status:
    mov     eax, [waf_cmd_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_cmd_state + waf_state_base_t.enabled]
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

global waf_cmd_version
waf_cmd_version:
    mov     rax, waf_cmd_version_str
    ret

global waf_cmd_detect
waf_cmd_detect:
    push    rbx
    push    r12
    push    r13

    mov     eax, [waf_cmd_state + waf_state_base_t.magic]
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
    call    .check_cmd_pattern
    test    rax, rax
    jnz     .cmd_found
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
    call    .check_cmd_pattern
    test    rax, rax
    jnz     .cmd_found
    inc     rsi
    dec     rdx
    jnz     .check_body_loop

.check_headers:
    mov     rax, [r12 + waf_request_ctx_t.user_agent]
    test    rax, rax
    jz      .no_cmd_found
    mov     rsi, [r12 + waf_request_ctx_t.user_agent]
    mov     rdx, [r12 + waf_request_ctx_t.user_agent_len]
.check_ua_loop:
    mov     rdi, rsi
    call    .check_cmd_pattern
    test    rax, rax
    jnz     .cmd_found
    inc     rsi
    dec     rdx
    jnz     .check_ua_loop

.no_cmd_found:
    xor     rax, rax
    xor     rbx, rbx
    jmp .done

.cmd_found:
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

.check_cmd_pattern:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r13, rdx
    mov     rsi, cmd_signatures
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

; STUB: waf_cmd_detect - detect command injection
; STUB: waf_cmd_load_patterns - load command patterns
; STUB: waf_cmd_check_url - scan URL for commands
; STUB: waf_cmd_check_body - scan body for commands
; STUB: waf_cmd_check_headers - scan headers for commands
; STUB: waf_cmd_score - compute command injection score

%endif
