; ============================================================================
; Capability Gate — Privileged Interface Access Control
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/caps.inc"

; struct offsets (hoisted above use)
%define Gate_size    16

section .text

; Privileged capabilities that require gate
%define GATE_CAP_CAPTURE    CAP_CAPTURE
%define GATE_CAP_INJECT     CAP_INJECT
%define GATE_CAP_POLICY     CAP_POLICY
%define GATE_CAP_DEBUG      CAP_DEBUG
%define GATE_CAP_SESSION    CAP_SESSION

struc Gate
    .server:        resq 1
    .audit_log:     resq 1
endstruc

; ---------------------------------------------------------------------------
; gate_init
; ---------------------------------------------------------------------------
global gate_init
gate_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.gate], 0
    mov qword [rbx + Server.arena], r12

    mov rdi, r12
    mov rsi, Gate_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Gate.server], rdi
    mov qword [rbx + Gate.audit_log], 0

    mov qword [rdi + Server.gate], rbx

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
    test rax, r13
    jz .denied

    ; Check trust profile allows this capability
    mov rax, [rsi + Client.trust_profile]
    test rax, rax
    jz .denied

    mov r13, [rax + TrustProfile.caps]
    test r13, r13
    jz .denied

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
    ; Check if this specific capability requires prompt
    ; For now, all privileged caps require prompt in standard profile
    ; TODO: Per-capability prompt configuration
    jmp .show_prompt

.show_prompt:
    ; Show server-drawn permission prompt
    ; TODO: Implement server-drawn prompt
    ; For now, grant if user confirms
    call gate_show_prompt
    test rax, rax
    jz .denied

.allowed:
    ; Log the access
    call gate_log_access
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.denied:
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

    ; TODO: Draw server-drawn prompt on screen
    ; Wait for user response
    ; Return 1 if granted, 0 if denied

    ; For now, auto-grant in trusted profile
    mov rax, [rsi + Client.trust_profile]
    cmp dword [rax + TrustProfile.prompts], PROMPT_NEVER
    je .auto_grant

    ; TODO: Implement actual prompt UI
    ; For now, auto-grant
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

.auto_grant:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; gate_log_access
; ---------------------------------------------------------------------------
gate_log_access:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Write to audit log
    ; Entry: timestamp, client_id, capability, granted/denied, details

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global gate_version
gate_version: dq 0x010000
