%ifndef GUARD_SECURITY_USRAUTH_CAPABILITY_CAP_ASM
%define GUARD_SECURITY_USRAUTH_CAPABILITY_CAP_ASM
; =============================================================================
; Tattva OS — security/usrauth/capability/cap.asm
; =============================================================================
; L3 — Capability Table: Unforgeable Authority References.
;
; Implements:
;   - Capability grant and revocation (`usrauth_cap_grant`, `_revoke`)
;   - Lookup honouring expiry (`usrauth_cap_find`)
;   - Rights checking (`usrauth_cap_check`)
;   - Attenuating delegation (`usrauth_cap_delegate`)
;
; A capability is authority that is HELD, not authority looked up by name at
; the moment of use. That distinction is what makes the confused deputy
; structurally impossible rather than merely guarded against: a subject cannot
; exercise authority it was never handed, even when a name-based check against
; its ambient identity would have said yes.
;
; THE ATTENUATION RULE — the single invariant this layer rests on:
;
;   Delegation may only NARROW. Rights are intersected with the granter's, and
;   expiry is clamped to the earlier of the two bounds. A subject can never
;   hand out more than it holds, nor extend a deadline it is itself subject to.
;
; If `usrauth_cap_delegate` is ever relaxed to allow amplification, every other
; guarantee in this layer becomes decorative — a subject could mint itself
; arbitrary authority by delegating to itself.
;
; Capability storage lives inside uguard's subject records (see
; subject/table.asm), so handles remain opaque and capabilities cannot be
; forged by writing to memory a subject controls.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .text

global usrauth_cap_grant
global usrauth_cap_find
global usrauth_cap_check
global usrauth_cap_delegate
global usrauth_cap_revoke

; -----------------------------------------------------------------------------
; usrauth_cap_grant
;
; Installs a capability on a subject.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Object class
;   ECX = Rights bitmask
;   R8  = Absolute expiry in ns, or 0 for none
;
; Returns:
;   EAX = Capability index, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_cap_grant:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                    ; Object id
    mov r13d, edx                   ; Class
    mov r14d, ecx                   ; Rights
    mov r15, r8                     ; Expiry

    and r14d, USRAUTH_VERB_MASK      ; Never store undefined verb bits

    call usrauth_subject_get
    test rax, rax
    jz .cg_inval
    mov rbx, rax

    mov ecx, dword [rbx + usrauth_subject_t.cap_count]
    cmp ecx, USRAUTH_MAX_CAPS_PER_SUBJECT
    jae .cg_inval

    mov rax, rcx
    imul rax, usrauth_cap_t_size
    lea rdi, [rbx + usrauth_subject_t.caps]
    add rdi, rax

    mov [rdi + usrauth_cap_t.object_id], r12
    mov dword [rdi + usrauth_cap_t.object_class], r13d
    mov dword [rdi + usrauth_cap_t.rights], r14d
    mov [rdi + usrauth_cap_t.expires_ns], r15
    mov dword [rdi + usrauth_cap_t.flags], 0

    inc dword [rbx + usrauth_subject_t.cap_count]
    inc qword [usrauth_cap_grants]

    mov eax, ecx
    jmp .cg_return

.cg_inval:
    mov eax, USRAUTH_DENY_INVALID

.cg_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_cap_find
;
; Locates a live capability for an object.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Object class
;
; Returns:
;   RAX = Capability pointer, or 0
; -----------------------------------------------------------------------------
align 32
usrauth_cap_find:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    mov r13d, edx

    call usrauth_subject_get
    test rax, rax
    jz .cf_missing
    mov rbx, rax

    ; Fetch time once; a capability that expires mid-scan must not be
    ; accepted by one iteration and rejected by the next.
    call mono_get_nanos
    mov r15, rax

    mov r14d, dword [rbx + usrauth_subject_t.cap_count]
    xor rcx, rcx

.cf_loop:
    cmp ecx, r14d
    jae .cf_missing

    mov rax, rcx
    imul rax, usrauth_cap_t_size
    lea rdi, [rbx + usrauth_subject_t.caps]
    add rdi, rax

    cmp [rdi + usrauth_cap_t.object_id], r12
    jne .cf_next
    cmp dword [rdi + usrauth_cap_t.object_class], r13d
    jne .cf_next

    ; Expired capabilities are invisible, not merely unusable.
    mov rax, [rdi + usrauth_cap_t.expires_ns]
    test rax, rax
    jz .cf_found
    cmp r15, rax
    jae .cf_next

.cf_found:
    mov rax, rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.cf_next:
    inc ecx
    jmp .cf_loop

.cf_missing:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_cap_check
;
; Confirms the subject HOLDS authority covering the requested verbs.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Object class
;   ECX = Requested verb bitmask
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_CAPABILITY
; -----------------------------------------------------------------------------
align 32
usrauth_cap_check:
    push rbx

    mov ebx, ecx                    ; Requested verbs
    call usrauth_cap_find
    test rax, rax
    jz .cc_deny

    ; Every requested bit must be present.
    mov ecx, dword [rax + usrauth_cap_t.rights]
    mov eax, ecx
    and eax, ebx
    cmp eax, ebx
    jne .cc_deny

    xor eax, eax
    pop rbx
    ret

.cc_deny:
    inc qword [usrauth_cap_denials]
    mov eax, USRAUTH_DENY_CAPABILITY
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_cap_delegate
;
; Passes a capability to another subject, attenuated.
;
; ATTENUATE ONLY. The delegated rights are intersected with the holder's, and
; the expiry is clamped to the earlier of the two. A subject can never hand out
; more than it holds, nor extend a deadline it is itself bound by. Relaxing
; either clamp defeats the entire capability model.
;
; Inputs:
;   EDI = Granting subject handle
;   ESI = Receiving subject handle
;   RDX = Object id
;   ECX = Object class
;   R8D = Requested rights for the delegate
;   R9  = Requested expiry, or 0
;
; Returns:
;   EAX = Capability index on the receiver, or USRAUTH_DENY_CAPABILITY
; -----------------------------------------------------------------------------
align 32
usrauth_cap_delegate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov [rsp], rsi                  ; Receiver
    mov r12, rdx                    ; Object
    mov r13d, ecx                   ; Class
    mov r14d, r8d                   ; Requested rights
    mov r15, r9                     ; Requested expiry

    ; The granter must actually hold it.
    mov rsi, r12
    mov edx, r13d
    call usrauth_cap_find
    test rax, rax
    jz .cd_deny
    mov rbx, rax

    ; Rights: intersect, never widen.
    mov ecx, dword [rbx + usrauth_cap_t.rights]
    and r14d, ecx

    ; A delegation conferring nothing is an error, not a silent no-op.
    test r14d, r14d
    jz .cd_deny

    ; Expiry: take the earlier bound. Treat 0 as "unbounded" on both sides.
    mov rax, [rbx + usrauth_cap_t.expires_ns]
    test rax, rax
    jz .cd_use_requested        ; Holder unbounded: requested stands
    test r15, r15
    jz .cd_use_holder           ; Requested unbounded: clamp to holder
    cmp r15, rax
    jbe .cd_use_requested       ; Requested already earlier
.cd_use_holder:
    mov r15, rax

.cd_use_requested:
    mov edi, dword [rsp]            ; Receiver handle
    mov rsi, r12
    mov edx, r13d
    mov ecx, r14d
    mov r8, r15
    call usrauth_cap_grant
    jmp .cd_return

.cd_deny:
    inc qword [usrauth_cap_denials]
    mov eax, USRAUTH_DENY_CAPABILITY

.cd_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_cap_revoke
;
; Removes a capability by compacting the list.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Object class
;
; Returns:
;   EAX = USRAUTH_ALLOW, or USRAUTH_DENY_INVALID when not held
; -----------------------------------------------------------------------------
align 32
usrauth_cap_revoke:
    push rbx
    push r12
    push r13

    mov r13d, edi
    call usrauth_cap_find
    test rax, rax
    jz .cr_inval
    mov rbx, rax                    ; Capability to remove

    mov edi, r13d
    call usrauth_subject_get
    test rax, rax
    jz .cr_inval
    mov r12, rax

    ; Move the last entry into the hole and shrink.
    mov ecx, dword [r12 + usrauth_subject_t.cap_count]
    dec ecx
    mov rax, rcx
    imul rax, usrauth_cap_t_size
    lea rsi, [r12 + usrauth_subject_t.caps]
    add rsi, rax                    ; Last capability

    cmp rsi, rbx
    je .cr_shrink                   ; Already the last one

    mov rdi, rbx
    mov rcx, usrauth_cap_t_size
    rep movsb

.cr_shrink:
    dec dword [r12 + usrauth_subject_t.cap_count]

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.cr_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r13
    pop r12
    pop rbx
    ret


%endif ; GUARD_SECURITY_USRAUTH_CAPABILITY_CAP_ASM
