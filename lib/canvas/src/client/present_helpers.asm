; ============================================================================
; Client Present Helpers — Frame Callbacks + Presentation Feedback
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_present_wait
canvas_present_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    ASSERT_PTR rbx
    ; TODO: send frame callback, block until frame_done or timeout
    ; poll event loop with deadline
    call tv_time_now_ns
    add rax, r13
    mov r13, rax
.poll:
    sub rsp, ClientEvent_size
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test rax, rax
    jnz .got
    call tv_time_now_ns
    cmp rax, r13
    jae .timeout
    mov rdi, 1000000
    call tv_time_sleep_ns
    add rsp, ClientEvent_size
    jmp .poll
.got:
    ; TODO: check event is frame_done for surface
    add rsp, ClientEvent_size
    xor rax, rax
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
    ; TODO: return last PresentInfo
    xor rax, rax
    leave
    ret

section .data
global canvas_present_helpers_version
canvas_present_helpers_version: dq 0x010000
