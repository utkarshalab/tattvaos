%ifndef GUARD_CRYPTO_UPASS_ASM
%define GUARD_CRYPTO_UPASS_ASM
; =============================================================================
; Tattva OS — crypto/upass/upass.asm
; =============================================================================
; Password Hashing — Layered Stretch, Pepper and Device Binding.
;
; Implements:
;   - Record creation (`upass_hash`)
;   - Verification with constant-time compare (`upass_verify`)
;   - Rehash-on-verify policy check (`upass_needs_rehash`)
;   - Pepper and device-key installation (`upass_set_pepper`, `_set_device_key`)
;
; Three layers, each defeating a different attacker:
;
;   Stage 1  mk     = Argon2id(password, salt, secret=pepper, ad=uid, m, t, p)
;   Stage 2  dk     = HMAC-SHA256(pepper, "UPASS-KDF-v1" || uid || mk)
;   Stage 3  stored = dk XOR HMAC-SHA256(device_key, "UPASS-WRAP-v1" || salt)
;
; | Attacker holds        | Stopped by                                  |
; |-----------------------|---------------------------------------------|
; | Credential database   | Stage 1 — memory-hard cost per guess        |
; | Database + disk image | Stage 2 — pepper is not in the database     |
; | Database + pepper     | Stage 3 — device key never leaves the TPM   |
; | Powered-off machine   | Stage 3 — TPM refuses on changed PCRs       |
;
; THE PEPPER GOES INSIDE STAGE 1, not only after it. Argon2 has a secret
; parameter K for exactly this. Mixing the pepper in only afterwards would let
; an attacker who holds the database but not the pepper pay the memory-hard
; cost ONCE per password guess and then try candidate peppers cheaply against
; that result. Feeding it to Argon2 makes every (password, pepper) pair cost a
; full memory-hard evaluation. Stage 2 keeps the pepper as well, so a weakness
; in either construction still leaves the other standing.
;
; Stage 3 is a REVERSIBLE wrap, not another hash. That is deliberate: baking a
; device identity into the digest makes credentials unrecoverable the moment a
; motherboard dies. As a wrap it can be unwrapped with the old device key and
; re-wrapped with the new one, so hardware migration is not a password reset.
; This requires an escrow key — without one, a dead board still means dead
; credentials.
;
; The Stage 3 keystream is derived per record from the salt, so no two records
; share it. A fixed keystream XORed across many records would let an attacker
; cancel it out by XORing two stored values together.
;
; PBKDF2 RECORDS STILL VERIFY. The record carries its own algorithm and cost, so
; credentials written before Argon2id existed authenticate normally and are
; rewritten at current policy on the next successful login. A migration that
; required every user to reset their password would, in practice, be deployed
; by nobody.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%define UPASS_VERSION           1
%define UPASS_ALGO_PBKDF2       1       ; Legacy; verified, then upgraded
%define UPASS_ALGO_ARGON2ID     2       ; Current

%define UPASS_SALT_BYTES        16
%define UPASS_DIGEST_BYTES      32
%define UPASS_KEY_BYTES         32

; Current policy. Raise over time; rehash-on-verify upgrades records in place.
;
; 16 MiB / 3 passes / 1 lane. RFC 9106's second recommended profile is 64 MiB
; with 4 lanes; the memory is halved to stay inside the Argon2 arena, and lanes
; are pinned to 1 because extra lanes only pay off when they run in parallel.
; Adding lanes on a single thread shortens the dependency chain each lane must
; follow — it makes the hash cheaper to attack, not more expensive.
%define UPASS_MIN_M_COST        16384
%define UPASS_MIN_T_COST        3
%define UPASS_DEFAULT_M_COST    16384
%define UPASS_DEFAULT_T_COST    3
%define UPASS_DEFAULT_LANES     1

; There is deliberately no PBKDF2 cost floor: a PBKDF2 record is upgraded on
; sight whatever its iteration count, because no number of iterations makes it
; memory-hard. A floor here would imply some PBKDF2 records are good enough.

; -----------------------------------------------------------------------------
; On-disk credential record. Parameters are stored per record so policy can
; rise without invalidating anything already written.
;
; t_cost carries Argon2id passes or PBKDF2 iterations depending on .algo; the
; two never coexist in one record, and reading it under the wrong algorithm
; would be a verification failure rather than a silent weakening.
; -----------------------------------------------------------------------------
struc upass_record_t
    .version:           resd 1      ; UPASS_VERSION
    .algo:              resd 1      ; UPASS_ALGO_*
    .m_cost:            resd 1      ; KiB of memory (Argon2id only)
    .t_cost:            resd 1      ; Passes, or PBKDF2 iterations
    .lanes:             resd 1      ; Argon2id only
    .reserved:          resd 1
    .salt:              resb UPASS_SALT_BYTES
    .digest:            resb UPASS_DIGEST_BYTES     ; Wrapped
    .created_ns:        resq 1
endstruc

section .data
align 64

upass_pepper:       times UPASS_KEY_BYTES db 0
upass_pepper_set:   dq 0
upass_device_key:   times UPASS_KEY_BYTES db 0
upass_device_set:   dq 0

upass_scratch_mk:   times UPASS_DIGEST_BYTES db 0
upass_scratch_dk:   times UPASS_DIGEST_BYTES db 0
upass_scratch_ks:   times UPASS_DIGEST_BYTES db 0
upass_scratch_in:   times 128 db 0
upass_scratch_ad:   dd 0            ; uid as Argon2 associated data

upass_hashes:       dq 0
upass_verifies:     dq 0
upass_rejects:      dq 0

section .rodata
upass_kdf_label:    db "UPASS-KDF-v1"
upass_kdf_label_len equ $ - upass_kdf_label
upass_wrap_label:   db "UPASS-WRAP-v1"
upass_wrap_label_len equ $ - upass_wrap_label

section .text

global upass_set_pepper
global upass_set_device_key
global upass_hash
global upass_verify
global upass_needs_rehash
global upass_derive

; -----------------------------------------------------------------------------
; upass_set_pepper
;
; Installs the server-side secret. It must live outside the credential store —
; a pepper kept beside the hashes it protects is decorative.
;
; Inputs:
;   RDI = Pointer to 32 pepper bytes
;
; Returns:
;   EAX = 0 on success, -22 on a null argument
; -----------------------------------------------------------------------------
align 32
upass_set_pepper:
    test rdi, rdi
    jz .sp_inval
    mov rsi, rdi
    lea rdi, [upass_pepper]
    mov rcx, 4
    rep movsq
    mov qword [upass_pepper_set], 1
    xor eax, eax
    ret
.sp_inval:
    mov eax, -22
    ret

; -----------------------------------------------------------------------------
; upass_set_device_key
;
; Installs the device-binding key, normally unsealed from the TPM against a PCR
; policy. Passing 0 disables Stage 3, which is legitimate for a portable
; credential store but forfeits device binding.
;
; Inputs:
;   RDI = Pointer to 32 key bytes, or 0 to disable
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
upass_set_device_key:
    test rdi, rdi
    jz .sd_disable
    mov rsi, rdi
    lea rdi, [upass_device_key]
    mov rcx, 4
    rep movsq
    mov qword [upass_device_set], 1
    xor eax, eax
    ret
.sd_disable:
    lea rdi, [upass_device_key]
    xor rax, rax
    mov rcx, 4
    rep stosq
    mov qword [upass_device_set], 0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; upass_derive
;
; Runs all three stages into upass_scratch_dk.
;
; Inputs:
;   RDI = Password pointer
;   ESI = Password length
;   RDX = Pointer to a upass_record_t supplying salt and parameters
;   ECX = uid, bound into Stage 2 so identical passwords differ per user
;
; Returns:
;   EAX = 0 on success, -22 when the pepper is not installed
; -----------------------------------------------------------------------------
align 32
upass_derive:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Password
    mov r12d, esi                   ; Password length
    mov r13, rdx                    ; Record
    mov r14d, ecx                   ; uid

    cmp qword [upass_pepper_set], 0
    je .dv_inval                    ; Refuse rather than silently skip Stage 2

    ; ---- Stage 1: memory-hard stretch ----
    ; Dispatch on the record's own algorithm, so a credential written under an
    ; older scheme still authenticates instead of locking its owner out.
    cmp dword [r13 + upass_record_t.algo], UPASS_ALGO_PBKDF2
    je .dv_pbkdf2

    mov eax, r14d
    mov [upass_scratch_ad], eax

    sub rsp, argon2_params_t_size
    mov [rsp + argon2_params_t.pwd], rbx
    mov [rsp + argon2_params_t.pwdlen], r12d
    lea rax, [r13 + upass_record_t.salt]
    mov [rsp + argon2_params_t.salt], rax
    mov dword [rsp + argon2_params_t.saltlen], UPASS_SALT_BYTES
    lea rax, [upass_pepper]
    mov [rsp + argon2_params_t.secret], rax
    mov dword [rsp + argon2_params_t.secretlen], UPASS_KEY_BYTES
    lea rax, [upass_scratch_ad]
    mov [rsp + argon2_params_t.ad], rax
    mov dword [rsp + argon2_params_t.adlen], 4
    lea rax, [upass_scratch_mk]
    mov [rsp + argon2_params_t.out], rax
    mov dword [rsp + argon2_params_t.outlen], UPASS_DIGEST_BYTES
    mov eax, [r13 + upass_record_t.m_cost]
    mov [rsp + argon2_params_t.m_cost], eax
    mov eax, [r13 + upass_record_t.t_cost]
    mov [rsp + argon2_params_t.t_cost], eax
    mov eax, [r13 + upass_record_t.lanes]
    mov [rsp + argon2_params_t.lanes], eax

    mov rdi, rsp
    call argon2id_hash_ex
    add rsp, argon2_params_t_size
    test eax, eax
    jnz .dv_inval
    jmp .dv_stage2

.dv_pbkdf2:
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [r13 + upass_record_t.salt]
    mov ecx, UPASS_SALT_BYTES
    mov r8d, dword [r13 + upass_record_t.t_cost]
    lea r9, [upass_scratch_mk]
    push UPASS_DIGEST_BYTES
    call pbkdf2_sha256
    add rsp, 8
    test rax, rax
    js .dv_inval

.dv_stage2:
    ; ---- Stage 2: pepper-keyed, uid-bound ----
    lea rdi, [upass_scratch_in]
    lea rsi, [upass_kdf_label]
    mov rcx, upass_kdf_label_len
    rep movsb
    mov eax, r14d
    mov [rdi], eax                  ; uid follows the label
    add rdi, 4
    lea rsi, [upass_scratch_mk]
    mov rcx, 4
    rep movsq                       ; then the stretched key

    lea rdi, [upass_pepper]
    mov rsi, UPASS_KEY_BYTES
    lea rdx, [upass_scratch_in]
    mov ecx, upass_kdf_label_len + 4 + UPASS_DIGEST_BYTES
    lea r8, [upass_scratch_dk]
    call hmac_sha256

    ; ---- Stage 3: device wrap, keystream unique per salt ----
    cmp qword [upass_device_set], 0
    je .dv_done

    lea rdi, [upass_scratch_in]
    lea rsi, [upass_wrap_label]
    mov rcx, upass_wrap_label_len
    rep movsb
    lea rsi, [r13 + upass_record_t.salt]
    mov rcx, UPASS_SALT_BYTES
    rep movsb

    lea rdi, [upass_device_key]
    mov rsi, UPASS_KEY_BYTES
    lea rdx, [upass_scratch_in]
    mov ecx, upass_wrap_label_len + UPASS_SALT_BYTES
    lea r8, [upass_scratch_ks]
    call hmac_sha256

    lea rdi, [upass_scratch_dk]
    lea rsi, [upass_scratch_ks]
    mov rax, [rsi]
    xor [rdi], rax
    mov rax, [rsi + 8]
    xor [rdi + 8], rax
    mov rax, [rsi + 16]
    xor [rdi + 16], rax
    mov rax, [rsi + 24]
    xor [rdi + 24], rax

.dv_done:
    ; The stretched key is as sensitive as the password; do not leave it.
    lea rdi, [upass_scratch_mk]
    xor rax, rax
    mov rcx, 4
    rep stosq

    xor eax, eax
    jmp .dv_return

.dv_inval:
    mov eax, -22

.dv_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; upass_hash
;
; Creates a credential record from a password.
;
; Inputs:
;   RDI = Password pointer
;   ESI = Password length
;   RDX = Pointer to a upass_record_t to fill
;   ECX = uid
;
; Returns:
;   EAX = 0 on success, negative on failure
; -----------------------------------------------------------------------------
align 32
upass_hash:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx

    test rbx, rbx
    jz .uh_inval
    test r13, r13
    jz .uh_inval

    mov dword [r13 + upass_record_t.version], UPASS_VERSION
    mov dword [r13 + upass_record_t.algo], UPASS_ALGO_ARGON2ID
    mov dword [r13 + upass_record_t.m_cost], UPASS_DEFAULT_M_COST
    mov dword [r13 + upass_record_t.t_cost], UPASS_DEFAULT_T_COST
    mov dword [r13 + upass_record_t.lanes], UPASS_DEFAULT_LANES
    mov dword [r13 + upass_record_t.reserved], 0

    ; Fresh salt per record: without it, identical passwords collide and one
    ; precomputed table breaks every account at once.
    lea rdi, [r13 + upass_record_t.salt]
    mov rsi, UPASS_SALT_BYTES
    call urand_get_bytes

    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    mov ecx, r14d
    call upass_derive
    test eax, eax
    jnz .uh_return

    lea rdi, [r13 + upass_record_t.digest]
    lea rsi, [upass_scratch_dk]
    mov rcx, 4
    rep movsq

    call mono_get_nanos
    mov [r13 + upass_record_t.created_ns], rax

    ; Scrub the derived value now that it is stored.
    lea rdi, [upass_scratch_dk]
    xor rax, rax
    mov rcx, 4
    rep stosq

    inc qword [upass_hashes]
    xor eax, eax
    jmp .uh_return

.uh_inval:
    mov eax, -22

.uh_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; upass_verify
;
; Recomputes the record and compares in constant time.
;
; A byte-wise early-exit compare would let an attacker recover the stored value
; one byte at a time by measuring how quickly a wrong password is rejected.
;
; Inputs:
;   RDI = Password pointer
;   ESI = Password length
;   RDX = Pointer to a upass_record_t
;   ECX = uid
;
; Returns:
;   EAX = 1 when the password matches, 0 otherwise
; -----------------------------------------------------------------------------
align 32
upass_verify:
    push rbx
    push r12

    mov rbx, rdx                    ; Record

    test rdi, rdi
    jz .uv_no
    test rbx, rbx
    jz .uv_no
    cmp dword [rbx + upass_record_t.version], UPASS_VERSION
    ja .uv_no                       ; Written by a newer scheme

    call upass_derive
    test eax, eax
    jnz .uv_no

    lea rdi, [upass_scratch_dk]
    lea rsi, [rbx + upass_record_t.digest]
    mov rdx, UPASS_DIGEST_BYTES
    call ucrypt_ct_memcmp
    mov r12, rax

    ; Scrub before branching on the result.
    lea rdi, [upass_scratch_dk]
    xor rax, rax
    mov rcx, 4
    rep stosq

    inc qword [upass_verifies]

    test r12, r12
    jnz .uv_no

    mov eax, 1
    pop r12
    pop rbx
    ret

.uv_no:
    inc qword [upass_rejects]
    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; upass_needs_rehash
;
; Reports whether a record was created under weaker parameters than current
; policy.
;
; Callers should invoke this after a SUCCESSFUL verify and, when it returns
; non-zero, recompute the record with today's cost. Without this step a
; deployment's 2026 parameters are still protecting accounts years later,
; because existing records are never revisited.
;
; Inputs:
;   RDI = Pointer to a upass_record_t
;
; Returns:
;   EAX = 1 when the record should be upgraded, 0 otherwise
; -----------------------------------------------------------------------------
align 32
upass_needs_rehash:
    test rdi, rdi
    jz .nr_no

    cmp dword [rdi + upass_record_t.version], UPASS_VERSION
    jb .nr_yes                      ; Older scheme version

    ; Any record not on the current algorithm is upgraded on sight. A PBKDF2
    ; record is not broken, but it is not memory-hard, and the one moment the
    ; plaintext is legitimately available is the moment to fix that.
    cmp dword [rdi + upass_record_t.algo], UPASS_ALGO_ARGON2ID
    jne .nr_yes

    cmp dword [rdi + upass_record_t.m_cost], UPASS_MIN_M_COST
    jb .nr_yes
    cmp dword [rdi + upass_record_t.t_cost], UPASS_MIN_T_COST
    jb .nr_yes

.nr_no:
    xor eax, eax
    ret

.nr_yes:
    mov eax, 1
    ret

%endif ; GUARD_CRYPTO_UPASS_ASM
