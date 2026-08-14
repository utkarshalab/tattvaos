%ifndef GUARD_SECURITY_USRAUTH_POLICY_CONSENT_ASM
%define GUARD_SECURITY_USRAUTH_POLICY_CONSENT_ASM
; =============================================================================
; Tattva OS — security/usrauth/policy/consent.asm
; =============================================================================
; L4 — User Consent Gate (macOS TCC model).
;
; Implements:
;   - Consent recording and revocation (`usrauth_consent_grant`, `_revoke`)
;   - Consent lookup with expiry (`usrauth_consent_check`)
;   - Sensitive-class registration (`usrauth_consent_require`)
;
; Some resource classes should not be reachable on policy alone, however well
; the policy is written — a camera, a microphone, a key store, the raw disk.
; For these, an explicit human decision is an ADDITIONAL requirement layered on
; top of everything else.
;
; This is TCC's contribution. Note what it is not: consent never GRANTS. A
; subject with consent but no capability and no relation still gets nothing.
; Consent only removes a veto, which keeps it inside the intersection model
; rather than beside it.
;
; Consent is recorded per (subject, class) rather than per object, matching how
; people actually reason about permission — "this program may use the
; microphone", not "this program may use microphone #3".
;
; Grants expire by default. A consent decision made once and honoured forever
; is how permission dialogs become meaningless.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_MAX_CONSENTS         128
%define USRAUTH_CONSENT_DEFAULT_TTL  0      ; 0 = caller must state a lifetime

struc usrauth_consent_t
    .subject_handle:    resd 1
    .object_class:      resd 1      ; USRAUTH_CLASS_*
    .verbs:             resd 1      ; What the human actually agreed to
    .active:            resd 1
    .expires_ns:        resq 1      ; 0 = permanent; discouraged
    .granted_ns:        resq 1
endstruc

section .data
align 64

global usrauth_consents
usrauth_consents:
    times USRAUTH_MAX_CONSENTS * usrauth_consent_t_size db 0

usrauth_consent_count:      dq 0
; Bitmask of classes that require consent. Everything else passes the gate.
usrauth_consent_required:   dq 0
usrauth_consent_denials:    dq 0

section .text

global usrauth_consent_require
global usrauth_consent_grant
global usrauth_consent_revoke
global usrauth_consent_check

; -----------------------------------------------------------------------------
; usrauth_consent_require
;
; Marks an object class as requiring explicit consent.
;
; Inputs:
;   EDI = USRAUTH_CLASS_*
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_consent_require:
    cmp edi, 63
    ja .cr_inval
    mov ecx, edi
    mov rax, 1
    shl rax, cl
    or [usrauth_consent_required], rax
    xor eax, eax
    ret
.cr_inval:
    mov eax, USRAUTH_DENY_INVALID
    ret

; -----------------------------------------------------------------------------
; usrauth_consent_grant
;
; Records a human decision.
;
; Inputs:
;   EDI = Subject handle
;   ESI = Object class
;   EDX = Verbs consented to
;   RCX = Lifetime in ns, or 0 for permanent
;
; Returns:
;   EAX = Consent index, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_consent_grant:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15, rcx

    and r14d, USRAUTH_VERB_MASK
    test r14d, r14d
    jz .cg_inval                    ; Consent to nothing is not consent

    mov rax, [usrauth_consent_count]
    cmp rax, USRAUTH_MAX_CONSENTS
    jae .cg_inval

    mov rbx, rax
    imul rbx, usrauth_consent_t_size
    lea rcx, [usrauth_consents]
    add rbx, rcx

    mov dword [rbx + usrauth_consent_t.subject_handle], r12d
    mov dword [rbx + usrauth_consent_t.object_class], r13d
    mov dword [rbx + usrauth_consent_t.verbs], r14d
    mov dword [rbx + usrauth_consent_t.active], 1

    call mono_get_nanos
    mov [rbx + usrauth_consent_t.granted_ns], rax

    ; Convert a lifetime into an absolute deadline.
    test r15, r15
    jz .cg_permanent
    add rax, r15
    mov [rbx + usrauth_consent_t.expires_ns], rax
    jmp .cg_done

.cg_permanent:
    mov qword [rbx + usrauth_consent_t.expires_ns], 0

.cg_done:
    inc qword [usrauth_consent_count]
    call usrauth_policy_bump_epoch

    mov rax, [usrauth_consent_count]
    dec rax
    jmp .cg_return

.cg_inval:
    mov eax, USRAUTH_DENY_INVALID

.cg_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_consent_revoke
;
; Withdraws consent. Revocation is immediate — a person changing their mind
; should not have to wait for an expiry.
;
; Inputs:
;   EDI = Subject handle
;   ESI = Object class
;
; Returns:
;   EAX = Number revoked
; -----------------------------------------------------------------------------
align 32
usrauth_consent_revoke:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi
    mov r13d, esi
    xor r14d, r14d

    mov rcx, [usrauth_consent_count]
    lea rbx, [usrauth_consents]

.rv_loop:
    test rcx, rcx
    jz .rv_done

    cmp dword [rbx + usrauth_consent_t.active], 0
    je .rv_next
    cmp dword [rbx + usrauth_consent_t.subject_handle], r12d
    jne .rv_next
    cmp dword [rbx + usrauth_consent_t.object_class], r13d
    jne .rv_next

    mov dword [rbx + usrauth_consent_t.active], 0
    inc r14d

.rv_next:
    add rbx, usrauth_consent_t_size
    dec rcx
    jmp .rv_loop

.rv_done:
    test r14d, r14d
    jz .rv_return
    call usrauth_policy_bump_epoch

.rv_return:
    mov eax, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_consent_check
;
; Gates access to a class that requires consent.
;
; Classes not marked as requiring consent pass immediately — this gate exists
; to add a requirement for a small set of sensitive resources, not to become a
; second permission system for everything.
;
; Inputs:
;   EDI = Subject handle
;   ESI = Object class
;   EDX = Requested verbs
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_POLICY
; -----------------------------------------------------------------------------
align 32
usrauth_consent_check:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    and r14d, USRAUTH_VERB_MASK

    ; Does this class need consent at all?
    cmp r13d, 63
    ja .cc_deny
    mov ecx, r13d
    mov rax, 1
    shl rax, cl
    test [usrauth_consent_required], rax
    jz .cc_allow                    ; Not a gated class

    call mono_get_nanos
    mov r15, rax

    mov rcx, [usrauth_consent_count]
    lea rbx, [usrauth_consents]

.cc_loop:
    test rcx, rcx
    jz .cc_deny                     ; Gated class with no matching consent

    cmp dword [rbx + usrauth_consent_t.active], 0
    je .cc_next
    cmp dword [rbx + usrauth_consent_t.subject_handle], r12d
    jne .cc_next
    cmp dword [rbx + usrauth_consent_t.object_class], r13d
    jne .cc_next

    ; Expired consent is no consent.
    mov rax, [rbx + usrauth_consent_t.expires_ns]
    test rax, rax
    jz .cc_live
    cmp r15, rax
    jae .cc_next

.cc_live:
    ; The human must have agreed to at least what is being requested.
    mov eax, dword [rbx + usrauth_consent_t.verbs]
    mov edx, eax
    and edx, r14d
    cmp edx, r14d
    jne .cc_next                    ; Consented to less than this

    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.cc_next:
    add rbx, usrauth_consent_t_size
    dec rcx
    jmp .cc_loop

.cc_allow:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.cc_deny:
    inc qword [usrauth_consent_denials]
    mov eax, USRAUTH_DENY_POLICY
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_SECURITY_USRAUTH_POLICY_CONSENT_ASM
