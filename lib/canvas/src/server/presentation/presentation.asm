; Presentation feedback -- synchronized per-surface history and wire events.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define PresentInfo.kind 0
%define PresentInfo.seq 4
%define PresentInfo.time 12
%define PresentInfo.refresh_ns 20
%define PresentInfo.flags 28
%define PresentInfo_size 32

%define Feedback.next 0
%define Feedback.surface 8
%define Feedback.completed 16
%define Feedback.info 24
%define Feedback_size 56

%define SERVER_SURFACE_ID 0
%define SERVER_SURFACE_CLIENT 40
%define SERVER_CLIENT_RX_RING 48
%define CWP_OBJ_PRESENT 25
%define CWP_PRESENT_EVENT_FEEDBACK 2
%define PRESENT_KIND_VSYNC 0
%define PRESENT_FLAG_HW_COMPLETION 1

section .text

global presentation_init
presentation_init:
    mov qword [rel feedback_head], 0
    mov dword [rel feedback_lock], 0
    xor eax, eax
    ret

presentation_lock:
    mov eax, 1
.spin:
    xchg eax, [rel feedback_lock]
    test eax, eax
    jz .held
    pause
    mov eax, 1
    jmp .spin
.held:
    ret

presentation_unlock:
    mov dword [rel feedback_lock], 0
    ret

; IN server*, surface*, sequence.
global presentation_queue
presentation_queue:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    mov rdi, [rbx + Server.arena]
    mov rsi, Feedback_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov [r14 + Feedback.surface], r12
    mov qword [r14 + Feedback.completed], 0
    mov dword [r14 + Feedback.info + PresentInfo.kind], PRESENT_KIND_VSYNC
    mov qword [r14 + Feedback.info + PresentInfo.seq], r13
    mov qword [r14 + Feedback.info + PresentInfo.time], 0
    mov qword [r14 + Feedback.info + PresentInfo.refresh_ns], 0
    mov dword [r14 + Feedback.info + PresentInfo.flags], 0
    mov rax, [rbx + Server.outputs]
    test rax, rax
    jz .link
    mov rax, [rax + Output.frame_clock]
    test rax, rax
    jz .link
    mov rax, [rax + FrameClock.refresh_ns]
    mov [r14 + Feedback.info + PresentInfo.refresh_ns], rax
.link:
    call presentation_lock
    mov rax, [rel feedback_head]
    mov [r14 + Feedback.next], rax
    mov [rel feedback_head], r14
    call presentation_unlock
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; Complete the oldest outstanding feedback for a surface and emit its event.
global presentation_complete
presentation_complete:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 64
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .invalid
    call presentation_lock
    mov r14, [rel feedback_head]
    xor r15d, r15d
.find:
    test r14, r14
    jz .not_found_locked
    cmp [r14 + Feedback.surface], r12
    jne .next
    cmp qword [r14 + Feedback.completed], 0
    je .found
.next:
    mov r14, [r14 + Feedback.next]
    jmp .find
.found:
    mov [r14 + Feedback.completed], r13
    mov [r14 + Feedback.info + PresentInfo.time], r13
    or dword [r14 + Feedback.info + PresentInfo.flags], PRESENT_FLAG_HW_COMPLETION
    call presentation_unlock

    ; Payload is surface handle + alignment + PresentInfo.
    mov eax, [r12 + SERVER_SURFACE_ID]
    mov [rsp + 16], eax
    mov dword [rsp + 20], 0
    lea rdi, [rsp + 24]
    lea rsi, [r14 + Feedback.info]
    mov rdx, PresentInfo_size
    call memcopy
    mov dword [rsp], CWP_OBJ_PRESENT
    mov word [rsp + 4], CWP_PRESENT_EVENT_FEEDBACK
    mov word [rsp + 6], CWP_MSG_FLAG_IS_EVENT
    mov dword [rsp + 8], 40
    mov rax, [r12 + SERVER_SURFACE_CLIENT]
    test rax, rax
    jz .ok
    mov rdi, [rax + SERVER_CLIENT_RX_RING]
    test rdi, rdi
    jz .ok
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
    test rax, rax
    js .out
.ok:
    xor eax, eax
    jmp .out
.not_found_locked:
    call presentation_unlock
    mov rax, -(ENOENT)
    jmp .out
.invalid:
    mov rax, -(EINVAL)
.out:
    add rsp, 64
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; IN server*, surface*, out PresentInfo*. Returns latest completed feedback.
global presentation_get_feedback
presentation_get_feedback:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    call presentation_lock
    mov rbx, [rel feedback_head]
    xor r14d, r14d
.scan:
    test rbx, rbx
    jz .scan_done
    cmp [rbx + Feedback.surface], r12
    jne .scan_next
    mov rax, [rbx + Feedback.completed]
    test rax, rax
    jz .scan_next
    test r14, r14
    jz .select
    cmp rax, [r14 + Feedback.completed]
    jbe .scan_next
.select:
    mov r14, rbx
.scan_next:
    mov rbx, [rbx + Feedback.next]
    jmp .scan
.scan_done:
    test r14, r14
    jz .not_found_locked
    lea rsi, [r14 + Feedback.info]
    mov rdi, r13
    mov rdx, PresentInfo_size
    call memcopy
    call presentation_unlock
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.not_found_locked:
    call presentation_unlock
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .bss
align 8
feedback_head: resq 1
feedback_lock: resd 1

section .data
global presentation_version
presentation_version: dq 0x010100
