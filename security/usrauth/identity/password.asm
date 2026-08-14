%ifndef GUARD_SECURITY_USRAUTH_IDENTITY_PASSWORD_ASM
%define GUARD_SECURITY_USRAUTH_IDENTITY_PASSWORD_ASM
; =============================================================================
; Tattva OS — security/usrauth/identity/password.asm
; =============================================================================
; L0 — Password Authentication.
;
; Implements:
;   - Credential enrolment (`usrauth_password_enroll`)
;   - Authentication with rehash-on-verify (`usrauth_password_authenticate`)
;   - Failure throttling (`usrauth_password_throttle_check`)
;
; The hashing itself lives in crypto/upass; this is the identity-layer wrapper
; that binds a verified password to a subject and applies the policies that
; belong to authentication rather than to hashing.
;
; REHASH ON VERIFY: when a record was created under weaker parameters than
; current policy, it is recomputed during a SUCCESSFUL authentication — the one
; moment the plaintext is legitimately available. Without this step, records
; enrolled years ago keep their original cost forever, and raising the policy
; protects only new accounts.
;
; THROTTLING is per subject, not global. A global counter lets one attacker
; lock out every user by failing repeatedly against a single account.
;
; The failure path deliberately does NOT distinguish "no such credential" from
; "wrong password". Reporting the difference tells an attacker which subjects
; exist, turning a password guess into a free enumeration oracle.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_PW_MAX_CREDENTIALS   64
%define USRAUTH_PW_MAX_FAILURES      5
%define USRAUTH_PW_LOCKOUT_NS        900000000000    ; 15 minutes

struc usrauth_credential_t
    .subject_handle:    resd 1
    .active:            resd 1
    .failures:          resd 1
    .reserved:          resd 1
    .locked_until_ns:   resq 1
    .last_auth_ns:      resq 1      ; Feeds the MFA-recency attribute condition
    .record:            resb upass_record_t_size
endstruc

section .data
align 64

global usrauth_credentials
usrauth_credentials:
    times USRAUTH_PW_MAX_CREDENTIALS * usrauth_credential_t_size db 0

usrauth_cred_count:     dq 0
usrauth_pw_success:     dq 0
usrauth_pw_failure:     dq 0
usrauth_pw_lockouts:    dq 0
usrauth_pw_rehashes:    dq 0

section .text

global usrauth_password_enroll
global usrauth_password_authenticate
global usrauth_password_find
global usrauth_password_throttle_check

; -----------------------------------------------------------------------------
; usrauth_password_find
;
; Inputs:
;   EDI = Subject handle
;
; Returns:
;   RAX = Credential pointer, or 0
; -----------------------------------------------------------------------------
align 32
usrauth_password_find:
    push rbx

    mov rcx, [usrauth_cred_count]
    lea rbx, [usrauth_credentials]

.pf_loop:
    test rcx, rcx
    jz .pf_missing

    cmp dword [rbx + usrauth_credential_t.active], 0
    je .pf_next
    cmp dword [rbx + usrauth_credential_t.subject_handle], edi
    je .pf_found

.pf_next:
    add rbx, usrauth_credential_t_size
    dec rcx
    jmp .pf_loop

.pf_found:
    mov rax, rbx
    pop rbx
    ret

.pf_missing:
    xor rax, rax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_password_enroll
;
; Creates a credential for a subject.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Password pointer
;   EDX = Password length
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID on failure
; -----------------------------------------------------------------------------
align 32
usrauth_password_enroll:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi
    mov r13, rsi
    mov r14d, edx

    test r13, r13
    jz .pe_inval
    test r14d, r14d
    jz .pe_inval                    ; Empty passwords are not credentials

    ; Re-enrolment replaces rather than duplicating.
    mov edi, r12d
    call usrauth_password_find
    test rax, rax
    jnz .pe_reuse

    mov rax, [usrauth_cred_count]
    cmp rax, USRAUTH_PW_MAX_CREDENTIALS
    jae .pe_inval

    mov rbx, rax
    imul rbx, usrauth_credential_t_size
    lea rcx, [usrauth_credentials]
    add rbx, rcx
    inc qword [usrauth_cred_count]
    jmp .pe_fill

.pe_reuse:
    mov rbx, rax

.pe_fill:
    mov dword [rbx + usrauth_credential_t.subject_handle], r12d
    mov dword [rbx + usrauth_credential_t.active], 1
    mov dword [rbx + usrauth_credential_t.failures], 0
    mov qword [rbx + usrauth_credential_t.locked_until_ns], 0
    mov qword [rbx + usrauth_credential_t.last_auth_ns], 0

    mov rdi, r13
    mov esi, r14d
    lea rdx, [rbx + usrauth_credential_t.record]
    mov ecx, r12d                   ; uid bound into the derivation
    call upass_hash
    test eax, eax
    jnz .pe_inval

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.pe_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_password_throttle_check
;
; Reports whether a credential is currently locked out.
;
; Inputs:
;   RDI = Credential pointer
;
; Returns:
;   EAX = 0 when authentication may proceed, USRAUTH_DENY_EXPIRED when locked
; -----------------------------------------------------------------------------
align 32
usrauth_password_throttle_check:
    push rbx

    mov rbx, rdi
    mov rax, [rbx + usrauth_credential_t.locked_until_ns]
    test rax, rax
    jz .tc_ok

    push rax
    call mono_get_nanos
    pop rcx
    cmp rax, rcx
    jb .tc_locked

    ; Lockout has elapsed; clear it and give a fresh budget.
    mov qword [rbx + usrauth_credential_t.locked_until_ns], 0
    mov dword [rbx + usrauth_credential_t.failures], 0

.tc_ok:
    xor eax, eax
    pop rbx
    ret

.tc_locked:
    mov eax, USRAUTH_DENY_EXPIRED
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_password_authenticate
;
; Verifies a password and, on success, records the authentication time and
; upgrades the stored record if policy has moved on.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Password pointer
;   EDX = Password length
;
; Returns:
;   EAX = 0 on success
;         USRAUTH_DENY_EXPIRED when throttled
;         USRAUTH_DENY_INVALID on any authentication failure
; -----------------------------------------------------------------------------
align 32
usrauth_password_authenticate:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi
    mov r13, rsi
    mov r14d, edx

    mov edi, r12d
    call usrauth_password_find
    test rax, rax
    jz .pa_fail                     ; Same response as a wrong password
    mov rbx, rax

    mov rdi, rbx
    call usrauth_password_throttle_check
    test eax, eax
    jnz .pa_locked

    mov rdi, r13
    mov esi, r14d
    lea rdx, [rbx + usrauth_credential_t.record]
    mov ecx, r12d
    call upass_verify
    cmp eax, 1
    jne .pa_bad_password

    ; ---- Success ----
    mov dword [rbx + usrauth_credential_t.failures], 0
    mov qword [rbx + usrauth_credential_t.locked_until_ns], 0

    call mono_get_nanos
    mov [rbx + usrauth_credential_t.last_auth_ns], rax

    ; Upgrade the record while the plaintext is legitimately in hand.
    lea rdi, [rbx + usrauth_credential_t.record]
    call upass_needs_rehash
    test eax, eax
    jz .pa_ok

    mov rdi, r13
    mov esi, r14d
    lea rdx, [rbx + usrauth_credential_t.record]
    mov ecx, r12d
    call upass_hash
    inc qword [usrauth_pw_rehashes]

.pa_ok:
    inc qword [usrauth_pw_success]
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.pa_bad_password:
    inc dword [rbx + usrauth_credential_t.failures]
    cmp dword [rbx + usrauth_credential_t.failures], USRAUTH_PW_MAX_FAILURES
    jb .pa_fail

    ; Budget exhausted: lock this credential only, never globally.
    call mono_get_nanos
    ; `add r64, imm` only encodes a sign-extended imm32. The 15-minute lockout
    ; in nanoseconds exceeds that, so it must go through a register or NASM
    ; truncates it and the lockout silently becomes a fraction of a second.
    mov rcx, USRAUTH_PW_LOCKOUT_NS
    add rax, rcx
    mov [rbx + usrauth_credential_t.locked_until_ns], rax
    inc qword [usrauth_pw_lockouts]

.pa_fail:
    inc qword [usrauth_pw_failure]
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.pa_locked:
    mov eax, USRAUTH_DENY_EXPIRED
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_SECURITY_USRAUTH_IDENTITY_PASSWORD_ASM
