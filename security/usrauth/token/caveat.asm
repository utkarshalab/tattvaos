; =============================================================================
; Tattva OS — security/usrauth/token/caveat.asm
; =============================================================================
; L1 — Caveat Evaluation.
;
; Implements:
;   - Evaluation of every caveat carried by a token
;     (`usrauth_token_check_caveats`)
;
; A caveat is a RESTRICTION carried inside the token itself. Because caveats
; can only ever be appended — never removed, since the authentication tag
; covers both the caveat list and its count — a token can be narrowed by
; anyone holding it without contacting the issuer. That is what makes offline
; delegation safe: the result is provably no broader than what was handed over.
;
; ALL caveats must hold. They are conjunctive by construction. A token whose
; caveats were evaluated disjunctively would grow BROADER with every added
; restriction, which is exactly backwards.
;
; AN UNRECOGNISED CAVEAT KIND MUST DENY. This is the opposite of the
; unknown-field tolerance UBXP applies to data, and the asymmetry is
; deliberate: skipping a data field you do not understand loses information,
; while skipping a RESTRICTION you do not understand grants access the issuer
; explicitly withheld. An older verifier must refuse a token it cannot fully
; interpret rather than honour only the parts it happens to recognise.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .text

global usrauth_token_check_caveats

; -----------------------------------------------------------------------------
; usrauth_token_check_caveats
;
; Evaluates every caveat against a proposed access. ALL must hold.
;
; Inputs:
;   RDI = Pointer to a usrauth_token_t
;   RSI = Object id
;   EDX = Object class
;   ECX = Requested verbs
;   R8  = Current time in ns
;
; Returns:
;   EAX = USRAUTH_ALLOW, USRAUTH_DENY_CAVEAT or USRAUTH_DENY_EXPIRED
; -----------------------------------------------------------------------------
align 32
usrauth_token_check_caveats:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Token
    mov r12, rsi                    ; Object
    mov r13d, edx                   ; Class
    mov r14d, ecx                   ; Verbs
    mov r15, r8                     ; Now

    mov r9d, dword [rbx + usrauth_token_t.caveat_count]
    xor r10, r10

.cv_loop:
    cmp r10d, r9d
    jae .cv_allow

    mov rax, r10
    imul rax, usrauth_caveat_t_size
    lea rdi, [rbx + usrauth_token_t.caveats]
    add rdi, rax

    mov ecx, dword [rdi + usrauth_caveat_t.kind]

    cmp ecx, USRAUTH_CAVEAT_EXPIRES
    je .cv_expires
    cmp ecx, USRAUTH_CAVEAT_VERB_MASK
    je .cv_verbs
    cmp ecx, USRAUTH_CAVEAT_OBJECT
    je .cv_object
    cmp ecx, USRAUTH_CAVEAT_CLASS
    je .cv_class
    cmp ecx, USRAUTH_CAVEAT_SUBJECT
    je .cv_next                     ; Checked by the caller against the handle

    ; An unrecognised caveat must DENY, never be skipped. Ignoring unknown
    ; restrictions would let an old verifier honour a token it cannot fully
    ; understand — exactly backwards from unknown-field tolerance in data.
    jmp .cv_deny

.cv_expires:
    mov rax, [rdi + usrauth_caveat_t.arg_a]
    test rax, rax
    jz .cv_next
    cmp r15, rax
    jae .cv_expired
    jmp .cv_next

.cv_verbs:
    mov eax, dword [rdi + usrauth_caveat_t.arg_a]
    mov ecx, r14d
    and ecx, eax
    cmp ecx, r14d
    jne .cv_deny                    ; Requesting outside the permitted mask
    jmp .cv_next

.cv_object:
    mov rax, [rdi + usrauth_caveat_t.arg_a]
    cmp r12, rax
    jne .cv_deny
    jmp .cv_next

.cv_class:
    mov eax, dword [rdi + usrauth_caveat_t.arg_a]
    cmp r13d, eax
    jne .cv_deny

.cv_next:
    inc r10
    jmp .cv_loop

.cv_allow:
    xor eax, eax
    jmp .cv_return

.cv_expired:
    mov eax, USRAUTH_DENY_EXPIRED
    jmp .cv_return

.cv_deny:
    mov eax, USRAUTH_DENY_CAVEAT

.cv_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
