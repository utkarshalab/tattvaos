; ============================================================================
; Prompts — Server-Drawn Permission Prompts (Anti-Spoofing)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/color.inc"

section .text

struc Prompt {
    .client:        resq 1
    .message:       resq 1
    .message_len:   resq 1
    .capability:    resq 1
    .options:       resq 1
    .option_count:  resd 1
    .callback:      resq 1
    .user_data:     resq 1
    .timeout:       resq 1
    .state:         resd 1
}
%define Prompt_size    72

%define PROMPT_STATE_PENDING     0
%define PROMPT_STATE_ANSWERED    1
%define PROMPT_STATE_TIMEOUT     2
%define PROMPT_STATE_CANCELLED   3

%define PROMPT_OPTION_ALLOW      0
%define PROMPT_OPTION_DENY       1
%define PROMPT_OPTION_ALWAYS     2
%define PROMPT_OPTION_NEVER      3

struc PromptOption {
    .text:      resq 1
    .text_len:  resq 1
    .action:    resd 1
    .value:     resq 1
}
%define PromptOption_size    24

%define PROMPT_ACTION_ALLOW      1
%define PROMPT_ACTION_DENY       2
%define PROMPT_ACTION_ALWAYS     3
%define PROMPT_ACTION_NEVER      4

; ---------------------------------------------------------------------------
; prompts_init
; ---------------------------------------------------------------------------
global prompts_init
prompts_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.prompts], 0
    mov qword [rbx + Server.prompt_count], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; prompts_show
;   Show permission prompt
;   IN:  rdi = server*, rsi = client*, rdx = message, rcx = msg_len, r8 = capability, r9 = options, r10 = timeout
;   OUT: rax = 1 if allowed, 0 if denied, negative error
; ---------------------------------------------------------------------------
global prompts_show
prompts_show:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov r13, r9
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Check if prompts are required by trust profile
    mov rax, [r12 + Client.trust_profile]
    test rax, rax
    jz .no_profile
    mov al, [rax + TrustProfile.prompts]
    cmp al, PROMPT_NEVER
    je .auto_allow
    cmp al, PROMPT_PRIVILEGED
    je .check_privileged
    cmp al, PROMPT_ALL
    je .show_prompt

.no_profile:
.auto_allow:
    mov rax, 1
    ret

.check_privileged:
    ; Check if capability is privileged
    mov rax, r8
    test rax, CAP_CAPTURE | CAP_INJECT | CAP_POLICY | CAP_DEBUG | CAP_SESSION
    jz .auto_allow

.show_prompt:
    ; Allocate prompt
    mov rdi, [rbx + Server.arena]
    mov rsi, Prompt_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    ; Initialize prompt
    mov qword [r12 + Prompt.client], r15
    mov qword [r12 + Prompt.message], r13
    mov qword [r12 + Prompt.message_len], r14
    mov qword [r12 + Prompt.capability], r8
    mov qword [r12 + Prompt.options], r9
    mov dword [r12 + Prompt.option_count], r10d
    mov qword [r12 + Prompt.callback], 0
    mov qword [r12 + Prompt.user_data], 0
    mov qword [r12 + Prompt.timeout], r11
    mov dword [r12 + Prompt.state], PROMPT_STATE_PENDING

    ; Draw prompt on screen
    call prompts_draw

    ; Wait for response (with timeout)
    call prompts_wait

    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; prompts_draw
;   Draw prompt on screen (server-drawn, anti-spoofing)
; ---------------------------------------------------------------------------
prompts_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Create overlay window on top of all content
    ; Draw prompt with:
    ; - Distinctive border/color (unspoofable)
    ; - App name/icon
    ; - Message
    ; - Capability being requested
    ; - Options (Allow/Deny/Always/Never)
    ; - Visual distinction from client content

    ; TODO: Implement actual drawing using compositor

    ret

; ---------------------------------------------------------------------------
; prompts_wait
;   Wait for user response
; ---------------------------------------------------------------------------
prompts_wait:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Wait for user input or timeout
    ; TODO: Implement event loop for prompt

    ; For now, auto-allow
    mov rax, 1
    ret

; ---------------------------------------------------------------------------
; prompts_handle_input
;   Handle user input on prompt
; ---------------------------------------------------------------------------
global prompts_handle_input
prompts_handle_input:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Handle key/mouse input on prompt
    ; Options: Allow (1), Deny (2), Always (3), Never (4)

    ; TODO: Implement

    xor rax, rax
    ret

section .data
global prompts_version
prompts_version: dq 0x010000