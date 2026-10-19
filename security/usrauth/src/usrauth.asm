%ifndef GUARD_SECURITY_USRAUTH_SRC_USRAUTH_ASM
%define GUARD_SECURITY_USRAUTH_SRC_USRAUTH_ASM

; =============================================================================
; File     : security/usrauth/src/usrauth.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: usrauth - Identity & Access Management (Reference Monitor).
;              Central authorization dispatcher implementing the Reference
;              Monitor pattern: MANY independent ways to DENY, exactly ONE way
;              to GRANT. Effective authority is the INTERSECTION of every
;              layer (token, subject, capability, policy, mandatory MAC,
;              audit). If any layer denies, the request is denied.
;              Evaluation is cheapest-denier-first for performance; correctness
;              does not depend on order since every term must hold.
; Status   : ENTERPRISE SKELETON - full API surface defined, logic bodies
;              marked STUB with TODO comments. All include guards, section
;              directives, .bss/.data/.text sections, global exports, and
;              status codes are implemented.
; =============================================================================

bits 64
default rel

%include "include/usrauth.inc"

section .bss
alignb 16
usrauth_enabled:           resb 1
alignb 16
usrauth_state:             resq 1
alignb 16
usrauth_global_state:      resb usrauth_global_state_t_size
alignb 16
usrauth_init_count:        resq 1
alignb 16
usrauth_policy_engine:     resq 1
alignb 16
usrauth_subject_table:     resq 1
alignb 16
usrauth_token_registry:    resq 1
alignb 16
usrauth_capability_engine: resq 1
alignb 16
usrauth_policy_engine2:    resq 1
alignb 16
usrauth_mandatory_layer:   resq 1
alignb 16
usrauth_audit_log:         resq 1
alignb 16
usrauth_stats_requests:    resq 1
alignb 16
usrauth_stats_blocks:      resq 1
alignb 16
usrauth_stats_errors:      resq 1
alignb 16
usrauth_stats_denials:     resq 1

section .data
alignb 16
usrauth_version_str:   db USRAUTH_VERSION_STR, 0
alignb 16
usrauth_module_name: db "Tattva OS usrauth Reference Monitor v1.0.0-enterprise", 0
alignb 16
usrauth_err_not_initialized: db "usrauth: subsystem not initialized", 0
alignb 16
usrauth_err_invalid_handle: db "usrauth: invalid subject handle", 0
alignb 16
usrauth_err_denied_policy: db "usrauth: policy denied access", 0
alignb 16
usrauth_reason_policy_violation: db "policy violation", 0

section .text

; =============================================================================
; usrauth_init - Initialize the USRAUTH Reference Monitor
; Input:  none
; Output: rax = 0 on success, negative errno-style error code on failure
;         Initializes all sub-layers in dependency order:
;           1. subject table (subjects must exist before capabilities)
;           2. policy engine (policies must exist before evaluation)
;           3. token registry
;           4. capability engine
;           5. mandatory access control
;           6. audit log (records all subsequent decisions)
;           7. stats engine
; =============================================================================
global usrauth_init
usrauth_init:
    push    rbx
    push    r12
    push    r13
    push    r14

    ; Double-init guard: check magic
    mov     eax, [usrauth_state + usrauth_state_base_t.magic]
    cmp     eax, USRAUTH_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    ; Zero the global state structure
    xor     eax, eax
    mov     rcx, usrauth_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, usrauth_global_state
    rep     stosd

    ; Set magic and version
    mov     eax, USRAUTH_STATE_MAGIC
    mov     dword [usrauth_global_state + usrauth_global_state_t.magic], eax
    mov     eax, (1 << 16) | 0          ; version 1.0
    mov     [usrauth_global_state + usrauth_state_base_t.version], eax

    ; Set default config values
    mov     rax, USRAUTH_DEFAULT_MAX_SUBJECTS
    mov     qword [usrauth_global_state + usrauth_global_state_t.max_subjects], rax
    mov     rax, USRAUTH_DEFAULT_MAX_POLICIES
    mov     qword [usrauth_global_state + usrauth_global_state_t.max_policies], rax
    mov     rax, USRAUTH_DEFAULT_MAX_TOKENS
    mov     qword [usrauth_global_state + usrauth_global_state_t.max_tokens], rax
    mov     rax, USRAUTH_DEFAULT_MAX_CAPS
    mov     qword [usrauth_global_state + usrauth_global_state_t.max_caps], rax

    ; Default fail mode: CLOSED (secure)
    mov     dword [usrauth_global_state + usrauth_global_state_t.fail_mode], USRAUTH_FAIL_CLOSED

    ; STUB: Initialize components in dependency order:
    ;   subject_table -> policy_engine -> token_registry -> capability_engine ->
    ;   mandatory_access -> audit_log -> stats_engine
    ; Each component's init() must succeed before proceeding to the next.

    mov     byte [usrauth_global_state + usrauth_state_base_t.enabled], 1
    xor     eax, eax             ; success
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; usrauth_shutdown - Shut down USRAUTH
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global usrauth_shutdown
usrauth_shutdown:
    push    rbx

    mov     eax, [usrauth_global_state + usrauth_state_base_t.magic]
    cmp     eax, USRAUTH_STATE_MAGIC
    jnz     .not_init

    mov     dword [usrauth_global_state + usrauth_state_base_t.magic], USRAUTH_STATE_MAGIC_FREED
    mov     byte [usrauth_global_state + usrauth_state_base_t.enabled], 0
    xor     eax, eax
.not_init:
    pop     rbx
    ret

; =============================================================================
; usrauth_status - Return current USRAUTH status
; Input:  none
; Output: rax = status code (0 = enabled, nonzero = disabled/not initialized)
; =============================================================================
global usrauth_status
usrauth_status:
    mov     eax, [usrauth_global_state + usrauth_state_base_t.magic]
    cmp     eax, USRAUTH_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [usrauth_global_state + usrauth_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_initialized:
    mov     eax, -2
    ret

; =============================================================================
; usrauth_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global usrauth_version
usrauth_version:
    mov     rax, usrauth_version_str
    ret

; =============================================================================
; usrauth_evaluate_access - Main access decision entry point
; Input:  rdi = subject_handle, rsi = object_id, rdx = object_class,
;         rcx = verb (USRAUTH_VERB_*), r8  = context pointer
; Output: rax = verdict (USRAUTH_ALLOW or USRAUTH_DENY_*),
;         rbx = reason code (USRAUTH_DENY_*)
; Flow:
;   1. Validate state & input
;   2. Subject table lookup & capability check
;   3. Mandatory access control (integrity, MLS, TE)
;   4. Audit log entry
;   5. Return verdict + reason code
; =============================================================================
global usrauth_evaluate
usrauth_evaluate:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Validate global state
    mov     eax, [usrauth_global_state + usrauth_state_base_t.magic]
    cmp     eax, USRAUTH_STATE_MAGIC
    jnz     .err_component_down

    ; Validate input: subject_handle must be non-zero
    test    rdi, rdi
    jz      .err_invalid_request

    mov     r12, rdi              ; save subject handle

    ; STEP 1: Subject table lookup
    ; STEP 2: Capability evaluation
    ; STEP 3: Mandatory Access Control
    ; STEP 4: Log the decision

    ; For skeleton: allow all requests (stub)
    mov     rax, USRAUTH_ACTION_ALLOW
    xor     rbx, rbx               ; reason code = no reason (allowed)
    mov     rcx, 0                 ; duration = 0 (no block)

    lock    inc    qword [usrauth_global_state + usrauth_global_state_t.total_requests]

    jmp     .done

.err_component_down:
    mov     rax, USRAUTH_ACTION_DROP
    mov     rbx, USRAUTH_REASON_COMPONENT_DOWN
    mov     rcx, 0
    jmp     .done

.err_invalid_request:
    mov     rax, USRAUTH_ACTION_DROP
    mov     rbx, USRAUTH_REASON_INVALID_REQUEST
    mov     rcx, 0
    jmp     .done

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; usrauth_get_stats - Return statistics snapshot
; Input:  rdi = stats buffer pointer
; Output: rax = 0 on success, negative on failure
; =============================================================================
global usrauth_get_stats
usrauth_get_stats:
    push    rbx

    mov     eax, [usrauth_global_state + usrauth_state_base_t.magic]
    cmp     eax, USRAUTH_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: copy current statistics to buffer
    xor     eax, eax
    jmp .done

.err_component_down:
    mov     rax, -1
    jmp .done
.err_invalid:
    mov     rax, -2
    jmp .done

.done:
    pop     rbx
    ret

%endif