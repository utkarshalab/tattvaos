; =============================================================================
; Tattva OS — security/usrauth/capability/restrict.asm
; =============================================================================
; L3 — Irreversible Self-Restriction (pledge / unveil).
;
; Implements:
;   - Voluntary, permanent narrowing of a subject's own authority
;     (`usrauth_subject_restrict`)
;
; A process that has finished its privileged setup should be able to discard
; the authority it no longer needs, so that a later compromise inherits less.
; OpenBSD's pledge established the pattern: the program itself declares what it
; will still require, and everything else becomes permanently unavailable.
;
; THE RESTRICTION IS IRREVERSIBLE. There is deliberately no inverse operation.
; Authority that can be reclaimed was never really surrendered — a compromised
; subject would simply reclaim it, and the whole exercise would amount to a
; comment. Reversibility is the difference between a security boundary and a
; suggestion.
;
; Restriction also bumps the subject's token epoch: outstanding tokens were
; minted against authority the subject no longer holds, so they must stop
; validating immediately rather than linger until their own expiry.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .text

global usrauth_subject_restrict

; -----------------------------------------------------------------------------
; usrauth_subject_restrict
;
; Irreversibly narrows a subject's authority, in the spirit of pledge/unveil.
;
; Every held capability is intersected with the supplied mask and the subject
; is marked restricted. There is deliberately no inverse operation: authority
; that can be reclaimed was never really surrendered, and a compromised
; subject would simply reclaim it.
;
; Inputs:
;   EDI = Subject handle
;   ESI = Verb mask to retain
;
; Returns:
;   EAX = Capabilities remaining, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_subject_restrict:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, esi
    and r12d, USRAUTH_VERB_MASK

    call usrauth_subject_get
    test rax, rax
    jz .sr_inval
    mov rbx, rax

    mov r13d, dword [rbx + usrauth_subject_t.cap_count]
    xor rcx, rcx
    xor r14d, r14d                  ; Capabilities still conferring something

.sr_loop:
    cmp ecx, r13d
    jae .sr_done

    mov rax, rcx
    imul rax, usrauth_cap_t_size
    lea rdi, [rbx + usrauth_subject_t.caps]
    add rdi, rax

    mov edx, dword [rdi + usrauth_cap_t.rights]
    and edx, r12d
    mov dword [rdi + usrauth_cap_t.rights], edx

    test edx, edx
    jz .sr_next
    inc r14d

.sr_next:
    inc ecx
    jmp .sr_loop

.sr_done:
    or dword [rbx + usrauth_subject_t.flags], USRAUTH_SUBJ_RESTRICTED

    ; Restriction invalidates outstanding tokens: they were minted against
    ; authority the subject no longer has.
    inc qword [rbx + usrauth_subject_t.token_epoch]

    mov eax, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.sr_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
