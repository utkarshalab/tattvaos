; ============================================================================
; Prompts — Server-Owned Permission Prompts (Anti-Spoofing)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/caps.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern ut_log_write
extern ut_time_now_ns
extern ut_wait_yield

%define PROMPT_STATE_PENDING     0
%define PROMPT_STATE_ANSWERED    1
%define PROMPT_STATE_TIMEOUT     2
%define PROMPT_STATE_CANCELLED   3
%define PROMPT_ACTION_ALLOW      1
%define PROMPT_ACTION_DENY       2
%define PROMPT_ACTION_ALWAYS     3
%define PROMPT_ACTION_NEVER      4
%define PROMPT_DEFAULT_TIMEOUT   (30 * 1000000000)
%define PRIVILEGED_CAPS          (CAP_CAPTURE | CAP_INJECT | CAP_POLICY | CAP_DEBUG | CAP_SESSION)

section .text

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
    EPILOGUE_RESTORE rbx, r12
    ret

; prompts_show(server, client, message, message_len, capability,
;              options_or_null, timeout_ns)
; Returns 1 for allow, 0 for deny/timeout, or a negative error.
global prompts_show
prompts_show:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    mov [rsp + 8], r10
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rax, [r12 + Client.trust_profile]
    test rax, rax
    jz .deny
    movzx ecx, byte [rax + TrustProfile.prompts]
    cmp ecx, PROMPT_NEVER
    je .allow
    cmp ecx, PROMPT_PRIVILEGED
    jne .need_prompt
    test r15, PRIVILEGED_CAPS
    jz .allow

.need_prompt:
    cmp qword [rbx + Server.prompt_count], 0
    jne .busy
    mov rdi, [rbx + Server.arena]
    mov rsi, Prompt_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r11, rax
    mov [r11 + Prompt.client], r12
    mov [r11 + Prompt.message], r13
    mov [r11 + Prompt.message_len], r14
    mov [r11 + Prompt.capability], r15
    mov rax, [rsp]
    test rax, rax
    jnz .have_options
    mov rax, default_prompt_options
.have_options:
    mov [r11 + Prompt.options], rax
    mov dword [r11 + Prompt.option_count], 2
    mov qword [r11 + Prompt.callback], 0
    mov qword [r11 + Prompt.user_data], 0
    mov dword [r11 + Prompt.state], PROMPT_STATE_PENDING
    mov [rbx + Server.prompts], r11
    mov qword [rbx + Server.prompt_count], 1
    mov [rsp], r11

    call ut_time_now_ns
    mov r11, [rsp]
    mov rcx, [rsp + 8]
    test rcx, rcx
    jnz .have_timeout
    mov rcx, PROMPT_DEFAULT_TIMEOUT
.have_timeout:
    add rax, rcx
    jc .bad_timeout
    mov [r11 + Prompt.timeout], rax

    mov rdi, rbx
    mov rsi, r11
    call prompts_draw
    test rax, rax
    js .finish
    mov rdi, rbx
    mov rsi, [rsp]
    call prompts_wait
.finish:
    mov qword [rbx + Server.prompts], 0
    mov qword [rbx + Server.prompt_count], 0
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_timeout:
    mov rax, -(EINVAL)
    jmp .finish
.allow:
    mov rax, 1
    jmp .return
.deny:
    xor rax, rax
    jmp .return
.busy:
    mov rax, -(EBUSY)
    jmp .return
.oom:
    mov rax, -(ENOMEM)
.return:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; Publish prompt text through a server-owned channel. Native compositors can
; mirror the same Prompt object into a protected overlay without trusting the
; requesting client for pixels or labels.
global prompts_draw
prompts_draw:
    PROLOGUE_SAVE rbx
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov rbx, rsi
    mov rdi, [rbx + Prompt.message]
    mov rsi, [rbx + Prompt.message_len]
    call ut_log_write
    test rax, rax
    js .draw_done
    xor rax, rax
.draw_done:
    EPILOGUE_RESTORE rbx
    ret

global prompts_wait
prompts_wait:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
.wait:
    mov eax, [r12 + Prompt.state]
    cmp eax, PROMPT_STATE_ANSWERED
    je .answered
    cmp eax, PROMPT_STATE_CANCELLED
    je .denied
    cmp eax, PROMPT_STATE_TIMEOUT
    je .denied
    call ut_time_now_ns
    cmp rax, [r12 + Prompt.timeout]
    jae .timed_out
    call ut_wait_yield
    jmp .wait
.timed_out:
    mov dword [r12 + Prompt.state], PROMPT_STATE_TIMEOUT
.denied:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.answered:
    mov rax, [r12 + Prompt.user_data]
    cmp rax, PROMPT_ACTION_ALLOW
    je .allowed
    cmp rax, PROMPT_ACTION_ALWAYS
    jne .denied
.allowed:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

; Called only by the trusted input path after server-side hit testing.
global prompts_answer
prompts_answer:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    cmp [rdi + Server.prompts], rsi
    jne .invalid
    cmp dword [rsi + Prompt.state], PROMPT_STATE_PENDING
    jne .invalid
    cmp rdx, PROMPT_ACTION_ALLOW
    jb .invalid
    cmp rdx, PROMPT_ACTION_NEVER
    ja .invalid
    mov [rsi + Prompt.user_data], rdx
    mov dword [rsi + Prompt.state], PROMPT_STATE_ANSWERED
    xor rax, rax
    leave
    ret
.invalid:
    mov rax, -(EINVAL)
    leave
    ret

global prompts_cancel_client
prompts_cancel_client:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov rax, [rdi + Server.prompts]
    test rax, rax
    jz .cancel_done
    cmp [rax + Prompt.client], rsi
    jne .cancel_done
    mov dword [rax + Prompt.state], PROMPT_STATE_CANCELLED
.cancel_done:
    xor rax, rax
    leave
    ret

section .rodata
prompt_allow_text: db "Allow", 0
prompt_deny_text:  db "Deny", 0
align 8
default_prompt_options:
    dq prompt_allow_text
    dq 5
    dd PROMPT_ACTION_ALLOW
    dd 1
    dq prompt_deny_text
    dq 4
    dd PROMPT_ACTION_DENY
    dd 0

section .data
global prompts_version
prompts_version: dq 0x010000
