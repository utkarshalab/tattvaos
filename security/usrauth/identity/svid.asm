; =============================================================================
; Tattva OS — security/usrauth/identity/svid.asm
; =============================================================================
; L0 — Workload Identity Document (SPIFFE-shaped SVID).
;
; Implements:
;   - Document issue from attested state (`usrauth_svid_issue`)
;   - Validation including expiry (`usrauth_svid_validate`)
;   - Binding a document to a subject (`usrauth_svid_bind`)
;
; A workload identity says WHAT is running, not WHO is operating it. It is
; derived from measured boot state rather than from a stored secret, so there
; is nothing to steal: an attacker who copies the document to another machine
; finds it fails validation there, because the attestation it is bound to no
; longer holds.
;
; Documents are SHORT LIVED by construction. The Kerberos lesson applies —
; a long-lived credential is a long-lived liability, and a workload can always
; re-derive from attestation as often as needed since the source is local
; hardware state rather than a remote authority.
;
; The trust domain separates otherwise-identical workloads across deployments,
; so a document minted in staging cannot be presented in production even when
; the measurements match.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_SVID_MAGIC           0x53564944      ; "SVID"
%define USRAUTH_SVID_ID_BYTES        32
%define USRAUTH_SVID_DOMAIN_BYTES    32
%define USRAUTH_SVID_TAG_BYTES       32
%define USRAUTH_SVID_DEFAULT_TTL     3600000000000   ; 1 hour in ns

struc usrauth_svid_t
    .magic:             resd 1      ; USRAUTH_SVID_MAGIC
    .version:           resd 1
    .workload_id:       resb USRAUTH_SVID_ID_BYTES      ; From attestation
    .trust_domain:      resb USRAUTH_SVID_DOMAIN_BYTES  ; Deployment separator
    .issued_ns:         resq 1
    .expires_ns:        resq 1
    .subject_handle:    resd 1      ; Bound subject, or USRAUTH_INVALID_HANDLE
    .reserved:          resd 1
    .tag:               resb USRAUTH_SVID_TAG_BYTES     ; HMAC over the above
endstruc

section .data
align 64

usrauth_svid_domain:    times USRAUTH_SVID_DOMAIN_BYTES db 0
usrauth_svid_domain_set: dq 0
usrauth_svid_issued:    dq 0
usrauth_svid_rejected:  dq 0

section .text

global usrauth_svid_set_domain
global usrauth_svid_issue
global usrauth_svid_validate
global usrauth_svid_bind
global usrauth_svid_tag

; -----------------------------------------------------------------------------
; usrauth_svid_set_domain
;
; Installs the trust domain identifier for this deployment.
;
; Inputs:
;   RDI = Pointer to 32 domain bytes
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID on a null argument
; -----------------------------------------------------------------------------
align 32
usrauth_svid_set_domain:
    test rdi, rdi
    jz .sd_inval
    mov rsi, rdi
    lea rdi, [usrauth_svid_domain]
    mov rcx, 4
    rep movsq
    mov qword [usrauth_svid_domain_set], 1
    xor eax, eax
    ret
.sd_inval:
    mov eax, USRAUTH_DENY_INVALID
    ret

; -----------------------------------------------------------------------------
; usrauth_svid_tag
;
; Authenticates the document with the token key, over everything preceding the
; tag field.
;
; Inputs:
;   RDI = Pointer to a usrauth_svid_t
;   RSI = Pointer to a 32-byte tag buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_svid_tag:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    lea rdi, [usrauth_token_key]
    mov rsi, 32
    mov rdx, rbx
    mov rcx, usrauth_svid_t.tag     ; Everything up to the tag itself
    mov r8, r12
    call hmac_sha256

    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_svid_issue
;
; Mints a document from current attested state.
;
; Fails when attestation fails. That is the point — an identity asserting what
; the workload is must not be issuable by a workload that cannot prove it.
;
; Inputs:
;   RDI = Pointer to a usrauth_svid_t to fill
;   RSI = Lifetime in ns, or 0 for the default
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_MANDATORY when attestation fails
; -----------------------------------------------------------------------------
align 32
usrauth_svid_issue:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    test rbx, rbx
    jz .si_inval
    cmp qword [usrauth_svid_domain_set], 0
    je .si_inval                    ; Without a domain the document is ambiguous

    ; Zero first: reserved bytes feed the tag and must be deterministic.
    mov rdi, rbx
    mov rcx, usrauth_svid_t_size
    xor al, al
    rep stosb

    mov dword [rbx + usrauth_svid_t.magic], USRAUTH_SVID_MAGIC
    mov dword [rbx + usrauth_svid_t.version], USRAUTH_VERSION
    mov dword [rbx + usrauth_svid_t.subject_handle], USRAUTH_INVALID_HANDLE

    ; Identity comes from measured state, not from a stored secret.
    lea rdi, [rbx + usrauth_svid_t.workload_id]
    call usrauth_attest_derive_id
    test eax, eax
    jnz .si_fail

    lea rdi, [rbx + usrauth_svid_t.trust_domain]
    lea rsi, [usrauth_svid_domain]
    mov rcx, 4
    rep movsq

    call mono_get_nanos
    mov [rbx + usrauth_svid_t.issued_ns], rax

    test r12, r12
    jnz .si_ttl
    mov r12, USRAUTH_SVID_DEFAULT_TTL

.si_ttl:
    add rax, r12
    mov [rbx + usrauth_svid_t.expires_ns], rax

    mov rdi, rbx
    lea rsi, [rbx + usrauth_svid_t.tag]
    call usrauth_svid_tag

    inc qword [usrauth_svid_issued]
    xor eax, eax
    jmp .si_return

.si_fail:
    inc qword [usrauth_svid_rejected]
    mov eax, USRAUTH_DENY_MANDATORY
    jmp .si_return

.si_inval:
    mov eax, USRAUTH_DENY_INVALID

.si_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_svid_validate
;
; Checks authenticity, expiry, trust domain, and that the attested state still
; matches the identity the document claims.
;
; The tag is verified FIRST: every other field is attacker-controlled until
; authenticity is established.
;
; Inputs:
;   RDI = Pointer to a usrauth_svid_t
;
; Returns:
;   EAX = USRAUTH_ALLOW, or a USRAUTH_DENY_* code
; -----------------------------------------------------------------------------
align 32
usrauth_svid_validate:
    push rbx
    push r12
    push r13
    sub rsp, 80

    mov rbx, rdi

    test rbx, rbx
    jz .sv_inval
    cmp dword [rbx + usrauth_svid_t.magic], USRAUTH_SVID_MAGIC
    jne .sv_inval
    cmp dword [rbx + usrauth_svid_t.version], USRAUTH_VERSION
    ja .sv_inval

    ; ---- 1. Authenticity ----
    mov rdi, rbx
    mov rsi, rsp
    call usrauth_svid_tag

    lea rdi, [rbx + usrauth_svid_t.tag]
    mov rsi, rsp
    mov rdx, USRAUTH_SVID_TAG_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .sv_reject

    ; ---- 2. Expiry ----
    call mono_get_nanos
    mov rcx, [rbx + usrauth_svid_t.expires_ns]
    test rcx, rcx
    jz .sv_domain                   ; No expiry set
    cmp rax, rcx
    jae .sv_expired

.sv_domain:
    ; ---- 3. Trust domain must match this deployment ----
    lea rdi, [rbx + usrauth_svid_t.trust_domain]
    lea rsi, [usrauth_svid_domain]
    mov rdx, USRAUTH_SVID_DOMAIN_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .sv_reject

    ; ---- 4. Attested state must still produce this identity ----
    lea rdi, [rsp + 40]
    call usrauth_attest_derive_id
    test eax, eax
    jnz .sv_reject                  ; Platform no longer attests

    lea rdi, [rbx + usrauth_svid_t.workload_id]
    lea rsi, [rsp + 40]
    mov rdx, USRAUTH_SVID_ID_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .sv_reject                  ; Different workload than claimed

    xor eax, eax
    jmp .sv_return

.sv_expired:
    inc qword [usrauth_svid_rejected]
    mov eax, USRAUTH_DENY_EXPIRED
    jmp .sv_return

.sv_reject:
    inc qword [usrauth_svid_rejected]
    mov eax, USRAUTH_DENY_REVOKED
    jmp .sv_return

.sv_inval:
    mov eax, USRAUTH_DENY_INVALID

.sv_return:
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_svid_bind
;
; Associates a validated document with a subject, marking the subject attested.
;
; Validation happens before binding, so an unverified document can never set
; the ATTESTED flag that policy conditions rely on.
;
; Inputs:
;   RDI = Pointer to a usrauth_svid_t
;   ESI = Subject handle
;
; Returns:
;   EAX = USRAUTH_ALLOW, or a USRAUTH_DENY_* code
; -----------------------------------------------------------------------------
align 32
usrauth_svid_bind:
    push rbx
    push r12

    mov rbx, rdi
    mov r12d, esi

    call usrauth_svid_validate
    test eax, eax
    jnz .sb_return

    mov edi, r12d
    call usrauth_subject_get
    test rax, rax
    jz .sb_inval

    or dword [rax + usrauth_subject_t.flags], USRAUTH_SUBJ_ATTESTED
    mov dword [rbx + usrauth_svid_t.subject_handle], r12d

    ; Re-tag: the bound handle is covered by the authentication tag.
    mov rdi, rbx
    lea rsi, [rbx + usrauth_svid_t.tag]
    call usrauth_svid_tag

    xor eax, eax
    jmp .sb_return

.sb_inval:
    mov eax, USRAUTH_DENY_INVALID

.sb_return:
    pop r12
    pop rbx
    ret
