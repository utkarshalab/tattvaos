; UTM Kernel - Alert Engine
; Pure Assembly Implementation

%ifndef _UTM_ALERT_ENGINE_ASM_
%define _UTM_ENTERPRISE_ALERT_ENGINE_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .rodata
utm_alert_lock dq 0

section .bss
align 64
global utm_alert_rules
utm_alert_rules:
    resb MAX_ALERT_RULES * ALERT_RULE_SIZE

global utm_alert_events
utm_alert_events:
    resb MAX_ALERT_RULES * ALERT_EVENT_SIZE

global utm_alert_rule_count
utm_alert_rule_count:
    resq 1

global utm_alert_event_count
utm_alert_event_count:
    resq 1

section .text

global utm_alert_engine_init
global utm_alert_add_rule
global utm_alert_remove_rule
global utm_alert_check
global utm_alert_ack

extern utm_get_monotonic_ns

utm_alert_engine_init:
    mov rdi, utm_alert_rules
    mov rcx, MAX_ALERT_RULES * ALERT_RULE_SIZE / 8
    xor rax, rax
    rep stosq
    
    mov rdi, utm_alert_events
    mov rcx, MAX_ALERT_RULES * ALERT_EVENT_SIZE / 8
    xor rax, rax
    rep stosq
    
    mov rsi, utm_alert_rule_count
    mov qword [rsi], 0
    mov rsi, utm_alert_event_count
    mov qword [rsi], 0
    ret

utm_alert_add_rule:
    mov rax, [utm_alert_rule_count]
    cmp rax, MAX_ALERT_RULES
    jge .add_max_rules
    
    mov rcx, rax
    imul rcx, ALERT_RULE_SIZE
    mov r8, rdi
    mov rdi, utm_alert_rules
    add rdi, rcx
    mov rcx, ALERT_RULE_SIZE / 8
    rep movsq
    
    mov rsi, utm_alert_rule_count
    inc qword [rsi]
    mov rax, rcx
    ret

.add_max_rules:
    mov rax, UTM_ERR_OVERFLOW
    ret

utm_alert_remove_rule:
    mov rsi, utm_alert_rule_count
    cmp rdi, [rsi]
    jae .remove_not_found
    
    mov rcx, rdi
    imul rcx, ALERT_RULE_SIZE
    mov rdi, utm_alert_rules
    add rdi, rcx
    mov byte [rdi + AlertRule.enabled], 0
    
    xor rax, rax
    ret

.remove_not_found:
    mov rax, UTM_ERR_NOTFOUND
    ret

utm_alert_check:
    mov rcx, [utm_alert_rule_count]
    test rcx, rcx
    jz .check_done
    
    mov rsi, utm_alert_rules
.check_loop:
    push rcx
    push rsi
    
    cmp byte [rsi + AlertRule.enabled], 0
    je .check_skip
    
    mov eax, [rdi + SystemSample.cpu_total_percent]
    cmp dword [rsi + AlertRule.threshold], 0
    je .check_gt
    
.check_gt:
    cmp eax, [rsi + AlertRule.threshold]
    jle .check_skip
    
    call utm_alert_trigger
    
.check_skip:
    pop rsi
    pop rcx
    add rsi, ALERT_RULE_SIZE
    loop .check_loop
    
.check_done:
    ret

utm_alert_trigger:
    mov rsi, utm_alert_event_count
    mov rax, [rsi]
    cmp rax, MAX_ALERT_RULES
    jge .trigger_max_events
    
    mov rcx, rax
    imul rcx, ALERT_EVENT_SIZE
    mov rdi, utm_alert_events
    add rdi, rcx
    
    mov [rdi + AlertEvent.event_id], rax
    call utm_get_monotonic_ns
    mov [rdi + AlertEvent.timestamp_ns], rax
    
    mov rsi, utm_alert_event_count
    inc qword [rsi]
    ret

.trigger_max_events:
    ret

utm_alert_ack:
    mov rsi, utm_alert_event_count
    cmp rdi, [rsi]
    jae .ack_not_found
    
    mov rcx, rdi
    imul rcx, ALERT_EVENT_SIZE
    mov rdi, utm_alert_events
    add rdi, rcx
    
    call utm_get_monotonic_ns
    mov [rdi + AlertEvent.resolved_at], rax
    mov byte [rdi + AlertEvent.resolved], 1
    
    xor rax, rax
    ret

.ack_not_found:
    mov rax, UTM_ERR_NOTFOUND
    ret

%endif