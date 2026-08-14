%ifndef GUARD_SECURITY_USRAUTH_IDENTITY_ATTEST_ASM
%define GUARD_SECURITY_USRAUTH_IDENTITY_ATTEST_ASM
; =============================================================================
; Tattva OS — security/usrauth/identity/attest.asm
; =============================================================================
; L0 — Attestation-Rooted Workload Identity.
;
; Implements:
;   - PCR policy registration (`usrauth_attest_set_policy`)
;   - Measurement extension (`usrauth_attest_extend`)
;   - Identity derivation from measured state (`usrauth_attest_derive_id`)
;   - Boot-state verification (`usrauth_attest_verify`)
;
; In a unikernel there is no user database to compromise, so the strongest
; identity available is not a secret the workload HOLDS but the measurement of
; what the workload IS. That is the SPIFFE insight applied downward: identity
; derived from attested state rather than from a configured credential.
;
; A PCR is extended, never written:
;
;   PCR_new = SHA-256(PCR_old || measurement)
;
; That one-way chaining is the whole security property. Because extension is
; not invertible and not reorderable, code that runs later cannot roll a PCR
; back to a value that was valid earlier, and cannot reach a target value by
; extending in a different order. Allowing direct writes would let a
; compromised later stage forge the boot state that preceded it.
;
; The derived identity therefore changes whenever the boot chain changes — a
; different kernel, a tampered loader, or a different machine all produce a
; different id. That is intended: authority tied to this identity evaporates
; the moment the platform stops being the platform it claimed to be.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_PCR_COUNT            24      ; TPM 2.0 platform PCR bank
%define USRAUTH_PCR_BYTES            32      ; SHA-256 digests
%define USRAUTH_ATTEST_ID_BYTES      32

; Conventional PCR assignments, following the TCG platform profile.
%define USRAUTH_PCR_FIRMWARE         0
%define USRAUTH_PCR_CONFIG           1
%define USRAUTH_PCR_LOADER           4
%define USRAUTH_PCR_KERNEL           8
%define USRAUTH_PCR_POLICY           9       ; usrauth policy artifact

struc usrauth_attest_policy_t
    .pcr_mask:          resd 1      ; Which PCRs participate, one bit each
    .reserved:          resd 1
    .expected:          resb USRAUTH_PCR_COUNT * USRAUTH_PCR_BYTES
    .bound:             resd 1      ; Non-zero once expectations are frozen
    .reserved2:         resd 1
endstruc

section .data
align 64

; Shadow of the platform PCR bank. Mirrors the TPM so a policy can be checked
; without a chip round-trip on every decision.
global usrauth_pcr_bank
usrauth_pcr_bank:       times USRAUTH_PCR_COUNT * USRAUTH_PCR_BYTES db 0

global usrauth_attest_policy
usrauth_attest_policy:  times usrauth_attest_policy_t_size db 0

usrauth_attest_id:      times USRAUTH_ATTEST_ID_BYTES db 0
usrauth_attest_valid:   dq 0
usrauth_attest_extends: dq 0
usrauth_attest_fails:   dq 0

section .text

global usrauth_attest_set_policy
global usrauth_attest_extend
global usrauth_attest_derive_id
global usrauth_attest_verify
global usrauth_attest_get_id
global usrauth_attest_reset

; -----------------------------------------------------------------------------
; usrauth_attest_reset
;
; Clears the shadow bank. Only legitimate at cold boot — calling it later would
; discard the measurement history the policy depends on.
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_attest_reset:
    push rdi
    push rcx
    lea rdi, [usrauth_pcr_bank]
    mov rcx, USRAUTH_PCR_COUNT * USRAUTH_PCR_BYTES
    xor al, al
    rep stosb
    mov qword [usrauth_attest_valid], 0
    pop rcx
    pop rdi
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usrauth_attest_extend
;
; PCR[i] = SHA-256(PCR[i] || measurement)
;
; There is deliberately no "set PCR" counterpart. Extension is the only
; mutation, which is what makes the resulting value unforgeable by anything
; that runs after the measurement it is trying to fake.
;
; Inputs:
;   EDI = PCR index
;   RSI = Measurement digest pointer (32 bytes)
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID on a bad index
; -----------------------------------------------------------------------------
align 32
usrauth_attest_extend:
    push rbx
    push r12
    push r13
    sub rsp, 80                     ; 64-byte concat buffer + slack

    mov r12d, edi
    mov r13, rsi

    cmp r12d, USRAUTH_PCR_COUNT
    jae .ae_inval
    test r13, r13
    jz .ae_inval

    ; Address of this PCR in the shadow bank.
    mov rax, r12
    imul rax, USRAUTH_PCR_BYTES
    lea rbx, [usrauth_pcr_bank]
    add rbx, rax

    ; Concatenate old PCR value with the new measurement.
    mov rdi, rsp
    mov rsi, rbx
    mov rcx, 4
    rep movsq

    lea rdi, [rsp + USRAUTH_PCR_BYTES]
    mov rsi, r13
    mov rcx, 4
    rep movsq

    ; Hash the pair back into the PCR.
    mov rdi, rsp
    mov rsi, USRAUTH_PCR_BYTES * 2
    mov rdx, rbx
    call sha256_hash

    inc qword [usrauth_attest_extends]

    ; Any extension invalidates a previously derived identity.
    mov qword [usrauth_attest_valid], 0

    xor eax, eax
    jmp .ae_return

.ae_inval:
    mov eax, USRAUTH_DENY_INVALID

.ae_return:
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_attest_set_policy
;
; Freezes the expected PCR values for the participating registers.
;
; Once bound, the expectations cannot be replaced. A policy that could be
; rewritten at runtime would let a compromised kernel simply declare its own
; measurements correct.
;
; Inputs:
;   EDI = PCR participation mask
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID when already bound
; -----------------------------------------------------------------------------
align 32
usrauth_attest_set_policy:
    push rbx
    push r12
    push r13

    lea rbx, [usrauth_attest_policy]

    cmp dword [rbx + usrauth_attest_policy_t.bound], 0
    jne .sp_inval                   ; Already sealed

    mov dword [rbx + usrauth_attest_policy_t.pcr_mask], edi

    ; Snapshot the current bank as the expected state.
    lea rdi, [rbx + usrauth_attest_policy_t.expected]
    lea rsi, [usrauth_pcr_bank]
    mov rcx, (USRAUTH_PCR_COUNT * USRAUTH_PCR_BYTES) / 8
    rep movsq

    mov dword [rbx + usrauth_attest_policy_t.bound], 1

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.sp_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_attest_verify
;
; Compares every participating PCR against its expected value, in constant
; time so a mismatch position cannot be probed by timing.
;
; Returns:
;   EAX = 0 when the boot state matches, USRAUTH_DENY_MANDATORY otherwise
; -----------------------------------------------------------------------------
align 32
usrauth_attest_verify:
    push rbx
    push r12
    push r13
    push r14

    lea rbx, [usrauth_attest_policy]

    cmp dword [rbx + usrauth_attest_policy_t.bound], 0
    je .av_fail                     ; No policy: cannot attest to anything

    mov r12d, dword [rbx + usrauth_attest_policy_t.pcr_mask]
    xor r13, r13                    ; PCR index
    xor r14d, r14d                  ; Accumulated difference

.av_loop:
    cmp r13, USRAUTH_PCR_COUNT
    jae .av_decide

    ; Skip registers not covered by the policy.
    mov ecx, r13d
    mov eax, 1
    shl eax, cl
    test r12d, eax
    jz .av_next

    mov rax, r13
    imul rax, USRAUTH_PCR_BYTES

    lea rdi, [usrauth_pcr_bank]
    add rdi, rax
    lea rsi, [rbx + usrauth_attest_policy_t.expected]
    add rsi, rax
    mov rdx, USRAUTH_PCR_BYTES

    push r13
    call ucrypt_ct_memcmp
    pop r13

    or r14d, eax                    ; Accumulate; never exit early

.av_next:
    inc r13
    jmp .av_loop

.av_decide:
    test r14d, r14d
    jnz .av_fail

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.av_fail:
    inc qword [usrauth_attest_fails]
    mov eax, USRAUTH_DENY_MANDATORY
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_attest_derive_id
;
; Derives a stable workload identity from the participating PCRs.
;
;   id = SHA-256("USRAUTH-ATTEST-v1" || PCR[i] for each i in mask)
;
; The label provides domain separation so this value cannot collide with any
; other digest computed over the same registers.
;
; Inputs:
;   RDI = Pointer to a 32-byte identity output buffer
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_MANDATORY when attestation fails
; -----------------------------------------------------------------------------
align 32
usrauth_attest_derive_id:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 832                    ; Label + up to 24 PCR digests

    mov r15, rdi
    test r15, r15
    jz .di_fail

    ; Identity is only meaningful if the platform is in the expected state.
    call usrauth_attest_verify
    test eax, eax
    jnz .di_fail

    lea rbx, [usrauth_attest_policy]
    mov r12d, dword [rbx + usrauth_attest_policy_t.pcr_mask]

    ; Domain-separating label.
    lea rdi, [rsp]
    lea rsi, [usrauth_attest_label]
    mov rcx, usrauth_attest_label_len
    rep movsb

    mov r14, usrauth_attest_label_len   ; Running offset
    xor r13, r13                        ; PCR index

.di_loop:
    cmp r13, USRAUTH_PCR_COUNT
    jae .di_hash

    mov ecx, r13d
    mov eax, 1
    shl eax, cl
    test r12d, eax
    jz .di_next

    mov rax, r13
    imul rax, USRAUTH_PCR_BYTES
    lea rsi, [usrauth_pcr_bank]
    add rsi, rax
    lea rdi, [rsp + r14]
    mov rcx, 4
    rep movsq
    add r14, USRAUTH_PCR_BYTES

.di_next:
    inc r13
    jmp .di_loop

.di_hash:
    lea rdi, [rsp]
    mov rsi, r14
    lea rdx, [usrauth_attest_id]
    call sha256_hash

    ; Hand a copy to the caller.
    mov rdi, r15
    lea rsi, [usrauth_attest_id]
    mov rcx, 4
    rep movsq

    mov qword [usrauth_attest_valid], 1

    xor eax, eax
    jmp .di_return

.di_fail:
    inc qword [usrauth_attest_fails]
    mov eax, USRAUTH_DENY_MANDATORY

.di_return:
    add rsp, 832
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_attest_get_id
;
; Returns the cached identity, if one has been derived and is still valid.
;
; Inputs:
;   RDI = Pointer to a 32-byte output buffer
;
; Returns:
;   EAX = 0 on success, USRAUTH_DENY_INVALID when no valid identity exists
; -----------------------------------------------------------------------------
align 32
usrauth_attest_get_id:
    cmp qword [usrauth_attest_valid], 0
    je .gi_inval
    test rdi, rdi
    jz .gi_inval

    lea rsi, [usrauth_attest_id]
    mov rcx, 4
    rep movsq

    xor eax, eax
    ret

.gi_inval:
    mov eax, USRAUTH_DENY_INVALID
    ret

section .rodata
usrauth_attest_label:       db "USRAUTH-ATTEST-v1"
usrauth_attest_label_len    equ $ - usrauth_attest_label

%endif ; GUARD_SECURITY_USRAUTH_IDENTITY_ATTEST_ASM
