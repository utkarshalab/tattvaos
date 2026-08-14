; =============================================================================
; Tattva OS — security/usrauth/token/revoke.asm
; =============================================================================
; L1 — Token Revocation.
;
; Implements:
;   - Bulk revocation by epoch (`usrauth_revoke_subject`)
;   - Individual revocation by token identity (`usrauth_revoke_token`)
;   - Revocation lookup and pruning (`usrauth_revoke_check`, `_prune`)
;
; Stateless bearer tokens have one well-known weakness: once issued they remain
; valid until they expire, with no obvious way to take one back. JWT
; deployments hit this constantly and usually answer it with either very short
; lifetimes or a database lookup on every request — the latter discarding the
; statelessness that motivated the design in the first place.
;
; Two mechanisms here, at different granularities:
;
;   EPOCH BUMP is the cheap one and covers the common case. Every token records
;   the subject epoch it was minted under, so incrementing that epoch
;   invalidates every outstanding token for the subject at once, in O(1), with
;   no need to enumerate or reach them. This is the right answer for logout,
;   credential change, privilege reduction and compromise.
;
;   REVOCATION SET handles the narrow case where one specific delegated token
;   must die while its siblings survive — a shared link withdrawn from a single
;   recipient. It costs a lookup, so it is bounded and deliberately small.
;
; Entries are pruned once the token they name would have expired anyway.
; Retaining them longer grows the set without bound while adding nothing: an
; expired token is already rejected by its own expiry caveat.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_REVOKE_MAX           64

struc usrauth_revoke_ent_t
    .subject_handle:    resd 1
    .active:            resd 1
    .issued_ns:         resq 1      ; Identifies the specific token
    .prune_after_ns:    resq 1      ; When this entry may be dropped
endstruc

section .data
align 64

global usrauth_revoke_list
usrauth_revoke_list:
    times USRAUTH_REVOKE_MAX * usrauth_revoke_ent_t_size db 0

usrauth_revoke_count:   dq 0
usrauth_revoke_hits:    dq 0

section .text

global usrauth_revoke_subject
global usrauth_revoke_token
global usrauth_revoke_check
global usrauth_revoke_prune

; -----------------------------------------------------------------------------
; usrauth_revoke_subject
;
; Invalidates every outstanding token for a subject by advancing its epoch.
;
; O(1) and complete — no token needs to be found, listed, or reached. This is
; the mechanism to reach for on logout, credential change, or compromise.
;
; Inputs:
;   EDI = Subject handle
;
; Returns:
;   RAX = New epoch, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_revoke_subject:
    jmp usrauth_subject_bump_epoch

; -----------------------------------------------------------------------------
; usrauth_revoke_token
;
; Revokes one specific token while leaving the subject other tokens valid.
;
; Inputs:
;   EDI = Subject handle
;   RSI = issued_ns of the token being revoked
;   RDX = Absolute time after which this entry may be pruned
;
; Returns:
;   EAX = 0 on success
; -----------------------------------------------------------------------------
align 32
usrauth_revoke_token:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi
    mov r13, rsi
    mov r14, rdx

    ; Reclaim dead entries before declaring the set full.
    call usrauth_revoke_prune

    ; Pruning only marks entries inactive; it cannot move the ones above them.
    ; So a reclaimed slot is recovered by SEARCHING for it, not by rewinding
    ; the count. Without this scan the high-water mark only ever rises and the
    ; set reaches its bound by accumulation even though most of it is dead.
    mov rcx, [usrauth_revoke_count]
    lea rbx, [usrauth_revoke_list]
.rt_scan:
    test rcx, rcx
    jz .rt_extend
    cmp dword [rbx + usrauth_revoke_ent_t.active], 0
    je .rt_fill                     ; Dead slot: reuse it in place
    add rbx, usrauth_revoke_ent_t_size
    dec rcx
    jmp .rt_scan

.rt_extend:
    mov rax, [usrauth_revoke_count]
    cmp rax, USRAUTH_REVOKE_MAX
    jae .rt_full

    mov rbx, rax
    imul rbx, usrauth_revoke_ent_t_size
    lea rcx, [usrauth_revoke_list]
    add rbx, rcx

    inc qword [usrauth_revoke_count]

.rt_fill:
    mov dword [rbx + usrauth_revoke_ent_t.subject_handle], r12d
    mov [rbx + usrauth_revoke_ent_t.issued_ns], r13
    mov [rbx + usrauth_revoke_ent_t.prune_after_ns], r14
    mov dword [rbx + usrauth_revoke_ent_t.active], 1

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.rt_full:
    ; Set exhausted: fall back to the epoch bump rather than silently failing
    ; to revoke. Over-revoking is safe; under-revoking is not.
    mov edi, r12d
    call usrauth_subject_bump_epoch

    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_revoke_check
;
; Tests whether a specific token has been individually revoked.
;
; Inputs:
;   EDI = Subject handle
;   RSI = issued_ns from the token
;
; Returns:
;   EAX = USRAUTH_DENY_REVOKED when revoked, 0 otherwise
; -----------------------------------------------------------------------------
align 32
usrauth_revoke_check:
    push rbx
    push r12
    push r13

    mov r12d, edi
    mov r13, rsi

    mov rcx, [usrauth_revoke_count]
    lea rbx, [usrauth_revoke_list]

.rc_loop:
    test rcx, rcx
    jz .rc_clear

    cmp dword [rbx + usrauth_revoke_ent_t.active], 0
    je .rc_next
    cmp dword [rbx + usrauth_revoke_ent_t.subject_handle], r12d
    jne .rc_next
    cmp [rbx + usrauth_revoke_ent_t.issued_ns], r13
    jne .rc_next

    inc qword [usrauth_revoke_hits]
    mov eax, USRAUTH_DENY_REVOKED
    pop r13
    pop r12
    pop rbx
    ret

.rc_next:
    add rbx, usrauth_revoke_ent_t_size
    dec rcx
    jmp .rc_loop

.rc_clear:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_revoke_prune
;
; Drops entries whose tokens would have expired anyway.
;
; Returns:
;   RAX = Entries reclaimed
; -----------------------------------------------------------------------------
align 32
usrauth_revoke_prune:
    push rbx
    push r12
    push r13

    call mono_get_nanos
    mov r13, rax

    xor r12, r12
    mov rcx, [usrauth_revoke_count]
    lea rbx, [usrauth_revoke_list]

.rp_loop:
    test rcx, rcx
    jz .rp_done

    cmp dword [rbx + usrauth_revoke_ent_t.active], 0
    je .rp_next

    mov rax, [rbx + usrauth_revoke_ent_t.prune_after_ns]
    test rax, rax
    jz .rp_next                     ; No prune time: retain indefinitely
    cmp r13, rax
    jb .rp_next

    mov dword [rbx + usrauth_revoke_ent_t.active], 0
    inc r12

.rp_next:
    add rbx, usrauth_revoke_ent_t_size
    dec rcx
    jmp .rp_loop

.rp_done:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret
