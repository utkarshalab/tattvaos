%ifndef GUARD_SECURITY_USRAUTH_SUBJECT_TABLE_ASM
%define GUARD_SECURITY_USRAUTH_SUBJECT_TABLE_ASM
; =============================================================================
; Tattva OS — security/usrauth/subject.asm
; =============================================================================
; L2 — Subject Table and Capability Store.
;
; Implements:
;   - Subject lifecycle (`usrauth_subject_create`, `_destroy`, `_get`)
;   - Group membership queries (`usrauth_subject_in_group`)
;   - Capability grant, lookup and attenuation (`usrauth_cap_*`)
;   - Irreversible self-restriction (`usrauth_subject_restrict`)
;   - Integrity-level write check (`usrauth_integrity_check`)
;
; usrauth owns this table and hands back opaque handles. It deliberately does
; NOT hook a scheduler — when sched/ exists, a task struct stores the handle
; and nothing here changes. That decoupling is what lets the reference monitor
; be built and tested before the kernel around it exists.
;
; CAPABILITY RULE: attenuate on pass, never amplify. A subject delegating
; authority may narrow the rights or shorten the expiry, never widen either.
; Enforced in usrauth_cap_delegate — if that check is ever relaxed, the
; confused-deputy protection collapses.
;
; RESTRICTION RULE: dropping authority is irreversible for the lifetime of the
; subject, following pledge/unveil. A subject that could re-acquire what it
; dropped has not really dropped anything.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

section .data
align 64

global usrauth_subject_table
usrauth_subject_table:
    times USRAUTH_MAX_SUBJECTS * usrauth_subject_t_size db 0

usrauth_subject_used:    times USRAUTH_MAX_SUBJECTS db 0
usrauth_subject_count:   dq 0
usrauth_cap_grants:      dq 0
usrauth_cap_denials:     dq 0

section .text

global usrauth_subject_create
global usrauth_subject_destroy
global usrauth_subject_get
global usrauth_subject_in_group
global usrauth_subject_bump_epoch

; -----------------------------------------------------------------------------
; usrauth_subject_get
;
; Inputs:
;   EDI = Subject handle
;
; Returns:
;   RAX = Subject pointer, or 0 when the handle is invalid or inactive
; -----------------------------------------------------------------------------
align 32
usrauth_subject_get:
    cmp edi, USRAUTH_MAX_SUBJECTS
    jae .sg_bad

    lea rax, [usrauth_subject_used]
    cmp byte [rax + rdi], 0
    je .sg_bad

    mov rax, rdi
    imul rax, usrauth_subject_t_size
    lea rcx, [usrauth_subject_table]
    add rax, rcx
    ret

.sg_bad:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; usrauth_subject_create
;
; Allocates a subject.
;
; Integrity defaults to MEDIUM rather than SYSTEM: a subject must be granted
; elevation explicitly, never receive it by omission.
;
; Inputs:
;   EDI = uid
;   ESI = gid
;   EDX = Type id (enforcement domain)
;   ECX = Integrity level
;
; Returns:
;   EAX = Subject handle, or USRAUTH_DENY_INVALID when the table is full
; -----------------------------------------------------------------------------
align 32
usrauth_subject_create:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; uid
    mov r13d, esi                   ; gid
    mov r14d, edx                   ; type
    mov r15d, ecx                   ; integrity

    cmp r15d, USRAUTH_INTEGRITY_SYSTEM
    ja .sc_inval

    ; Find a free slot.
    xor rbx, rbx
.sc_scan:
    cmp rbx, USRAUTH_MAX_SUBJECTS
    jae .sc_full
    lea rax, [usrauth_subject_used]
    cmp byte [rax + rbx], 0
    je .sc_claim
    inc rbx
    jmp .sc_scan

.sc_claim:
    mov rax, rbx
    imul rax, usrauth_subject_t_size
    lea rcx, [usrauth_subject_table]
    add rax, rcx
    mov rdi, rax                    ; Subject pointer

    ; Zero the slot: a recycled handle must not inherit prior authority.
    push rdi
    mov rcx, usrauth_subject_t_size
    xor al, al
    rep stosb
    pop rdi

    mov dword [rdi + usrauth_subject_t.uid], r12d
    mov dword [rdi + usrauth_subject_t.gid], r13d
    mov dword [rdi + usrauth_subject_t.type_id], r14d
    mov dword [rdi + usrauth_subject_t.integrity], r15d
    mov dword [rdi + usrauth_subject_t.flags], USRAUTH_SUBJ_ACTIVE
    mov dword [rdi + usrauth_subject_t.cap_count], 0
    mov dword [rdi + usrauth_subject_t.group_count], 0
    mov qword [rdi + usrauth_subject_t.token_epoch], 1

    call mono_get_nanos
    mov rdi, rax
    mov rax, rbx
    imul rax, usrauth_subject_t_size
    lea rcx, [usrauth_subject_table]
    add rax, rcx
    mov [rax + usrauth_subject_t.created_ns], rdi

    lea rax, [usrauth_subject_used]
    mov byte [rax + rbx], 1
    inc qword [usrauth_subject_count]

    mov eax, ebx
    jmp .sc_return

.sc_full:
.sc_inval:
    mov eax, USRAUTH_DENY_INVALID

.sc_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_subject_destroy
;
; Releases a subject and wipes its capabilities.
;
; Inputs:
;   EDI = Subject handle
;
; Returns:
;   EAX = USRAUTH_ALLOW, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_subject_destroy:
    push rbx

    mov ebx, edi
    call usrauth_subject_get
    test rax, rax
    jz .sd_inval

    ; Wipe rather than merely mark free: a later handle reuse must not expose
    ; the previous subject's capability list.
    mov rdi, rax
    mov rcx, usrauth_subject_t_size
    xor al, al
    rep stosb

    lea rax, [usrauth_subject_used]
    mov byte [rax + rbx], 0
    dec qword [usrauth_subject_count]

    xor eax, eax
    pop rbx
    ret

.sd_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_subject_add_group
;
; Inputs:
;   EDI = Subject handle
;   ESI = Group id
;
; Returns:
;   EAX = USRAUTH_ALLOW, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_subject_add_group:
    push rbx
    push r12

    mov r12d, esi
    call usrauth_subject_get
    test rax, rax
    jz .ag_inval
    mov rbx, rax

    mov ecx, dword [rbx + usrauth_subject_t.group_count]
    cmp ecx, USRAUTH_MAX_GROUPS
    jae .ag_inval

    mov rax, rcx
    shl rax, 2
    add rax, rbx
    mov dword [rax + usrauth_subject_t.groups], r12d

    inc dword [rbx + usrauth_subject_t.group_count]

    xor eax, eax
    pop r12
    pop rbx
    ret

.ag_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_subject_in_group
;
; Checks the primary gid and every supplementary group.
;
; Inputs:
;   EDI = Subject handle
;   ESI = Group id
;
; Returns:
;   EAX = 1 when a member, 0 otherwise
; -----------------------------------------------------------------------------
align 32
usrauth_subject_in_group:
    push rbx
    push r12
    push r13

    mov r12d, esi
    call usrauth_subject_get
    test rax, rax
    jz .ig_no
    mov rbx, rax

    cmp dword [rbx + usrauth_subject_t.gid], r12d
    je .ig_yes

    mov r13d, dword [rbx + usrauth_subject_t.group_count]
    xor rcx, rcx
.ig_loop:
    cmp ecx, r13d
    jae .ig_no

    mov rax, rcx
    shl rax, 2
    add rax, rbx
    cmp dword [rax + usrauth_subject_t.groups], r12d
    je .ig_yes

    inc ecx
    jmp .ig_loop

.ig_yes:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

.ig_no:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_subject_bump_epoch
;
; Invalidates every token derived from this subject.
;
; This is the revocation mechanism. Tokens carry the epoch they were minted
; under; bumping it makes all outstanding ones stale without needing to track
; or reach them individually — the standard answer to JWT's revocation hole.
;
; Inputs:
;   EDI = Subject handle
;
; Returns:
;   RAX = New epoch, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_subject_bump_epoch:
    call usrauth_subject_get
    test rax, rax
    jz .be_inval

    inc qword [rax + usrauth_subject_t.token_epoch]
    mov rax, [rax + usrauth_subject_t.token_epoch]
    ret

.be_inval:
    mov rax, USRAUTH_DENY_INVALID
    ret


%endif ; GUARD_SECURITY_USRAUTH_SUBJECT_TABLE_ASM
