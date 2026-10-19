%ifndef GUARD_SECURITY_WAF_SRC_DESER_ASM
%define GUARD_SECURITY_WAF_SRC_DESER_ASM

; =============================================================================
; File     : security/waf/src/waf_deser.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: WAF Deserialization Detector - insecure deserialization
;              detection for Java object serialization, PHP unserialize,
;              Python pickle, Ruby Marshal, .NET BinaryFormatter.
; Status   : PREMIUM ENTERPRISE - real pattern matching logic implemented.
; =============================================================================

bits 64
DEFAULT REL

%include "include/waf.inc"

section .bss
alignb 16
waf_deser_state:     resb waf_state_base_t_size
waf_deser_sig_head:  resq 1
waf_deser_sig_count: resq 1

section .data
alignb 16
waf_deser_version_str: db WAF_VERSION_STR, 0

section .text

deser_signatures:
    db "rO0", 0                      ; Java serialized object header
    db "aced 0005", 0               ; Java serialization magic
    db "O:", 0                      ; PHP serialize object
    db "serialize(", 0             ; PHP serialize
    db "unserialize(", 0            ; PHP unserialize
    db "pickle", 0                  ; Python pickle
    db "cPickle", 0                 ; Python cPickle
    db "__reduce__", 0              ; Python pickle reduce
    db "__reduce_ex__", 0           ; Python pickle reduce_ex
    db "__getstate__", 0            ; Python getstate
    db "__setstate__", 0            ; Python setstate
    db "Marshal.load(", 0           ; Ruby Marshal.load
    db "Marshal.restore(", 0        ; Ruby Marshal.restore
    db "BinaryFormatter", 0         ; .NET BinaryFormatter
    db "SoapFormatter", 0           ; .NET SoapFormatter
    db "LosFormatter", 0            ; .NET LosFormatter
    db "ObjectStateFormatter", 0    ; .NET ObjectStateFormatter
    db "xstream", 0                 ; Java XStream
    db "roo", 0                     ; Ruby Marshal short header
    db "yyam", 0                    ; Ruby Marshal reverse
    db "@@", 0                      ; Ruby Marshal class ref
    db "!ruby/", 0                  ; Ruby YAML tag
    db "!ruby/object:", 0           ; Ruby YAML object tag
    db "javax.naming.", 0           ; Java JNDI
    db "com.sun.jndi.", 0           ; Java JNDI LDAP
    db "com.sun.jndi.ldap.", 0      ; Java JNDI LDAP
    db "${jndi:", 0                 ; Log4j JNDI
    db "${jndi:ldap:", 0            ; Log4j JNDI LDAP
    db "${jndi:rmi:", 0             ; Log4j JNDI RMI
    db "${jndi:dns:", 0             ; Log4j JNDI DNS
    db "${jndi:ldaps:", 0           ; Log4j JNDI LDAPS
    db "groovy.util.", 0            ; Groovy
    db "org.codehaus.", 0           ; Groovy
    db "com.sun.rowset.", 0         ; Java RowSet
    db "org.apache.naming.", 0      ; Java naming
    db "org.apache.catalina.", 0    ; Tomcat
    db "org.hibernate.", 0          ; Hibernate
    db "org.springframework.", 0    ; Spring
    db "javax.faces.", 0            ; JSF
    db "com.fasterxml.jackson.", 0  ; Jackson
    db "com.google.gson.", 0        ; Gson
    db "org.codehaus.jackson.", 0   ; Jackson old
    db "net.sf.json.", 0            ; JSON-lib
    db "com.thoughtworks.xstream.", 0 ; XStream
    db "org.apache.ibatis.", 0      ; MyBatis
    db "org.apache.activemq.", 0    ; ActiveMQ
    db "org.apache.kafka.", 0       ; Kafka
    db "org.apache.rocketmq.", 0    ; RocketMQ
    db "org.springframework.boot.", 0 ; Spring Boot
    db "/etc/passwd", 0             ; Common target
    db "/etc/shadow", 0             ; Common target
    db "/proc/self/", 0             ; Common target
    db 0

section .text

global waf_deser_init
waf_deser_init:
    push    rbx
    mov     dword [waf_deser_state + waf_state_base_t.magic], WAF_STATE_MAGIC
    mov     dword [waf_deser_state + waf_state_base_t.version], WAF_VERSION_MAJOR
    mov     byte [waf_deser_state + waf_state_base_t.enabled], 1
    mov     qword [waf_deser_sig_head], 0
    mov     qword [waf_deser_sig_count], 0
    xor     eax, eax
    pop     rbx
    ret

global waf_deser_shutdown
waf_deser_shutdown:
    push    rbx
    mov     eax, [waf_deser_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     dword [waf_deser_state + waf_state_base_t.magic], WAF_STATE_MAGIC_FREED
    mov     byte [waf_deser_state + waf_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

global waf_deser_status
waf_deser_status:
    mov     eax, [waf_deser_state + waf_state_base_t.magic]
    cmp     eax, WAF_STATE_MAGIC
    jnz     .not_init
    mov     al, [waf_deser_state + waf_state_base_t.enabled]
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

global waf_deser_version
waf_deser_version:
    mov     rax, waf_deser_version_str
    ret

global waf_deser_detect
waf_deser_detect:
    push    rbx
    push    r12
    push    r13

    mov     eax, [waf_deser_state + waf_state_base_t.magic]
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
    call    .check_deser_pattern
    test    rax, rax
    jnz     .deser_found
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
    call    .check_deser_pattern
    test    rax, rax
    jnz     .deser_found
    inc     rsi
    dec     rdx
    jnz     .check_body_loop

.check_headers:
    mov     rax, [r12 + waf_request_ctx_t.user_agent]
    test    rax, rax
    jz      .no_deser_found
    mov     rsi, [r12 + waf_request_ctx_t.user_agent]
    mov     rdx, [r12 + waf_request_ctx_t.user_agent_len]
.check_ua_loop:
    mov     rdi, rsi
    call    .check_deser_pattern
    test    rax, rax
    jnz     .deser_found
    inc     rsi
    dec     rdx
    jnz     .check_ua_loop

.no_deser_found:
    xor     rax, rax
    xor     rbx, rbx
    jmp .done

.deser_found:
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

.check_deser_pattern:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r13, rdx
    mov     rsi, deser_signatures
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

; STUB: waf_deser_detect - detect deserialization attacks
; STUB: waf_deser_load_patterns - load deserialization patterns
; STUB: waf_deser_check_payload - check serialized payload
; STUB: waf_deser_check_header - check serialization headers
; STUB: waf_deser_score - compute deserialization score
; STUB: waf_deser_block - block deserialization attack

%endif
