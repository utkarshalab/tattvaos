; ============================================================================
; Client Present Helpers — Waiting for a Frame
; ============================================================================
; canvas_present_wait asks for a frame callback and waits for its frame_done
; event (surface, callback, time, flags); every other event that comes first
; is held for canvas_event_poll, as during a call.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern canvas_frame_request
extern canvas_wire_queue
extern canvas_wire_read

%define CLIENT_PRESENT_VALID 104        ; ClientConn.present_valid
%define CLIENT_PRESENT_INFO  112        ; a ClientPresentInfo

section .text

; ---------------------------------------------------------------------------
; canvas_present_wait
;   Until the surface's next commit has been shown
;   IN:  rdi = conn, esi = surface, rdx = how long to wait, ns
;   OUT: rax = 0, -ETIMEDOUT, negative error from the request
; ---------------------------------------------------------------------------
global canvas_present_wait
canvas_present_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r13, rdx
    ASSERT_PTR rbx
    call canvas_frame_request
    test rax, rax
    js .out
    mov r12d, eax                       ; the callback
    call ut_time_now_ns
    add r13, rax                        ; the deadline
.wait:
    mov rdi, rbx
    call canvas_wire_read
    test rax, rax
    js .idle
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.in_hdr]
    test word [rcx + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .wait
    cmp dword [rcx + MsgHdr.obj], CWP_OBJ_SURFACE
    jne .keep
    cmp word [rcx + MsgHdr.opcode], SURFACE_EV_FRAME_DONE
    jne .keep
    cmp [rbx + CLIENT_WIRE + ClientWire.in_msg + 4], r12d
    je .done
.keep:
    mov rdi, rbx
    call canvas_wire_queue
    jmp .wait
.idle:
    call ut_time_now_ns
    cmp rax, r13
    jae .timeout
    mov rax, [rbx + CLIENT_WIRE + ClientWire.pump]
    test rax, rax
    jz .yield
    mov rdi, [rbx + CLIENT_WIRE + ClientWire.pump_arg]
    call rax
    jmp .wait
.yield:
    call ut_yield
    jmp .wait
.done:
    mov byte [rbx + CLIENT_PRESENT_VALID], 1
    lea rcx, [rbx + CLIENT_PRESENT_INFO]
    mov dword [rcx + ClientPresentInfo.kind], 0
    mov qword [rcx + ClientPresentInfo.seq], 0
    mov rax, [rbx + CLIENT_WIRE + ClientWire.in_msg + 8]
    mov [rcx + ClientPresentInfo.time], rax
    mov eax, [rbx + CLIENT_WIRE + ClientWire.in_msg + 16]
    mov [rcx + ClientPresentInfo.flags], eax
    xor eax, eax
    jmp .out
.timeout:
    mov rax, -(ETIMEDOUT)
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; canvas_present_feedback
;   IN:  rdi = conn
;   OUT: rax = the last frame's ClientPresentInfo, 0 before the first
; ---------------------------------------------------------------------------
global canvas_present_feedback
canvas_present_feedback:
    xor eax, eax
    cmp byte [rdi + CLIENT_PRESENT_VALID], 0
    je .out
    lea rax, [rdi + CLIENT_PRESENT_INFO]
.out:
    ret

section .data
global canvas_present_helpers_version
canvas_present_helpers_version: dq 0x020000
