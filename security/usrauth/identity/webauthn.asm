%ifndef GUARD_SECURITY_USRAUTH_IDENTITY_WEBAUTHN_ASM
%define GUARD_SECURITY_USRAUTH_IDENTITY_WEBAUTHN_ASM
; =============================================================================
; Tattva OS — security/usrauth/identity/webauthn.asm
; =============================================================================
; L0 — FIDO2 / WebAuthn Assertion Verification.
;
; Implements:
;   - Credential registration (`usrauth_webauthn_register`)
;   - Assertion verification (`usrauth_webauthn_verify`)
;   - Signature counter clone detection (`usrauth_webauthn_check_counter`)
;
; Both algorithms verify for real: EdDSA via RFC 8032 Ed25519, ES256 via ECDSA
; over NIST P-256. ES256 signatures arrive DER-encoded, as authenticators emit
; them, and the decoder is strict — every alternative encoding it accepted
; would be a second valid byte string for the same signature.
;
; WHERE THE SECURITY ACTUALLY COMES FROM
; --------------------------------------
; Phishing resistance is NOT from the signature. It is from BINDING: the
; authenticator signs over an RP ID hash it computed itself from the origin it
; was invoked on. A credential registered for one relying party produces a
; signature a different relying party cannot accept, so a user tricked into
; visiting a lookalike site simply cannot produce a usable assertion. Password
; entropy has no equivalent property.
;
; Three checks matter and are all implemented here:
;   1. RP ID hash must match the registered relying party
;   2. User Present flag must be set — proves a human touched the device
;   3. Signature counter must INCREASE — a counter that stalls or goes
;      backwards indicates a cloned authenticator
;
; The counter check is the one most often skipped. Without it, an extracted
; credential can be replayed indefinitely from a copy.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_WA_MAX_CREDENTIALS   32
%define USRAUTH_WA_CRED_ID_BYTES     32
%define USRAUTH_WA_PUBKEY_BYTES      64      ; Ed25519 32, ES256 x||y 64
%define USRAUTH_WA_RPID_BYTES        32      ; SHA-256 of the RP ID

; Longest authenticator data an assertion may carry. The signed message is
; assembled in a fixed buffer, so this bound is what keeps that assembly from
; running off the end; anything larger is refused rather than truncated.
; Truncating would verify a signature over a PREFIX of the real message, which
; an attacker chooses.
%define USRAUTH_WA_MAX_AUTHDATA      1024

; COSE algorithm identifiers.
%define USRAUTH_WA_ALG_ES256        -7
%define USRAUTH_WA_ALG_EDDSA        -8

; Authenticator data flag bits.
%define USRAUTH_WA_FLAG_UP           0x01    ; User Present
%define USRAUTH_WA_FLAG_UV           0x04    ; User Verified (PIN/biometric)
%define USRAUTH_WA_FLAG_AT           0x40    ; Attested credential data
%define USRAUTH_WA_FLAG_ED           0x80    ; Extension data

struc usrauth_wa_cred_t
    .subject_handle:    resd 1
    .algorithm:         resd 1      ; USRAUTH_WA_ALG_*
    .sign_count:        resd 1      ; Last accepted counter value
    .active:            resd 1
    .cred_id:           resb USRAUTH_WA_CRED_ID_BYTES
    .pubkey:            resb USRAUTH_WA_PUBKEY_BYTES
    .rpid_hash:         resb USRAUTH_WA_RPID_BYTES
endstruc

; Authenticator data prefix, as produced by the device.
struc usrauth_wa_authdata_t
    .rpid_hash:         resb 32
    .flags:             resb 1
    .sign_count:        resb 4      ; BIG-endian on the wire
endstruc

section .data
align 64

global usrauth_wa_credentials
usrauth_wa_credentials:
    times USRAUTH_WA_MAX_CREDENTIALS * usrauth_wa_cred_t_size db 0

usrauth_wa_count:       dq 0
usrauth_wa_verified:    dq 0
usrauth_wa_rejected:    dq 0
usrauth_wa_clones:      dq 0

section .text

global usrauth_webauthn_register
global usrauth_webauthn_verify
global usrauth_webauthn_find
global usrauth_webauthn_check_counter

; -----------------------------------------------------------------------------
; usrauth_webauthn_find
;
; Inputs:
;   RDI = Credential id pointer (32 bytes)
;
; Returns:
;   RAX = Credential pointer, or 0
; -----------------------------------------------------------------------------
align 32
usrauth_webauthn_find:
    push rbx
    push r12
    push r13

    mov r13, rdi
    mov r12, [usrauth_wa_count]
    lea rbx, [usrauth_wa_credentials]

.wf_loop:
    test r12, r12
    jz .wf_missing

    cmp dword [rbx + usrauth_wa_cred_t.active], 0
    je .wf_next

    lea rdi, [rbx + usrauth_wa_cred_t.cred_id]
    mov rsi, r13
    mov rdx, USRAUTH_WA_CRED_ID_BYTES
    push rbx
    push r12
    call ucrypt_ct_memcmp
    pop r12
    pop rbx
    test rax, rax
    jz .wf_found

.wf_next:
    add rbx, usrauth_wa_cred_t_size
    dec r12
    jmp .wf_loop

.wf_found:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

.wf_missing:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_webauthn_register
;
; Records a credential produced during enrolment.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Credential id (32 bytes)
;   RDX = Public key
;   ECX = COSE algorithm identifier
;   R8  = RP ID hash (32 bytes)
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID on failure
; -----------------------------------------------------------------------------
align 32
usrauth_webauthn_register:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi
    mov r13, rsi
    mov r14, rdx
    mov r15, r8
    mov ebx, ecx                    ; Algorithm

    test r13, r13
    jz .wr_inval
    test r14, r14
    jz .wr_inval
    test r15, r15
    jz .wr_inval

    ; Only the two algorithms WebAuthn actually mandates.
    cmp ebx, USRAUTH_WA_ALG_ES256
    je .wr_alg_ok
    cmp ebx, USRAUTH_WA_ALG_EDDSA
    je .wr_alg_ok
    jmp .wr_inval

.wr_alg_ok:
    mov rax, [usrauth_wa_count]
    cmp rax, USRAUTH_WA_MAX_CREDENTIALS
    jae .wr_inval

    mov rcx, rax
    imul rcx, usrauth_wa_cred_t_size
    lea rax, [usrauth_wa_credentials]
    add rax, rcx
    push rax                        ; Slot

    mov dword [rax + usrauth_wa_cred_t.subject_handle], r12d
    mov dword [rax + usrauth_wa_cred_t.algorithm], ebx
    mov dword [rax + usrauth_wa_cred_t.sign_count], 0
    mov dword [rax + usrauth_wa_cred_t.active], 1

    lea rdi, [rax + usrauth_wa_cred_t.cred_id]
    mov rsi, r13
    mov rcx, 4
    rep movsq

    pop rax
    push rax
    lea rdi, [rax + usrauth_wa_cred_t.pubkey]
    mov rsi, r14
    mov rcx, 8                      ; 64 bytes covers both key formats
    rep movsq

    pop rax
    lea rdi, [rax + usrauth_wa_cred_t.rpid_hash]
    mov rsi, r15
    mov rcx, 4
    rep movsq

    inc qword [usrauth_wa_count]

    xor eax, eax
    jmp .wr_return

.wr_inval:
    mov eax, USRAUTH_DENY_INVALID

.wr_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_webauthn_check_counter
;
; Clone detection. The authenticator's signature counter must strictly
; increase; a value equal to or below the last accepted one means two devices
; are answering for the same credential.
;
; A counter of zero is exempt — some authenticators legitimately do not
; implement one, and the specification permits that.
;
; Inputs:
;   RDI = Credential pointer
;   ESI = Counter from this assertion
;
; Returns:
;   EAX = 0 when acceptable, USRAUTH_DENY_REVOKED on suspected cloning
; -----------------------------------------------------------------------------
align 32
usrauth_webauthn_check_counter:
    mov eax, dword [rdi + usrauth_wa_cred_t.sign_count]

    ; Both zero: authenticator does not maintain a counter.
    test esi, esi
    jnz .cc_compare
    test eax, eax
    jz .cc_ok
    jmp .cc_clone                   ; Counter went to zero after being non-zero

.cc_compare:
    cmp esi, eax
    jbe .cc_clone                   ; Not strictly increasing

    mov dword [rdi + usrauth_wa_cred_t.sign_count], esi

.cc_ok:
    xor eax, eax
    ret

.cc_clone:
    inc qword [usrauth_wa_clones]
    mov eax, USRAUTH_DENY_REVOKED
    ret

; -----------------------------------------------------------------------------
; usrauth_webauthn_verify
;
; Validates an assertion.
;
; Order is deliberate: the cheap binding checks run before the signature, so a
; wrong-origin or absent-user assertion is rejected without any curve work.
;
; The binding, presence and counter checks below are the security-relevant
; part, and they run before any curve arithmetic — a valid signature over the
; wrong RP ID is still an attack, and refusing it early costs nothing.
;
; Inputs:
;   RDI = Credential id (32 bytes)
;   RSI = Authenticator data pointer
;   EDX = Authenticator data length
;   RCX = Client data hash (32 bytes)
;   R8  = Signature pointer
;   R9D = Signature length
;
; Returns:
;   EAX = USRAUTH_ALLOW, or a USRAUTH_DENY_* code
; -----------------------------------------------------------------------------
align 32
usrauth_webauthn_verify:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, USRAUTH_WA_MAX_AUTHDATA + USRAUTH_WA_RPID_BYTES

    mov r12, rsi                    ; Authenticator data
    mov r13d, edx                   ; Its length
    mov r14, rcx                    ; Client data hash
    mov r15, r8                     ; Signature
    mov ebp, r9d                    ; Signature length — ES256 is DER, so the
                                    ; length is part of the input, not implied

    test r12, r12
    jz .wv_inval
    test r14, r14
    jz .wv_inval
    cmp r13d, usrauth_wa_authdata_t_size
    jb .wv_inval                    ; Too short to contain the prefix

    call usrauth_webauthn_find
    test rax, rax
    jz .wv_reject
    mov rbx, rax                    ; Credential

    ; ---- 1. RP ID binding. This is what makes WebAuthn phishing-resistant ----
    lea rdi, [rbx + usrauth_wa_cred_t.rpid_hash]
    lea rsi, [r12 + usrauth_wa_authdata_t.rpid_hash]
    mov rdx, USRAUTH_WA_RPID_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .wv_reject                  ; Assertion is for a different origin

    ; ---- 2. User Present. Proves a human interacted with the device ----
    movzx eax, byte [r12 + usrauth_wa_authdata_t.flags]
    test eax, USRAUTH_WA_FLAG_UP
    jz .wv_reject

    ; ---- 3. Counter must strictly increase ----
    mov eax, dword [r12 + usrauth_wa_authdata_t.sign_count]
    bswap eax                       ; Counter is big-endian on the wire
    mov rdi, rbx
    mov esi, eax
    call usrauth_webauthn_check_counter
    test eax, eax
    jnz .wv_return

    ; ---- 4. Signature over authData || clientDataHash ----
    ; BOTH halves must be signed. The challenge lives in the client data, so a
    ; signature covering only authData is not bound to the challenge at all —
    ; one captured assertion would then replay against every future one. The
    ; two are concatenated here, in that order, exactly as the authenticator
    ; signed them.
    ;
    ; Both algorithms verify for real. ES256 signatures arrive DER-encoded, as
    ; authenticators emit them; EdDSA signatures are the raw 64-byte pair.
    cmp r13d, USRAUTH_WA_MAX_AUTHDATA
    ja .wv_inval

    lea rdi, [rsp]                  ; Message buffer reserved on entry
    mov rsi, r12
    mov ecx, r13d
    rep movsb                       ; authData
    mov rsi, r14
    mov ecx, USRAUTH_WA_RPID_BYTES
    rep movsb                       ; then the client data hash

    mov r8d, r13d
    add r8d, USRAUTH_WA_RPID_BYTES  ; Total signed length

    mov eax, dword [rbx + usrauth_wa_cred_t.algorithm]
    cmp eax, USRAUTH_WA_ALG_EDDSA
    je .wv_eddsa

    ; ES256 — DER signature, so its length matters and is passed through.
    lea rdi, [rbx + usrauth_wa_cred_t.pubkey]
    lea rsi, [rsp]
    mov edx, r8d
    mov rcx, r15
    mov r8d, ebp                    ; Signature length
    call ecdsa_p256_verify_der
    jmp .wv_sig_result

.wv_eddsa:
    lea rdi, [rbx + usrauth_wa_cred_t.pubkey]
    lea rsi, [rsp]
    mov edx, r8d
    mov rcx, r15
    call ed25519_verify

.wv_sig_result:
    test rax, rax
    jz .wv_reject                   ; Both verifiers return 0 for a bad signature

    inc qword [usrauth_wa_verified]
    xor eax, eax
    jmp .wv_return

.wv_reject:
    inc qword [usrauth_wa_rejected]
    mov eax, USRAUTH_DENY_REVOKED
    jmp .wv_return

.wv_inval:
    mov eax, USRAUTH_DENY_INVALID

.wv_return:
    add rsp, USRAUTH_WA_MAX_AUTHDATA + USRAUTH_WA_RPID_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; GUARD_SECURITY_USRAUTH_IDENTITY_WEBAUTHN_ASM
