; ============================================================================
; Capability Gate — Privileged Interface Access Control
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/caps.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern audit_log
extern prompts_show

; Privileged capabilities that require gate
%define GATE_CAP_CAPTURE    CAP_CAPTURE
%define GATE_CAP_INJECT     CAP_INJECT
%define GATE_CAP_POLICY     CAP_POLICY
%define GATE_CAP_DEBUG      CAP_DEBUG
%define GATE_CAP_SESSION    CAP_SESSION
%define GATE_PRIVILEGED_MASK (GATE_CAP_CAPTURE | GATE_CAP_INJECT | GATE_CAP_POLICY | GATE_CAP_DEBUG | GATE_CAP_SESSION)
%define AUDIT_ACTION_PRIVILEGED 4
%define AUDIT_RESULT_GRANTED    1
%define AUDIT_RESULT_DENIED     2

section .text

; ---------------------------------------------------------------------------
; gate_init
; ---------------------------------------------------------------------------
global gate_init
gate_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.gate], 0
    mov qword [rbx + Server.arena], r12

    mov rdi, r12
    mov rsi, Gate_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov qword [r13 + Gate.server], rbx
    mov qword [r13 + Gate.audit_log], 0

    mov qword [rbx + Server.gate], r13

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; gate_check
;   Check if client can access privileged interface
;   IN:  rdi = server*, rsi = client*, rdx = required_cap
;   OUT: rax = 1 if allowed, 0 if denied, negative error
; ---------------------------------------------------------------------------
global gate_check
gate_check:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check if client has the capability
    mov rax, [r12 + Client.caps]
    and rax, r13
    cmp rax, r13
    jne .denied

    ; Check trust profile allows this capability
    mov rax, [rsi + Client.trust_profile]
    test rax, rax
    jz .denied

    mov rcx, [rax + TrustProfile.caps]
    and rcx, r13
    cmp rcx, r13
    jne .denied

    ; Check if prompt required
    mov al, [rax + TrustProfile.prompts]
    cmp al, PROMPT_NEVER
    je .allowed
    cmp al, PROMPT_PRIVILEGED
    je .check_prompt
    cmp al, PROMPT_ALL
    je .show_prompt

    ; Default: deny
    jmp .denied

.check_prompt:
    test r13, GATE_PRIVILEGED_MASK
    jz .allowed
    jmp .show_prompt

.show_prompt:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, gate_prompt_message
    mov rcx, gate_prompt_message_len
    mov r8, r13
    xor r9, r9
    mov r10, 30 * 1000000000
    call gate_show_prompt
    test rax, rax
    jz .denied

.allowed:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, 1
    call gate_log_access
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.denied:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    xor rcx, rcx
    call gate_log_access
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; gate_show_prompt
; ---------------------------------------------------------------------------
gate_show_prompt:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rsi + Client.trust_profile]
    cmp dword [rax + TrustProfile.prompts], PROMPT_NEVER
    je .auto_grant
    call prompts_show
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.auto_grant:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; gate_log_access
; ---------------------------------------------------------------------------
gate_log_access:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, AUDIT_ACTION_PRIVILEGED
    mov rdx, [r12 + Client.id]
    mov rcx, r13
    mov r8, AUDIT_RESULT_DENIED
    test r14, r14
    jz .log
    mov r8, AUDIT_RESULT_GRANTED
.log:
    xor r9, r9
    xor r10, r10
    call audit_log
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
gate_prompt_message: db "Allow privileged display-server operation?", 0
gate_prompt_message_len equ $ - gate_prompt_message - 1
global gate_version
gate_version: dq 0x010000
