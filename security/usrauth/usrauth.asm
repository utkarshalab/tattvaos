; =============================================================================
; Tattva OS — security/usrauth/usrauth.asm
; =============================================================================
; Master USRAUTH (Reference Monitor) Dispatcher.
;
; Single-pass NASM included subsystem handler linking every usrauth layer:
;   L1 token      L2 subject      L3 capability
;   L4 policy     L5 mandatory    L6 audit
;
; THE INVARIANT: many independent ways to DENY, exactly ONE way to GRANT.
; Effective authority is the INTERSECTION of every layer. If a future layer is
; added that can independently answer "yes", this model breaks — union
; semantics grant precisely what another layer meant to withhold.
;
; Evaluation is ordered cheapest-denier-first. Correctness does not depend on
; the order (every term must hold), but latency does: an O(1) bitmask rejection
; should never sit behind an O(depth) graph walk.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "security/usrauth/usrauth.inc"

; -----------------------------------------------------------------------------
; L2 subject table and L3 capabilities — the handle model everything consumes.
; -----------------------------------------------------------------------------
%include "security/usrauth/subject/table.asm"
%include "security/usrauth/subject/transition.asm"
%include "security/usrauth/capability/cap.asm"
%include "security/usrauth/capability/restrict.asm"

; -----------------------------------------------------------------------------
; L5 mandatory — can only deny.
; -----------------------------------------------------------------------------
%include "security/usrauth/mandatory/te.asm"
%include "security/usrauth/mandatory/integrity.asm"
%include "security/usrauth/mandatory/mls.asm"

; -----------------------------------------------------------------------------
; L4 policy — relations, attributes, time-bounded grants.
; -----------------------------------------------------------------------------
%include "security/usrauth/policy/relation.asm"
%include "security/usrauth/policy/ttl.asm"
%include "security/usrauth/policy/attribute.asm"
%include "security/usrauth/policy/consent.asm"

; -----------------------------------------------------------------------------
; L1 tokens — attenuable bearer credentials.
; -----------------------------------------------------------------------------
%include "security/usrauth/token/caveat.asm"
%include "security/usrauth/token/token.asm"
%include "security/usrauth/token/revoke.asm"

; -----------------------------------------------------------------------------
; L0 identity — how a subject proves who it is.
; -----------------------------------------------------------------------------
%include "security/usrauth/identity/attest.asm"
%include "security/usrauth/identity/svid.asm"
%include "security/usrauth/identity/password.asm"
%include "security/usrauth/identity/webauthn.asm"

; -----------------------------------------------------------------------------
; L6 audit — tamper-evident decision chain.
; -----------------------------------------------------------------------------
%include "security/usrauth/audit/decision_log.asm"

section .data
align 8
usrauth_initialised:     dq 0
usrauth_checks:          dq 0

section .text

global usrauth_init
global usrauth_check
global usrauth_check_token
global usrauth_stats

; -----------------------------------------------------------------------------
; usrauth_init
;
; Brings the reference monitor online.
;
; Inputs:
;   RDI = Pointer to 32 token key bytes, or 0 to generate one
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_init:
    push rbx

    call usrauth_token_init

    ; Enforcing by default. A reference monitor that starts permissive and
    ; waits to be switched on will, in practice, be found switched off.
    mov edi, 1
    call usrauth_te_set_enforcing

    mov qword [usrauth_initialised], 1
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_check
;
; THE decision function. Every access in the system resolves here.
;
;   allow =  mandatory_allows      (L5, never overridable)
;          ∧ integrity_ok          (L2, no write-up)
;          ∧ capability_present    (L3, authority is held, not looked up)
;          ∧ policy_allows         (L4, relations + time bounds)
;
; Any single failure denies. No layer can grant past another's refusal.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Pointer to a usrauth_object_t
;   EDX = Requested verb bitmask
;
; Returns:
;   EAX = USRAUTH_ALLOW, or the USRAUTH_DENY_* code of the FIRST layer to refuse
; -----------------------------------------------------------------------------
align 32
usrauth_check:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; Subject handle
    mov r13, rsi                    ; Object
    mov r14d, edx                   ; Verbs
    and r14d, USRAUTH_VERB_MASK

    inc qword [usrauth_checks]

    test r13, r13
    jz .uc_invalid
    test r14d, r14d
    jz .uc_invalid                  ; A request for nothing is malformed

    mov edi, r12d
    call usrauth_subject_get
    test rax, rax
    jz .uc_invalid
    mov rbx, rax                    ; Subject

    cmp dword [rbx + usrauth_subject_t.flags], 0
    je .uc_invalid
    test dword [rbx + usrauth_subject_t.flags], USRAUTH_SUBJ_ACTIVE
    jz .uc_invalid

    ; ---- L5 mandatory: cheapest denier, and the one nothing can override ----
    mov rdi, rbx
    mov rsi, r13
    mov edx, r14d
    call usrauth_mandatory_check
    test eax, eax
    jnz .uc_deny

    ; ---- L2 integrity: no write-up ----
    mov edi, dword [rbx + usrauth_subject_t.integrity]
    mov esi, dword [r13 + usrauth_object_t.integrity]
    mov edx, r14d
    call usrauth_integrity_check
    test eax, eax
    jnz .uc_deny

    ; ---- L3 capability: authority must be HELD ----
    mov edi, r12d
    mov rsi, [r13 + usrauth_object_t.object_id]
    mov edx, dword [r13 + usrauth_object_t.object_class]
    mov ecx, r14d
    call usrauth_cap_check
    test eax, eax
    jnz .uc_deny

    ; ---- L4 policy: relations and time bounds, cached ----
    mov edi, r12d
    mov rsi, [r13 + usrauth_object_t.object_id]
    mov edx, r14d
    call usrauth_policy_check
    test eax, eax
    jnz .uc_deny

    xor r15d, r15d                  ; USRAUTH_ALLOW
    jmp .uc_audit

.uc_invalid:
    mov r15d, USRAUTH_DENY_INVALID
    jmp .uc_audit

.uc_deny:
    mov r15d, eax

.uc_audit:
    ; Record allows as well as denials: after an incident the question is what
    ; the attacker successfully reached, which a denial-only log cannot answer.
    mov edi, r12d
    xor rsi, rsi
    xor edx, edx
    test r13, r13
    jz .uc_log
    mov rsi, [r13 + usrauth_object_t.object_id]
    mov edx, dword [r13 + usrauth_object_t.object_class]

.uc_log:
    mov ecx, r14d
    mov r8d, r15d
    call usrauth_audit_record

    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_check_token
;
; Bearer-token path: validate the token, then run the full subject decision.
;
; The token is checked FIRST so a forged or stale credential never causes a
; subject lookup, and its caveats are intersected with the subject's authority
; rather than substituted for it. A valid token can only ever NARROW what the
; subject could already do — it is not an alternative grant path.
;
; Inputs:
;   RDI = Pointer to a usrauth_token_t
;   RSI = Pointer to a usrauth_object_t
;   EDX = Requested verb bitmask
;
; Returns:
;   EAX = USRAUTH_ALLOW, or a USRAUTH_DENY_* code
; -----------------------------------------------------------------------------
align 32
usrauth_check_token:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Token
    mov r12, rsi                    ; Object
    mov r13d, edx                   ; Verbs

    test rbx, rbx
    jz .ut_invalid
    test r12, r12
    jz .ut_invalid

    ; ---- L1: authenticity, epoch freshness, caveats ----
    mov rdi, rbx
    mov rsi, [r12 + usrauth_object_t.object_id]
    mov edx, dword [r12 + usrauth_object_t.object_class]
    mov ecx, r13d
    call usrauth_token_verify
    test eax, eax
    jnz .ut_return                  ; Token itself failed: stop

    ; ---- Then the full subject decision. Intersection, not substitution ----
    mov edi, dword [rbx + usrauth_token_t.subject_handle]
    mov rsi, r12
    mov edx, r13d
    call usrauth_check
    jmp .ut_return

.ut_invalid:
    mov eax, USRAUTH_DENY_INVALID

.ut_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_stats
;
; Inputs:
;   RDI = Pointer to two qwords: initialised flag, total checks
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_stats:
    mov rax, [usrauth_initialised]
    mov [rdi], rax
    mov rax, [usrauth_checks]
    mov [rdi + 8], rax
    xor eax, eax
    ret
