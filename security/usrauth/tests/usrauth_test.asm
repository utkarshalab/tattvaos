; =============================================================================
; Tattva OS — security/usrauth/tests/usrauth_test.asm
; =============================================================================
; Semantic test suite for the reference monitor.
;
; The point of these tests is NOT to show that the code runs. It is to show
; that each layer denies what it is supposed to deny even when every other
; layer would have allowed it. A permission system that grants correctly but
; denies incorrectly fails silently and in the dangerous direction, so most of
; what follows sets up an access that all-but-one layer permits, and then
; asserts the exact deny code the remaining layer must produce.
;
; Asserting the SPECIFIC deny code, rather than merely "not allowed", is what
; makes these tests worth anything. A bug that makes every request fail would
; pass a suite that only checked for denial.
;
; Each test owns one bit of the failure mask; 0 means everything passed.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM), hosted test build
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .data
align 8

obj_file:       times usrauth_object_t_size db 0
obj_secret:     times usrauth_object_t_size db 0
tok:            times usrauth_token_t_size db 0
tok2:           times usrauth_token_t_size db 0
tok_a:          times usrauth_token_t_size db 0
tok_b:          times usrauth_token_t_size db 0
whocan:         times 16 dd 0

; Subject handles held across calls live here, not in registers. r10 and r11
; are caller-saved under SysV, so a handle parked in one survives only until
; the next call — and a test whose subject handle silently turns into garbage
; asserts nothing while still appearing to pass.
h_eve:          dd 0
h_dave:         dd 0
h_frank:        dd 0

FILE_ID         equ 0x1000
SECRET_ID       equ 0x2000
T_USER          equ 1
T_FILE          equ 2
T_SECRET        equ 3

section .text
global _start

_start:
    xor r15d, r15d                  ; Failure mask

    xor rdi, rdi
    call usrauth_init

    ; ---- object: ordinary file, medium integrity ----
    lea rbx, [obj_file]
    mov qword [rbx + usrauth_object_t.object_id], FILE_ID
    mov dword [rbx + usrauth_object_t.object_class], USRAUTH_CLASS_FILE
    mov dword [rbx + usrauth_object_t.type_id], T_FILE
    mov dword [rbx + usrauth_object_t.integrity], USRAUTH_INTEGRITY_MEDIUM

    ; ---- object: high-integrity secret ----
    lea rbx, [obj_secret]
    mov qword [rbx + usrauth_object_t.object_id], SECRET_ID
    mov dword [rbx + usrauth_object_t.object_class], USRAUTH_CLASS_FILE
    mov dword [rbx + usrauth_object_t.type_id], T_SECRET
    mov dword [rbx + usrauth_object_t.integrity], USRAUTH_INTEGRITY_HIGH

    ; ---- TE policy: T_USER may read+write T_FILE, but only READ T_SECRET ----
    mov edi, T_USER
    mov esi, T_FILE
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ | USRAUTH_VERB_WRITE
    call usrauth_te_add

    mov edi, T_USER
    mov esi, T_SECRET
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_te_add

    ; ---- subject alice ----
    mov edi, 1000
    mov esi, 1000
    mov edx, T_USER
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    mov r14d, eax                   ; alice

    mov edi, r14d
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ | USRAUTH_VERB_WRITE
    xor r8, r8
    call usrauth_cap_grant

    mov rdi, FILE_ID
    mov esi, USRAUTH_VERB_READ | USRAUTH_VERB_WRITE
    mov edx, r14d
    xor rcx, rcx
    xor r8, r8
    call usrauth_relation_add

; =============================================================================
; T1 — the full stack allows a request every layer permits.
;
; The baseline. Without it a suite of deny-assertions would pass on a monitor
; that denies unconditionally.
; =============================================================================
    mov edi, r14d
    lea rsi, [obj_file]
    mov edx, USRAUTH_VERB_READ
    call usrauth_check
    test eax, eax
    jz .t1
    or r15d, 1
.t1:

; =============================================================================
; T2 — L3 capability held, L4 relation absent: policy denies.
;
; The capability is granted deliberately so that the capability layer cannot
; be the one denying. Intersection means holding authority is necessary but
; never sufficient.
; =============================================================================
    mov edi, r14d
    mov rsi, SECRET_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    xor r8, r8
    call usrauth_cap_grant

    mov edi, r14d
    lea rsi, [obj_secret]
    mov edx, USRAUTH_VERB_READ
    call usrauth_check
    cmp eax, USRAUTH_DENY_POLICY
    je .t2
    or r15d, 2
.t2:

; =============================================================================
; T3 — L5 type enforcement overrides both capability and relation.
;
; Grant the capability AND the relation for WRITE on the secret, so the only
; remaining objector is the TE rule that never permitted WRITE on T_SECRET.
; =============================================================================
    mov edi, r14d
    mov rsi, SECRET_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_WRITE
    xor r8, r8
    call usrauth_cap_grant
    mov rdi, SECRET_ID
    mov esi, USRAUTH_VERB_READ | USRAUTH_VERB_WRITE
    mov edx, r14d
    xor rcx, rcx
    xor r8, r8
    call usrauth_relation_add

    mov edi, r14d
    lea rsi, [obj_secret]
    mov edx, USRAUTH_VERB_WRITE
    call usrauth_check
    cmp eax, USRAUTH_DENY_MANDATORY
    je .t3
    or r15d, 4
.t3:

; =============================================================================
; T4 — L2 Biba integrity blocks a write-up.
;
; TE is widened first to permit WRITE on T_SECRET, removing the T3 objector.
; Now medium-integrity alice writing a high-integrity object must be stopped by
; integrity and nothing else.
; =============================================================================
    mov edi, T_USER
    mov esi, T_SECRET
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ | USRAUTH_VERB_WRITE
    call usrauth_te_add

    mov edi, r14d
    lea rsi, [obj_secret]
    mov edx, USRAUTH_VERB_WRITE
    call usrauth_check
    cmp eax, USRAUTH_DENY_INTEGRITY
    je .t4
    or r15d, 8
.t4:

; =============================================================================
; T5/T6 — delegation attenuates.
;
; Alice holds READ|WRITE and asks to delegate READ|WRITE|ADMIN. The delegation
; must succeed with ADMIN silently dropped, not fail outright and not confer
; authority the delegator never had. T5 asserts the drop, T6 asserts that the
; overlap genuinely survived — a delegation that quietly conferred nothing
; would pass T5 alone.
; =============================================================================
    mov edi, 1001
    mov esi, 1001
    mov edx, T_USER
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    mov r13d, eax                   ; bob

    mov edi, r14d
    mov esi, r13d
    mov rdx, FILE_ID
    mov ecx, USRAUTH_CLASS_FILE
    mov r8d, USRAUTH_VERB_READ | USRAUTH_VERB_WRITE | USRAUTH_VERB_ADMIN
    xor r9, r9
    call usrauth_cap_delegate
    test eax, eax
    js .t5_fail

    mov edi, r13d
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_ADMIN
    call usrauth_cap_check
    cmp eax, USRAUTH_DENY_CAPABILITY
    je .t5
.t5_fail:
    or r15d, 16
.t5:
    mov edi, r13d
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_cap_check
    test eax, eax
    jz .t6
    or r15d, 32
.t6:

; =============================================================================
; T7 — a freshly issued token verifies.
; =============================================================================
    lea rdi, [tok]
    mov esi, r14d
    mov rdx, 100000                 ; lifetime ns
    call usrauth_token_issue
    test eax, eax
    jz .t7a
    or r15d, 64
    jmp .t8
.t7a:
    lea rdi, [tok]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_token_verify
    test eax, eax
    jz .t8
    or r15d, 64
.t8:

; =============================================================================
; T9 — a token whose body was altered no longer authenticates.
;
; The tag covers the subject handle, so flipping it must break verification.
; The specific code is asserted in T19; here the point is simply that the
; altered token is not honoured.
; =============================================================================
    lea rbx, [tok]
    xor byte [rbx + usrauth_token_t.subject_handle], 0xFF
    lea rdi, [tok]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_token_verify
    test eax, eax
    jnz .t9
    or r15d, 128
.t9:
    xor byte [rbx + usrauth_token_t.subject_handle], 0xFF   ; repair

; =============================================================================
; T10 — attenuation narrows and cannot be undone.
;
; Restrict the token to READ, then ask it for WRITE. The caveat must deny even
; though the underlying subject genuinely holds WRITE on this object.
; =============================================================================
    lea rdi, [tok]
    mov esi, USRAUTH_CAVEAT_VERB_MASK
    mov rdx, USRAUTH_VERB_READ
    xor rcx, rcx
    call usrauth_token_attenuate
    test eax, eax
    jnz .t10_fail

    lea rdi, [tok]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_WRITE
    call usrauth_token_verify
    cmp eax, USRAUTH_DENY_CAVEAT
    je .t10
.t10_fail:
    or r15d, 256
.t10:

; =============================================================================
; T11 — an epoch bump revokes outstanding tokens wholesale.
; =============================================================================
    lea rdi, [tok2]
    mov esi, r14d
    mov rdx, 100000
    call usrauth_token_issue

    mov edi, r14d
    call usrauth_subject_bump_epoch

    lea rdi, [tok2]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_token_verify
    cmp eax, USRAUTH_DENY_REVOKED
    je .t11
    or r15d, 512
.t11:

; =============================================================================
; T12 — an expired relation stops granting.
;
; The deadline is set behind the harness clock, so the grant exists in the
; table but has lapsed.
; =============================================================================
    mov edi, 1002
    mov esi, 1002
    mov edx, T_USER
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    mov r12d, eax                   ; carol

    mov edi, r12d
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    xor r8, r8
    call usrauth_cap_grant

    mov rdi, FILE_ID
    mov esi, USRAUTH_VERB_READ
    mov edx, r12d
    xor rcx, rcx
    mov r8, 500000                  ; deadline already behind the clock
    call usrauth_relation_add

    mov edi, r12d
    lea rsi, [obj_file]
    mov edx, USRAUTH_VERB_READ
    call usrauth_check
    cmp eax, USRAUTH_DENY_POLICY
    je .t12
    or r15d, 1024
.t12:

; =============================================================================
; T13 — self-restriction is irreversible.
;
; Bob drops to READ. The WRITE he demonstrably held in T6 must now be gone,
; and nothing in the API may hand it back.
; =============================================================================
    mov edi, r13d
    mov esi, USRAUTH_VERB_READ
    call usrauth_subject_restrict
    test eax, eax
    js .t13_fail

    mov edi, r13d
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_WRITE
    call usrauth_cap_check
    cmp eax, USRAUTH_DENY_CAPABILITY
    je .t13
.t13_fail:
    or r15d, 2048
.t13:

; =============================================================================
; T14 — the reverse query answers "who can read this object".
; =============================================================================
    mov rdi, FILE_ID
    mov esi, USRAUTH_VERB_READ
    lea rdx, [whocan]
    mov ecx, 16
    call usrauth_policy_who_can
    test eax, eax
    jnz .t14
    or r15d, 4096
.t14:

; =============================================================================
; T15/T16 — the audit chain is intact, and tampering with it is detected.
;
; T15 alone would pass on a verifier that returns "intact" unconditionally, so
; T16 corrupts a recorded verdict and requires the check to fail.
; =============================================================================
    xor rdi, rdi
    mov rsi, 20
    call usrauth_audit_verify_chain
    test rax, rax
    jz .t15
    or r15d, 8192
.t15:
    xor rdi, rdi
    call usrauth_audit_get
    test rax, rax
    jz .t16_skip
    xor dword [rax + usrauth_audit_t.verdict], 0xFF
    xor rdi, rdi
    mov rsi, 5
    call usrauth_audit_verify_chain
    test rax, rax
    jnz .t16
    or r15d, 16384
    jmp .t16
.t16_skip:
    or r15d, 16384
.t16:

; =============================================================================
; T17 — MLS forbids reading up.
;
; A level-1 subject is given both the capability and the relation for a
; level-5 object, leaving the lattice as the only possible objector.
; =============================================================================
    mov edi, 1
    call usrauth_mls_enable

    mov edi, 1003
    mov esi, 1003
    mov edx, T_USER
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    mov [h_eve], eax
    mov edi, [h_eve]
    call usrauth_subject_get
    mov rbx, rax
    mov dword [rbx + usrauth_subject_t.label + usrauth_label_t.level], 1

    lea rbx, [obj_file]
    mov dword [rbx + usrauth_object_t.label + usrauth_label_t.level], 5

    mov edi, [h_eve]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    xor r8, r8
    call usrauth_cap_grant
    mov rdi, FILE_ID
    mov esi, USRAUTH_VERB_READ
    mov edx, [h_eve]
    xor rcx, rcx
    xor r8, r8
    call usrauth_relation_add

    mov edi, [h_eve]
    lea rsi, [obj_file]
    mov edx, USRAUTH_VERB_READ
    call usrauth_check
    cmp eax, USRAUTH_DENY_MLS
    je .t17
    or r15d, 32768
.t17:

; =============================================================================
; T18 — individual revocation kills one token and spares its siblings.
;
; This is the test the epoch bump cannot stand in for. Two tokens are minted
; for the same subject under the same epoch; revoking one by its issued_ns
; must deny that token and leave the other working. A revocation check keyed on
; the subject alone — or a frozen test clock giving both tokens the same
; issued_ns — would take out both, which is why the sibling is asserted too.
; =============================================================================
    mov edi, 1004
    mov esi, 1004
    mov edx, T_USER
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    mov [h_dave], eax               ; dave

    lea rdi, [tok_a]
    mov esi, [h_dave]
    mov rdx, 100000
    call usrauth_token_issue
    test eax, eax
    jnz .t18_fail

    lea rdi, [tok_b]
    mov esi, [h_dave]
    mov rdx, 100000
    call usrauth_token_issue
    test eax, eax
    jnz .t18_fail

    ; Distinct identities, or the test proves nothing.
    mov rax, [tok_a + usrauth_token_t.issued_ns]
    cmp rax, [tok_b + usrauth_token_t.issued_ns]
    je .t18_fail

    mov edi, [h_dave]
    mov rsi, rax                    ; tok_a issued_ns
    xor rdx, rdx                    ; retain indefinitely
    call usrauth_revoke_token
    test eax, eax
    jnz .t18_fail

    lea rdi, [tok_a]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_token_verify
    cmp eax, USRAUTH_DENY_REVOKED
    jne .t18_fail
    jmp .t18
.t18_fail:
    or r15d, 65536
.t18:
    lea rdi, [tok_b]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_token_verify
    test eax, eax
    jz .t19_start
    or r15d, 131072                 ; T18b: sibling was collateral damage
.t19_start:

; =============================================================================
; T19 — a forged tag is reported as forgery, not as a policy miss.
;
; Corrupting the tag itself, rather than the body, isolates authentication from
; every other check. The distinct code matters operationally: caveat denials
; are routine, forged tags are an attack, and an audit trail that conflates
; them cannot tell an administrator which one just happened.
; =============================================================================
    lea rdi, [tok_b]
    mov esi, [h_dave]
    mov rdx, 100000
    call usrauth_token_issue

    lea rbx, [tok_b]
    xor byte [rbx + usrauth_token_t.tag], 0x01

    lea rdi, [tok_b]
    mov rsi, FILE_ID
    mov edx, USRAUTH_CLASS_FILE
    mov ecx, USRAUTH_VERB_READ
    call usrauth_token_verify
    cmp eax, USRAUTH_DENY_FORGED
    je .t19
    or r15d, 262144
.t19:

; =============================================================================
; T20 — pruning reclaims revocation entries whose tokens have expired anyway.
;
; The set is bounded, so entries that can no longer matter must be released or
; the bound is reached by accumulation alone. An entry naming an already-dead
; token adds nothing: the token's own expiry caveat already rejects it.
; =============================================================================
    mov edi, [h_dave]
    mov rsi, 0x1234                 ; some token identity
    mov rdx, 1                      ; prune deadline far behind the clock
    call usrauth_revoke_token
    test eax, eax
    jnz .t20_fail

    call usrauth_revoke_prune
    test rax, rax
    jz .t20_fail

    ; And the indefinitely-retained T18 entry must have survived the prune.
    mov edi, [h_dave]
    mov rsi, [tok_a + usrauth_token_t.issued_ns]
    call usrauth_revoke_check
    cmp eax, USRAUTH_DENY_REVOKED
    je .t20
.t20_fail:
    or r15d, 524288
.t20:

; =============================================================================
; T21 — a lapsed grant cannot be renewed back to life.
;
; Carol's grant expired in T12. Renewal must refuse it, because a deadline that
; can be pushed forward from the far side is not a deadline: anyone holding a
; stale reference could keep the grant alive forever and it would never end.
; =============================================================================
    mov rdi, FILE_ID
    mov esi, r12d                   ; carol, whose grant lapsed in T12
    mov rdx, 9000000                ; well ahead of the harness clock
    call usrauth_ttl_renew
    cmp rax, USRAUTH_DENY_EXPIRED
    je .t21
    or r15d, 1048576
.t21:
    ; And the grant is still dead afterwards — a refused renewal must not have
    ; quietly moved the deadline anyway.
    ;
    ; L4 is queried directly rather than through usrauth_check. By this point
    ; T17 has enabled MLS and raised obj_file to level 5, so the full stack
    ; would deny at L5 before policy is ever consulted, and the test would pass
    ; without the deadline having been examined at all.
    mov edi, r12d                   ; carol
    mov rsi, FILE_ID
    mov edx, USRAUTH_VERB_READ
    call usrauth_policy_check
    cmp eax, USRAUTH_DENY_POLICY
    je .t22_start
    or r15d, 2097152
.t22_start:

; =============================================================================
; T22 — renewal of a LIVE grant extends it, clamped to the cap.
;
; The mirror of T21: if renewal refused everything, T21 would pass for the
; wrong reason. A request far beyond the 24h cap must succeed but come back
; clamped, so no run of renewals can manufacture a permanent grant.
; =============================================================================
    mov edi, 1005
    mov esi, 1005
    mov edx, T_USER
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    mov [h_frank], eax

    mov rdi, FILE_ID
    mov esi, USRAUTH_VERB_READ
    mov edx, [h_frank]
    xor rcx, rcx
    mov r8, 8000000                 ; live: ahead of the clock
    call usrauth_relation_add

    mov rdi, FILE_ID
    mov esi, [h_frank]
    mov rdx, 0x7FFFFFFFFFFFFFF0     ; absurd request: must be clamped
    call usrauth_ttl_renew
    cmp rax, 8000000
    jbe .t22_fail                   ; Must have moved forward...
    mov rcx, 0x7FFFFFFFFFFFFFF0
    cmp rax, rcx
    jb .t22                         ; ...but nowhere near what was asked
.t22_fail:
    or r15d, 4194304
.t22:

; =============================================================================
; T23 — the sweep reclaims lapsed relations and nothing else.
;
; Carol's tuple is lapsed and must go; frank's was just renewed and must
; survive. The sweep is housekeeping, so the check that matters is that it
; never reaps a live grant.
; =============================================================================
    call usrauth_ttl_sweep
    test rax, rax
    jz .t23_fail                    ; T12 left at least one lapsed tuple

    ; Frank's tuple was renewed in T22 and must have survived. Again L4 is
    ; asked directly, so MLS cannot answer on policy's behalf.
    mov edi, [h_frank]
    mov rsi, FILE_ID
    mov edx, USRAUTH_VERB_READ
    call usrauth_policy_check
    test eax, eax
    jz .t23
.t23_fail:
    or r15d, 8388608
.t23:

    mov edi, r15d
    call usrauth_test_report
