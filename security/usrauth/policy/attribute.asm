%ifndef GUARD_SECURITY_USRAUTH_POLICY_ATTRIBUTE_ASM
%define GUARD_SECURITY_USRAUTH_POLICY_ATTRIBUTE_ASM
; =============================================================================
; Tattva OS — security/usrauth/policy/attribute.asm
; =============================================================================
; L4 — Attribute-Based Conditions (ABAC).
;
; Implements:
;   - Condition registration per object (`usrauth_attr_add`)
;   - Context evaluation (`usrauth_attr_check`)
;   - Request-context construction (`usrauth_attr_context_init`)
;
; Relations answer "is this subject related to this object". Attributes answer
; "is this request being made under acceptable circumstances" — time of day,
; device posture, network origin, how recently the subject re-authenticated.
;
; This is the BeyondCorp position: establishing a session is not the same as
; holding standing authority. Every request is evaluated against current
; context, so a session that was legitimate an hour ago on a compliant device
; does not remain legitimate after that device falls out of compliance.
;
; Conditions are CONSTRAINTS, never grants. Each one can only narrow what the
; relation layer already permitted. If a condition could grant, it would become
; a second authority and the intersection invariant would collapse — the same
; failure the whole design exists to avoid.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_MAX_ATTR_RULES       128

; Condition kinds.
%define USRAUTH_ATTR_TIME_WINDOW     1   ; arg_a = start ns, arg_b = end ns
%define USRAUTH_ATTR_MFA_RECENT      2   ; arg_a = max age of re-auth, ns
%define USRAUTH_ATTR_DEVICE_POSTURE  3   ; arg_a = required posture bitmask
%define USRAUTH_ATTR_NETWORK_ZONE    4   ; arg_a = permitted zone bitmask
%define USRAUTH_ATTR_ATTESTED        5   ; Subject must carry ATTESTED flag

; Device posture bits.
%define USRAUTH_POSTURE_ENCRYPTED    (1 << 0)
%define USRAUTH_POSTURE_PATCHED      (1 << 1)
%define USRAUTH_POSTURE_SECUREBOOT   (1 << 2)
%define USRAUTH_POSTURE_ATTESTED     (1 << 3)

struc usrauth_attr_rule_t
    .object_id:         resq 1
    .kind:              resd 1      ; USRAUTH_ATTR_*
    .active:            resd 1
    .arg_a:             resq 1
    .arg_b:             resq 1
endstruc

; The circumstances a request is made under. Supplied by the caller; uguard
; does not sample these itself because only the caller knows its own context.
struc usrauth_context_t
    .now_ns:            resq 1
    .last_auth_ns:      resq 1      ; When the subject last proved identity
    .posture:           resd 1      ; USRAUTH_POSTURE_* bitmask
    .network_zone:      resd 1      ; Single-bit zone identifier
endstruc

section .data
align 64

global usrauth_attr_rules
usrauth_attr_rules:
    times USRAUTH_MAX_ATTR_RULES * usrauth_attr_rule_t_size db 0

usrauth_attr_count:     dq 0
usrauth_attr_denials:   dq 0

section .text

global usrauth_attr_add
global usrauth_attr_check
global usrauth_attr_context_init

; -----------------------------------------------------------------------------
; usrauth_attr_context_init
;
; Fills a request context from the current clock plus caller-supplied posture.
;
; Inputs:
;   RDI = Pointer to a usrauth_context_t
;   RSI = Timestamp of the subject's last authentication, in ns
;   EDX = Device posture bitmask
;   ECX = Network zone
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_attr_context_init:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx

    test rbx, rbx
    jz .ci_inval

    call mono_get_nanos
    mov [rbx + usrauth_context_t.now_ns], rax

    mov [rbx + usrauth_context_t.last_auth_ns], r12
    mov dword [rbx + usrauth_context_t.posture], r13d
    mov dword [rbx + usrauth_context_t.network_zone], r14d

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.ci_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_attr_add
;
; Attaches a condition to an object.
;
; Inputs:
;   RDI = Object id
;   ESI = Condition kind
;   RDX = arg_a
;   RCX = arg_b
;
; Returns:
;   EAX = Rule index, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_attr_add:
    push rbx
    push r12
    push r13
    push r14

    ; Capture before RCX is reused for the table address.
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx

    cmp r12d, USRAUTH_ATTR_ATTESTED
    ja .aa_inval
    test r12d, r12d
    jz .aa_inval

    mov rax, [usrauth_attr_count]
    cmp rax, USRAUTH_MAX_ATTR_RULES
    jae .aa_inval

    mov rbx, rax
    imul rbx, usrauth_attr_rule_t_size
    lea rcx, [usrauth_attr_rules]
    add rbx, rcx

    mov [rbx + usrauth_attr_rule_t.object_id], rdi
    mov dword [rbx + usrauth_attr_rule_t.kind], r12d
    mov [rbx + usrauth_attr_rule_t.arg_a], r13
    mov [rbx + usrauth_attr_rule_t.arg_b], r14
    mov dword [rbx + usrauth_attr_rule_t.active], 1

    inc qword [usrauth_attr_count]

    ; Conditions change the answer, so cached decisions are stale.
    call usrauth_policy_bump_epoch

    mov rax, [usrauth_attr_count]
    dec rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.aa_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_attr_check
;
; Evaluates every condition attached to an object. ALL must hold.
;
; An object with no conditions passes trivially — conditions constrain, they do
; not grant, so their absence cannot be a denial.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   RDX = Pointer to a usrauth_context_t
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_POLICY
; -----------------------------------------------------------------------------
align 32
usrauth_attr_check:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; Subject
    mov r13, rsi                    ; Object
    mov r14, rdx                    ; Context

    test r14, r14
    jz .ac_deny                     ; No context supplied: cannot evaluate

    mov rcx, [usrauth_attr_count]
    lea rbx, [usrauth_attr_rules]

.ac_loop:
    test rcx, rcx
    jz .ac_allow

    cmp dword [rbx + usrauth_attr_rule_t.active], 0
    je .ac_next
    cmp [rbx + usrauth_attr_rule_t.object_id], r13
    jne .ac_next

    mov eax, dword [rbx + usrauth_attr_rule_t.kind]

    cmp eax, USRAUTH_ATTR_TIME_WINDOW
    je .ac_time
    cmp eax, USRAUTH_ATTR_MFA_RECENT
    je .ac_mfa
    cmp eax, USRAUTH_ATTR_DEVICE_POSTURE
    je .ac_posture
    cmp eax, USRAUTH_ATTR_NETWORK_ZONE
    je .ac_zone
    cmp eax, USRAUTH_ATTR_ATTESTED
    je .ac_attested

    ; Unknown condition kind must DENY. Skipping a restriction that this build
    ; does not understand would silently honour a policy it cannot enforce.
    jmp .ac_deny

.ac_time:
    mov rax, [r14 + usrauth_context_t.now_ns]
    cmp rax, [rbx + usrauth_attr_rule_t.arg_a]
    jb .ac_deny                     ; Before the window opens
    mov rdx, [rbx + usrauth_attr_rule_t.arg_b]
    test rdx, rdx
    jz .ac_next                     ; No upper bound
    cmp rax, rdx
    ja .ac_deny                     ; After it closes
    jmp .ac_next

.ac_mfa:
    ; now - last_auth must not exceed the permitted age.
    mov rax, [r14 + usrauth_context_t.now_ns]
    mov rdx, [r14 + usrauth_context_t.last_auth_ns]
    test rdx, rdx
    jz .ac_deny                     ; Never authenticated
    sub rax, rdx
    cmp rax, [rbx + usrauth_attr_rule_t.arg_a]
    ja .ac_deny                     ; Re-authentication too stale
    jmp .ac_next

.ac_posture:
    ; Every required posture bit must be present.
    mov eax, dword [r14 + usrauth_context_t.posture]
    mov edx, dword [rbx + usrauth_attr_rule_t.arg_a]
    and eax, edx
    cmp eax, edx
    jne .ac_deny
    jmp .ac_next

.ac_zone:
    mov eax, dword [r14 + usrauth_context_t.network_zone]
    mov edx, dword [rbx + usrauth_attr_rule_t.arg_a]
    test eax, edx
    jz .ac_deny                     ; Origin zone not permitted
    jmp .ac_next

.ac_attested:
    push rcx
    mov edi, r12d
    call usrauth_subject_get
    pop rcx
    test rax, rax
    jz .ac_deny
    test dword [rax + usrauth_subject_t.flags], USRAUTH_SUBJ_ATTESTED
    jz .ac_deny

.ac_next:
    add rbx, usrauth_attr_rule_t_size
    dec rcx
    jmp .ac_loop

.ac_allow:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.ac_deny:
    inc qword [usrauth_attr_denials]
    mov eax, USRAUTH_DENY_POLICY
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_SECURITY_USRAUTH_POLICY_ATTRIBUTE_ASM
