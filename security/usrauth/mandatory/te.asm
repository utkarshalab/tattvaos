; =============================================================================
; Tattva OS — security/usrauth/mandatory.asm
; =============================================================================
; L5 — Mandatory Access Control. This layer can ONLY deny.
;
; Implements:
;   - Type enforcement rules (`usrauth_te_add`, `usrauth_te_check`)
;   - Bell-LaPadula MLS dominance (`usrauth_mls_dominates`, `usrauth_mls_check`)
;   - Combined mandatory verdict (`usrauth_mandatory_check`)
;
; This is the "even root cannot" layer. Nothing below it — not a capability,
; not an ACL, not an owner — can grant what type enforcement withholds. That
; asymmetry is the entire point: discretionary controls protect users from
; accidents, mandatory controls protect the system from users.
;
; TYPE ENFORCEMENT: absence is denial. There is no deny rule because there is
; nothing to override; the default answer is already no. A rule set that
; needed explicit denials would be one where the default was allow, which is
; how policy gaps become privilege escalations.
;
; MLS (Bell-LaPadula), for confidentiality:
;   - No READ UP    — a subject may not read above its clearance
;   - No WRITE DOWN — a subject may not write below its clearance, because
;                     that would launder classified data into a lower level
;
; Write-down is the rule people find surprising and remove; removing it makes
; the model decorative, since any cleared subject could then copy secrets
; downward at will.
;
; MLS constrains confidentiality; Biba integrity (in subject.asm) constrains
; corruption. They point in opposite directions and are deliberately separate.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .data
align 64

global usrauth_te_rules
usrauth_te_rules:
    times USRAUTH_MAX_TE_RULES * usrauth_te_rule_t_size db 0

usrauth_te_count:        dq 0
usrauth_te_enforcing:    dq 1        ; 0 = permissive (log only), 1 = enforcing
usrauth_mls_enabled:     dq 0        ; MLS off unless a policy turns it on
usrauth_te_denials:      dq 0
usrauth_mls_denials:     dq 0

section .text

global usrauth_te_add
global usrauth_te_check
global usrauth_te_set_enforcing
global usrauth_mandatory_check

; -----------------------------------------------------------------------------
; usrauth_te_set_enforcing
;
; Permissive mode evaluates and records denials without applying them, which is
; how a policy is developed without locking the system out. It must never be
; the default — a policy that has only ever run permissive has never been
; tested.
;
; Inputs:
;   EDI = 0 for permissive, non-zero for enforcing
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_te_set_enforcing:
    xor eax, eax
    test edi, edi
    setnz al
    mov [usrauth_te_enforcing], rax
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usrauth_mls_enable
;
; Inputs:
;   EDI = 0 to disable, non-zero to enable
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_mandatory_check:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Subject
    mov r12, rsi                    ; Object
    mov r13d, edx                   ; Verbs

    test rbx, rbx
    jz .mk_inval
    test r12, r12
    jz .mk_inval

    mov edi, dword [rbx + usrauth_subject_t.type_id]
    mov esi, dword [r12 + usrauth_object_t.type_id]
    mov edx, dword [r12 + usrauth_object_t.object_class]
    mov ecx, r13d
    call usrauth_te_check
    test eax, eax
    jnz .mk_return                  ; Type enforcement denied: stop here

    lea rdi, [rbx + usrauth_subject_t.label]
    lea rsi, [r12 + usrauth_object_t.label]
    mov edx, r13d
    call usrauth_mls_check

.mk_return:
    pop r13
    pop r12
    pop rbx
    ret

.mk_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r13
    pop r12
    pop rbx
    ret
