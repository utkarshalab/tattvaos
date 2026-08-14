; =============================================================================
; Tattva OS — security/usrauth/subject/transition.asm
; =============================================================================
; L2 — Domain Transition Rules.
;
; Implements:
;   - Transition rule registration (`usrauth_transition_add`)
;   - Permitted-transition lookup (`usrauth_transition_allowed`)
;   - Applying a transition to a subject (`usrauth_transition_exec`)
;
; A domain transition is how a subject changes its enforcement type — the
; SELinux model, where running a particular binary moves a process from one
; domain to another. It is the only way a subject's type may ever change.
;
; THREE RULES, EACH OF WHICH IS A HOLE IF DROPPED:
;
;   1. Transitions must be EXPLICITLY declared. Absence is denial, exactly as
;      in type enforcement. An implicit or default transition means an
;      attacker who can execute the right object picks their own domain.
;
;   2. Integrity may never RISE across a transition. A low-integrity subject
;      executing a high-integrity binary does not become trusted — otherwise
;      every setuid-style escalation returns through the back door.
;
;   3. Capabilities do NOT survive. The new domain starts from what its rules
;      grant it, not from what the old domain happened to hold. Carrying them
;      over would let a subject launder authority across a boundary that
;      exists precisely to contain it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_MAX_TRANSITIONS      128

struc usrauth_transition_t
    .from_type:         resd 1      ; Current subject type
    .via_type:          resd 1      ; Type of the object being executed
    .to_type:           resd 1      ; Resulting subject type
    .active:            resd 1
endstruc

section .data
align 64

global usrauth_transitions
usrauth_transitions:
    times USRAUTH_MAX_TRANSITIONS * usrauth_transition_t_size db 0

usrauth_transition_count:   dq 0
usrauth_transitions_done:   dq 0
usrauth_transitions_denied: dq 0

section .text

global usrauth_transition_add
global usrauth_transition_allowed
global usrauth_transition_exec

; -----------------------------------------------------------------------------
; usrauth_transition_add
;
; Declares that a subject of `from_type` executing an object of `via_type`
; enters `to_type`.
;
; Inputs:
;   EDI = from_type
;   ESI = via_type
;   EDX = to_type
;
; Returns:
;   EAX = Rule index, or USRAUTH_DENY_INVALID when the table is full
; -----------------------------------------------------------------------------
align 32
usrauth_transition_add:
    push rbx
    push r12

    ; Capture arguments before RCX/RBX are reused as scratch below.
    mov r12d, edx

    mov rax, [usrauth_transition_count]
    cmp rax, USRAUTH_MAX_TRANSITIONS
    jae .ta_full

    mov rbx, rax
    imul rbx, usrauth_transition_t_size
    lea rcx, [usrauth_transitions]
    add rbx, rcx

    mov dword [rbx + usrauth_transition_t.from_type], edi
    mov dword [rbx + usrauth_transition_t.via_type], esi
    mov dword [rbx + usrauth_transition_t.to_type], r12d
    mov dword [rbx + usrauth_transition_t.active], 1

    inc qword [usrauth_transition_count]

    pop r12
    pop rbx
    ret

.ta_full:
    mov eax, USRAUTH_DENY_INVALID
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_transition_allowed
;
; Looks up the resulting type for a transition.
;
; Inputs:
;   EDI = from_type
;   ESI = via_type
;
; Returns:
;   EAX = Resulting type, or USRAUTH_DENY_MANDATORY when no rule permits it
; -----------------------------------------------------------------------------
align 32
usrauth_transition_allowed:
    push rbx

    mov rcx, [usrauth_transition_count]
    lea rbx, [usrauth_transitions]

.tl_loop:
    test rcx, rcx
    jz .tl_denied

    cmp dword [rbx + usrauth_transition_t.active], 0
    je .tl_next
    cmp dword [rbx + usrauth_transition_t.from_type], edi
    jne .tl_next
    cmp dword [rbx + usrauth_transition_t.via_type], esi
    jne .tl_next

    mov eax, dword [rbx + usrauth_transition_t.to_type]
    pop rbx
    ret

.tl_next:
    add rbx, usrauth_transition_t_size
    dec rcx
    jmp .tl_loop

.tl_denied:
    ; No declared rule: absence is denial.
    inc qword [usrauth_transitions_denied]
    mov eax, USRAUTH_DENY_MANDATORY
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_transition_exec
;
; Moves a subject into a new domain.
;
; Capabilities are dropped and the token epoch is bumped, so anything minted
; against the old domain stops validating. Integrity is never raised.
;
; Inputs:
;   EDI = Subject handle
;   ESI = via_type (the type of the object being executed)
;   EDX = Integrity level of that object
;
; Returns:
;   EAX = New subject type, or a negative USRAUTH_DENY_* code
; -----------------------------------------------------------------------------
align 32
usrauth_transition_exec:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi                   ; Subject handle
    mov r13d, esi                   ; via_type
    mov r14d, edx                   ; Object integrity

    call usrauth_subject_get
    test rax, rax
    jz .te_inval
    mov rbx, rax

    ; Is this transition declared?
    mov edi, dword [rbx + usrauth_subject_t.type_id]
    mov esi, r13d
    call usrauth_transition_allowed
    test eax, eax
    js .te_denied

    mov r13d, eax                   ; Resulting type

    ; Integrity may only stay level or drop. Executing a more-trusted object
    ; must not make an untrusted subject trusted.
    mov eax, dword [rbx + usrauth_subject_t.integrity]
    cmp r14d, eax
    jae .te_keep_integrity
    mov dword [rbx + usrauth_subject_t.integrity], r14d

.te_keep_integrity:
    mov dword [rbx + usrauth_subject_t.type_id], r13d

    ; Authority does not cross the boundary.
    mov dword [rbx + usrauth_subject_t.cap_count], 0

    ; Tokens minted under the old domain must stop validating.
    inc qword [rbx + usrauth_subject_t.token_epoch]

    inc qword [usrauth_transitions_done]

    mov eax, r13d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.te_denied:
    mov eax, USRAUTH_DENY_MANDATORY
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.te_inval:
    mov eax, USRAUTH_DENY_INVALID
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
