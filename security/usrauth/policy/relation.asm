; =============================================================================
; Tattva OS — security/usrauth/policy.asm
; =============================================================================
; L4 — Relationship and Attribute Policy.
;
; Implements:
;   - Relation tuple store (`usrauth_relation_add`, `_remove`)
;   - Bounded relationship graph walk (`usrauth_policy_check`)
;   - Reverse enumeration for access review (`usrauth_policy_who_can`)
;   - Decision cache with epoch invalidation (`usrauth_policy_cache_*`)
;
; Relations are Zanzibar-shaped: object#relation@subject, with indirection
; through another object for group-style inheritance. The reason to prefer this
; over plain ACLs is that it answers BOTH directions — "who can reach X" and
; "what can A reach". An ACL answers only the first, which is why access
; reviews on ACL-only systems require scanning every object in the system.
;
; TIME-BOUNDED BY DEFAULT: every grant carries an expiry. Permanence is
; possible but must be stated explicitly (expires_ns = 0). Windows, Linux and
; macOS all default to permanent-until-revoked, which is exactly why stale
; access accumulates for years. Inverting the default is the single highest
; value difference in this layer.
;
; The graph walk is depth-capped. An unbounded walk over attacker-influenced
; relations is a denial of service, and a cycle is an infinite loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "security/usrauth/usrauth.inc"

%define USRAUTH_CACHE_SLOTS       256
%define USRAUTH_CACHE_MASK        (USRAUTH_CACHE_SLOTS - 1)

; A memoised decision. Keyed by subject/object/verb, valid only while the
; global policy epoch is unchanged.
struc usrauth_cache_ent_t
    .subject_handle:    resd 1
    .verb:              resd 1
    .object_id:         resq 1
    .epoch:             resq 1
    .verdict:           resd 1
    .valid:             resd 1
endstruc

section .data
align 64

global usrauth_relations
usrauth_relations:
    times USRAUTH_MAX_RELATIONS * usrauth_relation_t_size db 0

usrauth_relation_count:  dq 0
usrauth_policy_epoch:    dq 1        ; Bumped on any policy mutation

usrauth_cache:
    times USRAUTH_CACHE_SLOTS * usrauth_cache_ent_t_size db 0

usrauth_cache_hits:      dq 0
usrauth_cache_misses:    dq 0
usrauth_policy_denials:  dq 0

section .text

global usrauth_relation_add
global usrauth_relation_remove
global usrauth_policy_check
global usrauth_policy_who_can
global usrauth_policy_bump_epoch
global usrauth_policy_cache_lookup
global usrauth_policy_cache_store
global usrauth_policy_stats

; -----------------------------------------------------------------------------
; usrauth_policy_bump_epoch
;
; Invalidates the entire decision cache in O(1) by moving the epoch forward.
; Sweeping the cache instead would be O(slots) and racy against concurrent
; lookups.
;
; Returns:
;   RAX = New epoch
; -----------------------------------------------------------------------------
align 32
usrauth_policy_bump_epoch:
    inc qword [usrauth_policy_epoch]
    mov rax, [usrauth_policy_epoch]
    ret

; -----------------------------------------------------------------------------
; usrauth_relation_add
;
; Records object#relation@subject.
;
; Inputs:
;   RDI = Object id
;   ESI = Relation verb bitmask
;   EDX = Subject handle, or USRAUTH_INVALID_HANDLE when using via_object
;   RCX = via_object for indirect grants, or 0
;   R8  = Absolute expiry in ns, or 0 for permanent
;
; Returns:
;   EAX = Relation index, or USRAUTH_DENY_INVALID
; -----------------------------------------------------------------------------
align 32
usrauth_relation_add:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; Object
    mov r13d, esi                   ; Relation verbs
    mov r14d, edx                   ; Subject
    mov r15, rcx                    ; via_object

    and r13d, USRAUTH_VERB_MASK
    test r13d, r13d
    jz .ra_inval                    ; A relation conferring nothing is a bug

    ; Must name either a subject or an indirection, not neither.
    cmp r14d, USRAUTH_INVALID_HANDLE
    jne .ra_have_target
    test r15, r15
    jz .ra_inval

.ra_have_target:
    mov rax, [usrauth_relation_count]
    cmp rax, USRAUTH_MAX_RELATIONS
    jae .ra_inval

    mov rbx, rax
    imul rbx, usrauth_relation_t_size
    lea rcx, [usrauth_relations]
    add rbx, rcx

    mov [rbx + usrauth_relation_t.object_id], r12
    mov dword [rbx + usrauth_relation_t.relation], r13d
    mov dword [rbx + usrauth_relation_t.subject_handle], r14d
    mov [rbx + usrauth_relation_t.via_object], r15
    mov [rbx + usrauth_relation_t.expires_ns], r8
    mov dword [rbx + usrauth_relation_t.flags], 0
    mov dword [rbx + usrauth_relation_t.active], 1

    inc qword [usrauth_relation_count]
    call usrauth_policy_bump_epoch   ; Cached decisions are now stale

    mov rax, [usrauth_relation_count]
    dec rax
    jmp .ra_return

.ra_inval:
    mov eax, USRAUTH_DENY_INVALID

.ra_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_relation_remove
;
; Deactivates every relation matching object + subject.
;
; Inputs:
;   RDI = Object id
;   ESI = Subject handle
;
; Returns:
;   EAX = Number deactivated
; -----------------------------------------------------------------------------
align 32
usrauth_relation_remove:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13d, esi
    xor r14d, r14d

    mov rcx, [usrauth_relation_count]
    lea rbx, [usrauth_relations]

.rr_loop:
    test rcx, rcx
    jz .rr_done

    cmp dword [rbx + usrauth_relation_t.active], 0
    je .rr_next
    cmp [rbx + usrauth_relation_t.object_id], r12
    jne .rr_next
    cmp dword [rbx + usrauth_relation_t.subject_handle], r13d
    jne .rr_next

    mov dword [rbx + usrauth_relation_t.active], 0
    inc r14d

.rr_next:
    add rbx, usrauth_relation_t_size
    dec rcx
    jmp .rr_loop

.rr_done:
    test r14d, r14d
    jz .rr_return
    call usrauth_policy_bump_epoch

.rr_return:
    mov eax, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_policy_cache_lookup
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Verb bitmask
;
; Returns:
;   EAX = Cached verdict, or 1 when there is no valid entry
;         (1 is not a verdict — verdicts are 0 or negative)
; -----------------------------------------------------------------------------
align 32
usrauth_policy_cache_lookup:
    push rbx

    ; Mix the key; sequential object ids would otherwise cluster.
    mov rax, rsi
    mov rcx, 0x9E3779B97F4A7C15
    imul rax, rcx
    xor eax, edi
    xor eax, edx
    and rax, USRAUTH_CACHE_MASK

    imul rax, usrauth_cache_ent_t_size
    lea rbx, [usrauth_cache]
    add rbx, rax

    cmp dword [rbx + usrauth_cache_ent_t.valid], 0
    je .cl_miss

    mov rax, [usrauth_policy_epoch]
    cmp [rbx + usrauth_cache_ent_t.epoch], rax
    jne .cl_miss                    ; Stale: policy changed since

    cmp dword [rbx + usrauth_cache_ent_t.subject_handle], edi
    jne .cl_miss
    cmp [rbx + usrauth_cache_ent_t.object_id], rsi
    jne .cl_miss
    cmp dword [rbx + usrauth_cache_ent_t.verb], edx
    jne .cl_miss

    inc qword [usrauth_cache_hits]
    mov eax, dword [rbx + usrauth_cache_ent_t.verdict]
    pop rbx
    ret

.cl_miss:
    inc qword [usrauth_cache_misses]
    mov eax, 1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_policy_cache_store
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Verb bitmask
;   ECX = Verdict
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_policy_cache_store:
    push rbx

    mov rax, rsi
    mov r8, 0x9E3779B97F4A7C15
    imul rax, r8
    xor eax, edi
    xor eax, edx
    and rax, USRAUTH_CACHE_MASK

    imul rax, usrauth_cache_ent_t_size
    lea rbx, [usrauth_cache]
    add rbx, rax

    mov dword [rbx + usrauth_cache_ent_t.subject_handle], edi
    mov [rbx + usrauth_cache_ent_t.object_id], rsi
    mov dword [rbx + usrauth_cache_ent_t.verb], edx
    mov dword [rbx + usrauth_cache_ent_t.verdict], ecx
    mov rax, [usrauth_policy_epoch]
    mov [rbx + usrauth_cache_ent_t.epoch], rax
    mov dword [rbx + usrauth_cache_ent_t.valid], 1

    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_policy_walk
;
; Accumulates verbs granted to a subject over an object, following via_object
; indirection up to USRAUTH_RELATION_MAX_DEPTH.
;
; Inputs:
;   RDI = Object id
;   ESI = Subject handle
;   EDX = Current depth
;   RCX = Current time in ns
;
; Returns:
;   EAX = Accumulated verb bitmask
; -----------------------------------------------------------------------------
align 32
usrauth_policy_walk:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; Object
    mov r13d, esi                   ; Subject
    mov r14d, edx                   ; Depth
    mov r15, rcx                    ; Now

    xor r8d, r8d                    ; Accumulated grants

    cmp r14d, USRAUTH_RELATION_MAX_DEPTH
    jae .pw_done                    ; Depth cap: cycles cannot spin

    mov rcx, [usrauth_relation_count]
    lea rbx, [usrauth_relations]

.pw_loop:
    test rcx, rcx
    jz .pw_done

    cmp dword [rbx + usrauth_relation_t.active], 0
    je .pw_next
    cmp [rbx + usrauth_relation_t.object_id], r12
    jne .pw_next

    ; Expired grants confer nothing. Checked before the subject match so an
    ; expired tuple cannot short-circuit into an allow.
    mov rax, [rbx + usrauth_relation_t.expires_ns]
    USRAUTH_JMP_IF_LAPSED r15, rax, .pw_next

    ; Direct grant to this subject?
    cmp dword [rbx + usrauth_relation_t.subject_handle], r13d
    jne .pw_indirect

    mov eax, dword [rbx + usrauth_relation_t.relation]
    or r8d, eax
    jmp .pw_next

.pw_indirect:
    ; Indirect: recurse through the referenced object.
    mov rax, [rbx + usrauth_relation_t.via_object]
    test rax, rax
    jz .pw_next

    push rcx
    push rbx
    push r8

    mov rdi, rax
    mov esi, r13d
    mov edx, r14d
    inc edx
    mov rcx, r15
    call usrauth_policy_walk

    mov edx, eax
    pop r8
    pop rbx
    pop rcx

    ; An indirect path confers only what the relation itself allows.
    mov eax, dword [rbx + usrauth_relation_t.relation]
    and eax, edx
    or r8d, eax

.pw_next:
    add rbx, usrauth_relation_t_size
    dec rcx
    jmp .pw_loop

.pw_done:
    mov eax, r8d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_policy_check
;
; Decides whether relations grant the requested verbs, using the cache.
;
; Inputs:
;   EDI = Subject handle
;   RSI = Object id
;   EDX = Requested verbs
;
; Returns:
;   EAX = USRAUTH_ALLOW or USRAUTH_DENY_POLICY
; -----------------------------------------------------------------------------
align 32
usrauth_policy_check:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi                   ; Subject
    mov r13, rsi                    ; Object
    mov r14d, edx                   ; Requested
    and r14d, USRAUTH_VERB_MASK

    test r14d, r14d
    jz .pc_allow

    call usrauth_policy_cache_lookup
    cmp eax, 1
    jne .pc_return                  ; Cache hit: verdict already known

    call mono_get_nanos
    mov rcx, rax

    mov rdi, r13
    mov esi, r12d
    xor edx, edx
    call usrauth_policy_walk

    ; Every requested bit must be covered.
    mov ecx, eax
    and ecx, r14d
    cmp ecx, r14d
    je .pc_grant

    inc qword [usrauth_policy_denials]
    mov ebx, USRAUTH_DENY_POLICY
    jmp .pc_memo

.pc_grant:
    xor ebx, ebx

.pc_memo:
    mov edi, r12d
    mov rsi, r13
    mov edx, r14d
    mov ecx, ebx
    call usrauth_policy_cache_store

    mov eax, ebx
    jmp .pc_return

.pc_allow:
    xor eax, eax

.pc_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_policy_who_can
;
; Reverse query: enumerate subjects holding a verb on an object.
;
; This direction is what makes access review tractable and is precisely what a
; pure ACL cannot answer without scanning every object in the system.
;
; Inputs:
;   RDI = Object id
;   ESI = Verb bitmask
;   RDX = Output array of subject handles
;   ECX = Output capacity
;
; Returns:
;   EAX = Number of subjects written
; -----------------------------------------------------------------------------
align 32
usrauth_policy_who_can:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; Object
    mov r13d, esi                   ; Verbs
    mov r14, rdx                    ; Output
    mov r15d, ecx                   ; Capacity

    xor r9d, r9d                    ; Written

    test r14, r14
    jz .wc_done

    call mono_get_nanos
    mov r10, rax

    mov rcx, [usrauth_relation_count]
    lea rbx, [usrauth_relations]

.wc_loop:
    test rcx, rcx
    jz .wc_done
    cmp r9d, r15d
    jae .wc_done

    cmp dword [rbx + usrauth_relation_t.active], 0
    je .wc_next
    cmp [rbx + usrauth_relation_t.object_id], r12
    jne .wc_next

    mov eax, dword [rbx + usrauth_relation_t.subject_handle]
    cmp eax, USRAUTH_INVALID_HANDLE
    je .wc_next                     ; Indirect entries have no direct subject

    ; Must actually confer the requested verbs.
    mov edx, dword [rbx + usrauth_relation_t.relation]
    and edx, r13d
    cmp edx, r13d
    jne .wc_next

    ; And must not have lapsed.
    mov rdx, [rbx + usrauth_relation_t.expires_ns]
    USRAUTH_JMP_IF_LAPSED r10, rdx, .wc_next

    mov [r14 + r9 * 4], eax
    inc r9d

.wc_next:
    add rbx, usrauth_relation_t_size
    dec rcx
    jmp .wc_loop

.wc_done:
    mov eax, r9d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usrauth_policy_stats
;
; Inputs:
;   RDI = Pointer to four qwords: relations, cache hits, misses, denials
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
usrauth_policy_stats:
    mov rax, [usrauth_relation_count]
    mov [rdi], rax
    mov rax, [usrauth_cache_hits]
    mov [rdi + 8], rax
    mov rax, [usrauth_cache_misses]
    mov [rdi + 16], rax
    mov rax, [usrauth_policy_denials]
    mov [rdi + 24], rax
    xor eax, eax
    ret
