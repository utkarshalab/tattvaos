; ============================================================================
; Client Present Helpers — Frame Callbacks + Presentation Feedback
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern canvas_frame_request

section .text

%define CLIENT_PRESENT_VALID 104
%define CLIENT_PRESENT_INFO  112

global canvas_present_wait
canvas_present_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    ASSERT_PTR rbx
    mov rdi, rbx
    mov esi, r12d
    call canvas_frame_request
    test rax, rax
    js .request_failed
    call ut_time_now_ns
    add rax, r13
    mov r13, rax
.poll:
    sub rsp, ClientEvent_size
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test rax, rax
    jnz .got
    call ut_time_now_ns
    cmp rax, r13
    jae .timeout
    mov rdi, 1000000
    call ut_time_sleep_ns
    add rsp, ClientEvent_size
    jmp .poll
.got:
    cmp dword [rsp + ClientEvent.a], r12d
    jne .other_event
    mov byte [rbx + CLIENT_PRESENT_VALID], 1
    mov dword [rbx + CLIENT_PRESENT_INFO], 0
    mov rax, [rsp + ClientEvent.time]
    mov [rbx + CLIENT_PRESENT_INFO + 16], rax
    add rsp, ClientEvent_size
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.other_event:
    add rsp, ClientEvent_size
    jmp .poll
.request_failed:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.timeout:
    add rsp, ClientEvent_size
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global canvas_present_feedback
canvas_present_feedback:
    PROLOGUE
    cmp byte [rdi + CLIENT_PRESENT_VALID], 0
    je .no_feedback
    lea rax, [rdi + CLIENT_PRESENT_INFO]
    leave
    ret
.no_feedback:
    xor eax, eax
    leave
    ret

section .data
global canvas_present_helpers_version
canvas_present_helpers_version: dq 0x010000
