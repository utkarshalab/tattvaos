; =============================================================================
; Tattva OS — security/usrauth/token/token.asm
; =============================================================================
; L1 — Attenuable Bearer Tokens.
;
; Implements:
;   - Issue, verify (`usrauth_token_issue`, `usrauth_token_verify`)
;   - Offline attenuation (`usrauth_token_attenuate`)
;   - Deterministic tag computation (`usrauth_token_tag`)
;
; Tokens are authenticated with HMAC-SHA256, not a public-key signature. That
; is a deliberate choice, not a shortcut: inside a single kernel the issuer and
; the verifier are the same authority, so an asymmetric signature would add
; cost and a large amount of field arithmetic while protecting against nothing
; in this threat model. Asymmetric signing becomes necessary only when a
; DIFFERENT party must verify without the minting key — cross-node federation.
;
; ATTENUATION IS OFFLINE. A holder narrows a token by appending a caveat and
; re-tagging with the same key. Because caveats can only ever be ADDED, and
; every caveat is a restriction, the result is provably no broader than the
; original. This is what allows delegation with no round trip to the issuer.
;
; REVOCATION is by epoch. A token records the subject epoch it was minted
; under; bumping the subject's epoch invalidates every outstanding token at
; once. This closes the hole that makes stateless bearer tokens hard to revoke
; in practice.
;
; The tag covers the caveat COUNT as well as the caveats. Without that, an
; attacker could truncate the caveat list — dropping restrictions — and the
; remaining bytes would still authenticate.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .data
align 64

; Token signing key. Derived at boot from the CSPRNG, or unsealed from the TPM
; when device binding is in force. It must never leave this module.
global usrauth_token_key
usrauth_token_key:       times 32 db 0
usrauth_token_key_set:   dq 0

usrauth_tokens_issued:   dq 0
usrauth_tokens_rejected: dq 0

section .text

global usrauth_token_init
global usrauth_token_issue
global usrauth_token_verify
global usrauth_token_attenuate
global usrauth_token_tag

; -----------------------------------------------------------------------------
; usrauth_token_init
;
; Installs the signing key.
;
; Inputs:
;   RDI = Pointer to 32 key bytes, or 0 to generate from the CSPRNG
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_token_init:
    push rbx

    test rdi, rdi
    jz .ti_generate

    mov rsi, rdi
    lea rdi, [usrauth_token_key]
    mov rcx, 4
    rep movsq
    jmp .ti_done

.ti_generate:
    lea rdi, [usrauth_token_key]
    mov rsi, 32
    call urand_get_bytes

.ti_done:
    mov qword [usrauth_token_key_set], 1
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_token_tag
;
; Computes the authentication tag over everything preceding the tag field.
;
; Covering caveat_count is essential — see the truncation note in the header.
;
; Inputs:
;   RDI = Pointer to a usrauth_token_t
;   RSI = Pointer to a 32-byte tag buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_token_tag:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    lea rdi, [usrauth_token_key]
    mov rsi, 32
    mov rdx, rbx
    mov rcx, usrauth_token_t.tag     ; Everything up to, but not including, tag
    mov r8, r12
    call hmac_sha256

    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_token_issue
;
; Mints a token bound to a subject and its current epoch.
;
; Inputs:
;   RDI = Pointer to a usrauth_token_t to fill
;   ESI = Subject handle
;   RDX = Lifetime in ns, or 0 for no expiry caveat
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID on a bad subject
; -----------------------------------------------------------------------------
align 32
usrauth_token_issue:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Token
    mov r12d, esi                   ; Subject handle
    mov r13, rdx                    ; Lifetime

    test rbx, rbx
    jz .tk_inval
    cmp qword [usrauth_token_key_set], 0
    je .tk_inval

    mov edi, r12d
    call usrauth_subject_get
    test rax, rax
    jz .tk_inval
    mov r14, rax

    ; Zero first: reserved bytes feed the tag and must be deterministic.
    mov rdi, rbx
    mov rcx, usrauth_token_t_size
    xor al, al
    rep stosb

    mov dword [rbx + usrauth_token_t.magic], USRAUTH_TOKEN_MAGIC
    mov dword [rbx + usrauth_token_t.version], USRAUTH_VERSION
    mov dword [rbx + usrauth_token_t.subject_handle], r12d
    mov dword [rbx + usrauth_token_t.caveat_count], 0

    mov rax, [r14 + usrauth_subject_t.token_epoch]
    mov [rbx + usrauth_token_t.epoch], rax

    call mono_get_nanos
    mov [rbx + usrauth_token_t.issued_ns], rax

    ; A lifetime becomes an expiry caveat rather than a bare field, so
    ; attenuation and expiry share one evaluation path.
    test r13, r13
    jz .tk_sign

    add rax, r13                    ; Absolute deadline
    lea rdi, [rbx + usrauth_token_t.caveats]
    mov dword [rdi + usrauth_caveat_t.kind], USRAUTH_CAVEAT_EXPIRES
    mov [rdi + usrauth_caveat_t.arg_a], rax
    mov dword [rbx + usrauth_token_t.caveat_count], 1

.tk_sign:
    mov rdi, rbx
    lea rsi, [rbx + usrauth_token_t.tag]
    call usrauth_token_tag

    inc qword [usrauth_tokens_issued]
    xor eax, eax
    jmp .tk_return

.tk_inval:
    mov eax, USRAUTH_DENY_INVALID

.tk_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_token_attenuate
;
; Appends a restricting caveat and re-tags.
;
; Only ADDS caveats. Since every caveat narrows, the result cannot be broader
; than the input — which is what makes offline delegation safe.
;
; Inputs:
;   RDI = Pointer to a usrauth_token_t (modified in place)
;   ESI = Caveat kind
;   RDX = arg_a
;   RCX = arg_b
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID when full or malformed
; -----------------------------------------------------------------------------
align 32
usrauth_token_attenuate:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx

    test rbx, rbx
    jz .ta_inval
    cmp dword [rbx + usrauth_token_t.magic], USRAUTH_TOKEN_MAGIC
    jne .ta_inval

    mov ecx, dword [rbx + usrauth_token_t.caveat_count]
    cmp ecx, USRAUTH_TOKEN_MAX_CAVEATS
    jae .ta_inval

    mov rax, rcx
    imul rax, usrauth_caveat_t_size
    lea rdi, [rbx + usrauth_token_t.caveats]
    add rdi, rax

    mov dword [rdi + usrauth_caveat_t.kind], r12d
    mov dword [rdi + usrauth_caveat_t.reserved], 0
    mov [rdi + usrauth_caveat_t.arg_a], r13
    mov [rdi + usrauth_caveat_t.arg_b], r14

    inc dword [rbx + usrauth_token_t.caveat_count]

    ; Re-tag: the caveat list and count are both covered.
    mov rdi, rbx
    lea rsi, [rbx + usrauth_token_t.tag]
    call usrauth_token_tag

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.ta_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_token_verify
;
; Full token validation: tag, epoch freshness, revocation, then caveats.
;
; Order matters. The tag is checked FIRST, because every other field is
; attacker-controlled until authenticity is established. Reading the epoch or
; caveats from an unauthenticated token and acting on them is the classic
; parse-before-verify mistake.
;
; Inputs:
;   RDI = Pointer to a usrauth_token_t
;   RSI = Object id
;   EDX = Object class
;   ECX = Requested verbs
;
; Returns:
;   EAX = USRAUTH_ALLOW, or a USRAUTH_DENY_* code
; -----------------------------------------------------------------------------
align 32
usrauth_token_verify:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

    mov rbx, rdi                    ; Token
    mov r12, rsi                    ; Object
    mov r13d, edx                   ; Class
    mov r14d, ecx                   ; Verbs

    test rbx, rbx
    jz .tv_inval
    cmp qword [usrauth_token_key_set], 0
    je .tv_inval

    cmp dword [rbx + usrauth_token_t.magic], USRAUTH_TOKEN_MAGIC
    jne .tv_inval
    cmp dword [rbx + usrauth_token_t.version], USRAUTH_VERSION
    ja .tv_inval

    mov eax, dword [rbx + usrauth_token_t.caveat_count]
    cmp eax, USRAUTH_TOKEN_MAX_CAVEATS
    ja .tv_inval                    ; Implausible count: reject before hashing

    ; ---- 1. Authenticity, before trusting any other field ----
    mov rdi, rbx
    mov rsi, rsp
    call usrauth_token_tag

    lea rdi, [rbx + usrauth_token_t.tag]
    mov rsi, rsp
    mov rdx, 32
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .tv_badtag

    ; ---- 2. Epoch freshness: revocation check ----
    mov edi, dword [rbx + usrauth_token_t.subject_handle]
    call usrauth_subject_get
    test rax, rax
    jz .tv_revoked
    mov r15, rax

    mov rax, [r15 + usrauth_subject_t.token_epoch]
    cmp [rbx + usrauth_token_t.epoch], rax
    jne .tv_revoked                 ; Subject epoch moved on: token is stale

    ; ---- 3. Individual revocation ----
    ; The epoch covers every token a subject holds. This narrower check exists
    ; for the case where one delegated token must die while its siblings live,
    ; so it is consulted only after the cheap epoch test has already passed.
    mov edi, dword [rbx + usrauth_token_t.subject_handle]
    mov rsi, [rbx + usrauth_token_t.issued_ns]
    call usrauth_revoke_check
    test eax, eax
    jnz .tv_fail

    ; ---- 4. Caveats ----
    call mono_get_nanos
    mov r8, rax

    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov ecx, r14d
    call usrauth_token_check_caveats
    test eax, eax
    jnz .tv_fail

    xor eax, eax
    jmp .tv_return

.tv_badtag:
    ; Distinct from DENY_CAVEAT on purpose. A caveat that fails is the system
    ; working as intended; a tag that fails to authenticate is someone trying
    ; to forge authority, and the audit trail must be able to tell them apart.
    mov eax, USRAUTH_DENY_FORGED
    jmp .tv_fail

.tv_revoked:
    mov eax, USRAUTH_DENY_REVOKED
    jmp .tv_fail

.tv_inval:
    mov eax, USRAUTH_DENY_INVALID

.tv_fail:
    inc qword [usrauth_tokens_rejected]

.tv_return:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
