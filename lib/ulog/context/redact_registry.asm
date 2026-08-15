; =============================================================================
; Tattva OS — lib/ulog/context/redact_registry.asm
; =============================================================================
; Which (module_id, field key) pairs are sensitive — crypto/ucrypt key
; material, security/usrauth capability tokens — so emit_fmt.asm can scrub
; a value before it ever reaches a sink, and mark log_record_t.redacted so
; a reader knows scrubbing happened rather than assuming the field was
; simply absent.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_REDACT_REGISTRY_ASM
%define LIB_ULOG_CONTEXT_REDACT_REGISTRY_ASM

[BITS 64]

%define REDACT_MAX_RULES  64

struc redact_rule_t
    .module_id    resw 1
    .reserved     resw 1
    .key_ptr      resq 1
endstruc

section .text

; -----------------------------------------------------------------------------
; redact_registry_add — Input: DI = module_id, RSI = key_ptr (static string)
; Output: RAX = 1 ok, 0 if REDACT_MAX_RULES already reached
; -----------------------------------------------------------------------------
global redact_registry_add
redact_registry_add:
    push rbx
    push rcx

    mov ecx, [ulog_redact_count]
    cmp ecx, REDACT_MAX_RULES
    jae .full

    mov rbx, redact_rule_t_size
    imul rbx, rcx
    add rbx, ulog_redact_rules

    mov [rbx + redact_rule_t.module_id], di
    mov [rbx + redact_rule_t.key_ptr], rsi

    inc dword [ulog_redact_count]
    mov rax, 1
    jmp .done

.full:
    xor rax, rax

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; redact_registry_check — Input: DI = module_id, RSI = key_ptr
; Output: RAX = 1 if this (module, key) pair is registered as sensitive
; -----------------------------------------------------------------------------
global redact_registry_check
redact_registry_check:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    xor ecx, ecx
.scan:
    cmp ecx, [ulog_redact_count]
    jae .no_match

    mov rbx, redact_rule_t_size
    imul rbx, rcx
    add rbx, ulog_redact_rules

    cmp [rbx + redact_rule_t.module_id], di
    jne .next

    ; string-compare key_ptr against rule's key_ptr
    mov rdx, [rbx + redact_rule_t.key_ptr]
.cmp_loop:
    mov al, [rsi]
    cmp al, [rdx]
    jne .next
    test al, al
    jz .match
    inc rsi
    inc rdx
    jmp .cmp_loop

.next:
    inc ecx
    mov rsi, [rsp]                   ; restore RSI (key_ptr) for the next rule's comparison
    jmp .scan

.match:
    mov rax, 1
    jmp .done

.no_match:
    xor rax, rax

.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

section .bss
alignb 8
global ulog_redact_rules
ulog_redact_rules: resb (redact_rule_t_size * REDACT_MAX_RULES)
global ulog_redact_count
ulog_redact_count: resd 1

%endif ; LIB_ULOG_CONTEXT_REDACT_REGISTRY_ASM
