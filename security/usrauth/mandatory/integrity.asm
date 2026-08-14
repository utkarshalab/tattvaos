; =============================================================================
; Tattva OS — security/usrauth/mandatory/integrity.asm
; =============================================================================
; L5 — Integrity Levels (Biba / Windows Mandatory Integrity Control).
;
; Implements:
;   - Write-up prevention (`usrauth_integrity_check`)
;
; A subject may not WRITE to an object of higher integrity than itself. This is
; what stops a low-integrity process — a sandboxed renderer, a downloaded
; binary, anything untrusted — from corrupting trusted state even when the
; discretionary permissions would allow it.
;
; Windows ships this as Mandatory Integrity Control and it is the mechanism
; behind the browser sandbox: the renderer runs at Low, so it cannot write to
; anything at Medium regardless of the user's own file permissions.
;
; READS ARE UNRESTRICTED HERE, deliberately. Biba constrains INTEGRITY, which
; is about corruption and therefore about writes. Confidentiality — who may
; READ what — is the MLS layer's concern and points in the opposite direction.
; Conflating the two makes one of them useless: enforcing "no read up" here
; would duplicate MLS, while enforcing "no write down" would invert Biba.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .text

global usrauth_integrity_check

; -----------------------------------------------------------------------------
; usrauth_integrity_check
;
; Biba write-up prevention: a subject may not write to an object whose
; integrity exceeds its own.
;
; Reads are unrestricted here — Biba constrains integrity (writes), while
; confidentiality (reads) is the MLS layer's concern. Conflating them is a
; common error that makes one of the two models useless.
;
; Inputs:
;   EDI = Subject integrity level
;   ESI = Object integrity level
;   EDX = Verb bitmask
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_INTEGRITY
; -----------------------------------------------------------------------------
align 32
usrauth_integrity_check:
    ; Only mutating verbs are constrained.
    test edx, USRAUTH_VERB_WRITE | USRAUTH_VERB_APPEND | USRAUTH_VERB_CREATE | USRAUTH_VERB_DELETE | USRAUTH_VERB_ADMIN
    jz .ic_allow

    cmp edi, esi
    jb .ic_deny                     ; Subject below object: write-up refused

.ic_allow:
    xor eax, eax
    ret

.ic_deny:
    mov eax, USRAUTH_DENY_INTEGRITY
    ret

