%ifndef GUARD_SECURITY_USRAUTH_POLICY_TTL_ASM
%define GUARD_SECURITY_USRAUTH_POLICY_TTL_ASM
; =============================================================================
; Tattva OS — security/usrauth/policy/ttl.asm
; =============================================================================
; L4 — Time-Bounded Grants.
;
; Implements:
;   - Liveness predicate (`usrauth_ttl_live`)
;   - Bounded renewal (`usrauth_ttl_renew`)
;   - Expiry sweep (`usrauth_ttl_sweep`)
;   - Next-deadline query (`usrauth_ttl_next_expiry`)
;
; Expiry is CHECKED on the read path, in the policy walk, so an access is never
; granted by a lapsed tuple regardless of whether anything has swept yet. That
; makes the sweep here a housekeeping operation rather than a security one: it
; reclaims table slots and keeps the walk short. Correctness must never depend
; on it having run, because a sweep that is late, descheduled, or never called
; would otherwise become a silent grant of expired authority.
;
; RENEWAL CANNOT RESURRECT. Once a grant has lapsed it is gone, and extending
; it is not renewal but a fresh grant that must go through `usrauth_relation_add`
; and be authorised as such. Allowing an expired tuple to be revived would make
; the deadline advisory: an attacker holding a stale reference could keep
; pushing it forward forever, and the grant would never actually end.
;
; RENEWAL IS CAPPED. Each extension is clamped to USRAUTH_TTL_MAX_EXTENSION
; from the current time, so no sequence of renewals produces an effectively
; permanent grant by accumulation. Permanence remains available, but only by
; stating it explicitly at creation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

; Longest window any single renewal may open, measured from now: 24 hours.
%define USRAUTH_TTL_MAX_EXTENSION    86400000000000

section .data
align 8

usrauth_ttl_renewals:    dq 0
usrauth_ttl_clamped:     dq 0       ; Renewals truncated to the cap
usrauth_ttl_swept:       dq 0

section .text

global usrauth_ttl_live
global usrauth_ttl_renew
global usrauth_ttl_sweep
global usrauth_ttl_next_expiry
global usrauth_ttl_stats

; -----------------------------------------------------------------------------
; usrauth_ttl_live
;
; The liveness predicate in callable form, for paths where the cost of a call
; is irrelevant. The hot path uses the USRAUTH_JMP_IF_LAPSED macro instead;
; both derive from the same rule so they cannot disagree.
;
; Inputs:
;   RDI = Deadline in ns (0 = permanent)
;   RSI = Current time in ns
;
; Returns:
;   EAX = 1 when still live, 0 when lapsed
; -----------------------------------------------------------------------------
align 32
usrauth_ttl_live:
    test rdi, rdi
    jz .tl_live                     ; Permanent
    cmp rsi, rdi
    jae .tl_lapsed

.tl_live:
    mov eax, 1
    ret

.tl_lapsed:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usrauth_ttl_renew
;
; Extends a live grant's deadline, clamped to the renewal cap.
;
; A permanent grant is left alone rather than being given a deadline: renewal
; is for extending authority, and quietly converting permanence into a 24-hour
; window would revoke access nobody asked to revoke.
;
; Inputs:
;   RDI = Object id
;   ESI = Subject handle
;   RDX = Requested new absolute deadline in ns
;
; Returns:
;   RAX = The deadline actually set, or USRAUTH_DENY_INVALID when no live
;         matching grant exists, or USRAUTH_DENY_EXPIRED when it has lapsed
; -----------------------------------------------------------------------------
align 32
usrauth_ttl_renew:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; Object
    mov r13d, esi                   ; Subject
    mov r14, rdx                    ; Requested deadline

    call mono_get_nanos
    mov r15, rax                    ; Now

    mov rcx, [usrauth_relation_count]
    lea rbx, [usrauth_relations]

.tr_find:
    test rcx, rcx
    jz .tr_missing

    cmp dword [rbx + usrauth_relation_t.active], 0
    je .tr_next
    cmp [rbx + usrauth_relation_t.object_id], r12
    jne .tr_next
    cmp dword [rbx + usrauth_relation_t.subject_handle], r13d
    je .tr_found

.tr_next:
    add rbx, usrauth_relation_t_size
    dec rcx
    jmp .tr_find

.tr_found:
    mov rax, [rbx + usrauth_relation_t.expires_ns]
    test rax, rax
    jz .tr_permanent                ; Already unbounded: nothing to extend

    ; A lapsed grant is not renewable. Re-granting is a separate, authorised
    ; act; letting it happen here would make every deadline advisory.
    cmp r15, rax
    jae .tr_lapsed

    ; Clamp to now + max extension.
    mov rcx, USRAUTH_TTL_MAX_EXTENSION
    add rcx, r15
    jc .tr_clamp                    ; Overflowed the clock: cap it
    cmp r14, rcx
    jbe .tr_set

.tr_clamp:
    mov r14, rcx
    inc qword [usrauth_ttl_clamped]

.tr_set:
    ; Never move a deadline backwards here. Shortening a grant is revocation,
    ; and revocation must go through the path that invalidates the cache.
    cmp r14, rax
    jbe .tr_unchanged

    mov [rbx + usrauth_relation_t.expires_ns], r14
    inc qword [usrauth_ttl_renewals]

    ; Cached verdicts were computed under the old deadline.
    call usrauth_policy_bump_epoch

    mov rax, r14
    jmp .tr_return

.tr_unchanged:
    mov rax, [rbx + usrauth_relation_t.expires_ns]
    jmp .tr_return

.tr_permanent:
    xor eax, eax                    ; Still permanent
    jmp .tr_return

    ; These return in RAX alongside genuine 64-bit deadlines, so they must be
    ; written as full-width negatives. `mov eax, -6` zero-extends and yields
    ; 0x00000000FFFFFFFA, which no caller comparing RAX against -6 will match —
    ; the error would read as an enormous valid deadline instead of a refusal.
.tr_lapsed:
    mov rax, USRAUTH_DENY_EXPIRED
    jmp .tr_return

.tr_missing:
    mov rax, USRAUTH_DENY_INVALID

.tr_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_ttl_sweep
;
; Deactivates every lapsed relation, reclaiming its slot.
;
; Purely housekeeping — the policy walk already refuses lapsed tuples, so
; skipping the sweep costs table space and walk time but never authority.
;
; Returns:
;   RAX = Relations reclaimed
; -----------------------------------------------------------------------------
align 32
usrauth_ttl_sweep:
    push rbx
    push r12
    push r13

    call mono_get_nanos
    mov r13, rax

    xor r12, r12
    mov rcx, [usrauth_relation_count]
    lea rbx, [usrauth_relations]

.ts_loop:
    test rcx, rcx
    jz .ts_done

    cmp dword [rbx + usrauth_relation_t.active], 0
    je .ts_next

    mov rax, [rbx + usrauth_relation_t.expires_ns]
    USRAUTH_JMP_IF_LAPSED r13, rax, .ts_reap
    jmp .ts_next

.ts_reap:
    mov dword [rbx + usrauth_relation_t.active], 0
    inc r12

.ts_next:
    add rbx, usrauth_relation_t_size
    dec rcx
    jmp .ts_loop

.ts_done:
    test r12, r12
    jz .ts_return

    add [usrauth_ttl_swept], r12
    ; Reaping changes what the table says; memoised verdicts must not survive.
    call usrauth_policy_bump_epoch

.ts_return:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_ttl_next_expiry
;
; Earliest deadline still ahead of the clock.
;
; Lets a caller schedule one sweep for the moment it becomes useful instead of
; polling. Permanent grants are ignored — they have no deadline to wait for.
;
; Returns:
;   RAX = Earliest future deadline in ns, or 0 when nothing is pending
; -----------------------------------------------------------------------------
align 32
usrauth_ttl_next_expiry:
    push rbx
    push r12
    push r13

    call mono_get_nanos
    mov r13, rax

    xor r12, r12                    ; Best so far (0 = none)
    mov rcx, [usrauth_relation_count]
    lea rbx, [usrauth_relations]

.tn_loop:
    test rcx, rcx
    jz .tn_done

    cmp dword [rbx + usrauth_relation_t.active], 0
    je .tn_next

    mov rax, [rbx + usrauth_relation_t.expires_ns]
    test rax, rax
    jz .tn_next                     ; Permanent
    cmp rax, r13
    jbe .tn_next                    ; Already lapsed: the sweep, not the wait

    test r12, r12
    jz .tn_take
    cmp rax, r12
    jae .tn_next

.tn_take:
    mov r12, rax

.tn_next:
    add rbx, usrauth_relation_t_size
    dec rcx
    jmp .tn_loop

.tn_done:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_ttl_stats
;
; Inputs:
;   RDI = Buffer for three quadwords: renewals, clamped, swept
; -----------------------------------------------------------------------------
align 32
usrauth_ttl_stats:
    test rdi, rdi
    jz .tst_done
    mov rax, [usrauth_ttl_renewals]
    mov [rdi], rax
    mov rax, [usrauth_ttl_clamped]
    mov [rdi + 8], rax
    mov rax, [usrauth_ttl_swept]
    mov [rdi + 16], rax
.tst_done:
    ret

%endif ; GUARD_SECURITY_USRAUTH_POLICY_TTL_ASM
