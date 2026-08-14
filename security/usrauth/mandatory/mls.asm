%ifndef GUARD_SECURITY_USRAUTH_MANDATORY_MLS_ASM
%define GUARD_SECURITY_USRAUTH_MANDATORY_MLS_ASM
; =============================================================================
; Tattva OS — security/usrauth/mandatory/mls.asm
; =============================================================================
; L5 — Multi-Level Security (Bell-LaPadula).
;
; Implements:
;   - Enable / disable (`usrauth_mls_enable`)
;   - Label dominance (`usrauth_mls_dominates`)
;   - Read/write constraint enforcement (`usrauth_mls_check`)
;
; Bell-LaPadula protects CONFIDENTIALITY through two rules:
;
;   No READ UP    — a subject may not read above its clearance
;   No WRITE DOWN — a subject may not write below its clearance, because that
;                   would launder classified data into a lower level
;
; The write-down rule is the one people find counter-intuitive and remove.
; Removing it makes the model decorative: any cleared subject could then simply
; copy secrets downward at will, which is precisely the leak the model exists
; to prevent.
;
; Dominance requires BOTH a level at least as high AND a superset of
; categories. The category test is a superset check, not an intersection —
; sharing one compartment does not confer access to another, which is the
; entire purpose of compartments.
;
; MLS points the opposite way to Biba integrity (mandatory/integrity.asm):
; one governs reads for secrecy, the other writes for trustworthiness. They are
; deliberately separate.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .text

global usrauth_mls_enable
global usrauth_mls_dominates
global usrauth_mls_check

; -----------------------------------------------------------------------------
align 32
usrauth_mls_enable:
    xor eax, eax
    test edi, edi
    setnz al
    mov [usrauth_mls_enabled], rax
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usrauth_te_add
;
; Adds an allow rule: (subject type, object type, class) -> verbs.
;
; Inputs:
;   EDI = Subject type
;   ESI = Object type
;   EDX = Object class
;   ECX = Allowed verb bitmask
;
; Returns:
;   EAX = Rule index, or USRAUTH_DENY_INVALID when the table is full
; -----------------------------------------------------------------------------
align 32
usrauth_te_add:
    push rbx
    push r12

    ; Capture the verb argument BEFORE RCX is reused as scratch. Computing the
    ; table address into RCX first would overwrite it, and the mask would then
    ; be applied to the address rather than the verbs.
    mov r12d, ecx
    and r12d, USRAUTH_VERB_MASK

    mov rax, [usrauth_te_count]
    cmp rax, USRAUTH_MAX_TE_RULES
    jae .ta_full

    mov rbx, rax
    imul rbx, usrauth_te_rule_t_size
    lea rcx, [usrauth_te_rules]
    add rbx, rcx

    mov dword [rbx + usrauth_te_rule_t.subject_type], edi
    mov dword [rbx + usrauth_te_rule_t.object_type], esi
    mov dword [rbx + usrauth_te_rule_t.object_class], edx
    mov dword [rbx + usrauth_te_rule_t.allowed_verbs], r12d

    inc qword [usrauth_te_count]

    pop r12
    pop rbx
    ret

.ta_full:
    mov eax, USRAUTH_DENY_INVALID
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_te_check
;
; Type enforcement. Verbs allowed by any matching rule are unioned, then the
; request must be fully covered.
;
; Unioning ACROSS RULES is correct and is not the union-grant hazard: every
; rule here comes from the same signed policy artifact, so there is still only
; one authority. The hazard is unioning across independent LAYERS.
;
; Inputs:
;   EDI = Subject type
;   ESI = Object type
;   EDX = Object class
;   ECX = Requested verbs
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_MANDATORY
; -----------------------------------------------------------------------------
align 32
usrauth_te_check:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; Subject type
    mov r13d, esi                   ; Object type
    mov r14d, edx                   ; Class
    mov r15d, ecx                   ; Requested
    and r15d, USRAUTH_VERB_MASK

    test r15d, r15d
    jz .tc_allow                    ; Requesting nothing is trivially allowed

    xor r8d, r8d                    ; Accumulated allowance
    mov rcx, [usrauth_te_count]
    lea rbx, [usrauth_te_rules]

.tc_loop:
    test rcx, rcx
    jz .tc_decide

    cmp dword [rbx + usrauth_te_rule_t.subject_type], r12d
    jne .tc_next
    cmp dword [rbx + usrauth_te_rule_t.object_type], r13d
    jne .tc_next
    cmp dword [rbx + usrauth_te_rule_t.object_class], r14d
    jne .tc_next

    mov eax, dword [rbx + usrauth_te_rule_t.allowed_verbs]
    or r8d, eax

.tc_next:
    add rbx, usrauth_te_rule_t_size
    dec rcx
    jmp .tc_loop

.tc_decide:
    mov eax, r8d
    and eax, r15d
    cmp eax, r15d
    je .tc_allow

    inc qword [usrauth_te_denials]

    ; Permissive mode records the denial but lets the access proceed.
    cmp qword [usrauth_te_enforcing], 0
    je .tc_allow

    mov eax, USRAUTH_DENY_MANDATORY
    jmp .tc_return

.tc_allow:
    xor eax, eax

.tc_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_mls_dominates
;
; Label A dominates B when A's level is at least B's AND A's category set is a
; superset of B's.
;
; The category test is a superset check, not an intersection test. Sharing one
; compartment does not confer access to another — that is the whole purpose of
; compartments.
;
; Inputs:
;   RDI = Pointer to label A
;   RSI = Pointer to label B
;
; Returns:
;   EAX = 1 when A dominates B, 0 otherwise
; -----------------------------------------------------------------------------
align 32
usrauth_mls_dominates:
    mov eax, dword [rdi + usrauth_label_t.level]
    cmp eax, dword [rsi + usrauth_label_t.level]
    jb .md_no

    ; A must contain every category B has: (B & ~A) == 0
    mov rax, [rdi + usrauth_label_t.categories]
    not rax
    and rax, [rsi + usrauth_label_t.categories]
    test rax, rax
    jnz .md_no

    mov eax, 1
    ret

.md_no:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usrauth_mls_check
;
; Bell-LaPadula.
;
; Inputs:
;   RDI = Subject label
;   RSI = Object label
;   EDX = Requested verbs
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_MLS
; -----------------------------------------------------------------------------
align 32
usrauth_mls_check:
    push rbx
    push r12
    push r13

    cmp qword [usrauth_mls_enabled], 0
    je .mc_allow                    ; Not in force

    mov rbx, rdi                    ; Subject label
    mov r12, rsi                    ; Object label
    mov r13d, edx                   ; Verbs

    ; --- No read up: subject must dominate object ---
    test r13d, USRAUTH_VERB_READ | USRAUTH_VERB_EXEC
    jz .mc_write_phase

    mov rdi, rbx
    mov rsi, r12
    call usrauth_mls_dominates
    test eax, eax
    jz .mc_deny

.mc_write_phase:
    ; --- No write down: object must dominate subject ---
    test r13d, USRAUTH_VERB_WRITE | USRAUTH_VERB_APPEND | USRAUTH_VERB_CREATE
    jz .mc_allow

    mov rdi, r12
    mov rsi, rbx
    call usrauth_mls_dominates
    test eax, eax
    jz .mc_deny

.mc_allow:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.mc_deny:
    inc qword [usrauth_mls_denials]
    mov eax, USRAUTH_DENY_MLS
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_mandatory_check
;
; The complete L5 verdict: type enforcement, then MLS.
;
; Inputs:
;   RDI = Pointer to a usrauth_subject_t
;   RSI = Pointer to a usrauth_object_t
;   EDX = Requested verbs
;
; Returns:
;   EAX = USRAUTH_ALLOW, USRAUTH_DENY_MANDATORY or USRAUTH_DENY_MLS

%endif ; GUARD_SECURITY_USRAUTH_MANDATORY_MLS_ASM
