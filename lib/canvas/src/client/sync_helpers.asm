; ============================================================================
; Client Sync Helpers — cw_fence, cw_timeline, and waiting for them
; ============================================================================
; Every function takes rdi = conn and leaves it unchanged for the next call.
; Fences and timelines are the client's own; a buffer is given a timeline's
; points with canvas_buffer_set_timeline.
;
; canvas_fence_wait and canvas_timeline_wait ask the server first (a signal
; sent before the answer shows in it), then read what comes until the
; fence_signaled or timeline_signaled event they wait for; every event read
; on the way, that one too, stays queued for canvas_event_poll. Nothing come
; yet: the pump turns, or the program yields, until the deadline.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern canvas_call
extern canvas_send
extern canvas_wire_queue
extern canvas_wire_read

section .text

; ---------------------------------------------------------------------------
; canvas_fence_create
;   IN:  rdi = conn, esi = type (0 CPU, 1 GPU)
;   OUT: rax = the fence's handle, negative error
; ---------------------------------------------------------------------------
global canvas_fence_create
canvas_fence_create:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov [rsp], esi
    mov esi, CWP_OBJ_FENCE
    mov edx, FENCE_CREATE
    mov rcx, rsp
    mov r8d, 4
    call canvas_call
    test rax, rax
    js .out
    mov eax, [rbx + CLIENT_WIRE + ClientWire.reply]
.out:
    add rsp, 16
    pop rbx
    ret

; %1 = the function, %2 = interface, %3 = request: a request about one handle
%macro ONE_HANDLE 3
global %1
%1:
    sub rsp, 24
    mov [rsp], esi
    mov esi, %2
    mov edx, %3
    mov rcx, rsp
    mov r8d, 4
    call canvas_send
    add rsp, 24
    ret
%endmacro

; ---------------------------------------------------------------------------
; canvas_fence_destroy, canvas_fence_signal, canvas_fence_reset
;   IN:  rdi = conn, esi = fence
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
ONE_HANDLE canvas_fence_destroy, CWP_OBJ_FENCE, FENCE_DESTROY
ONE_HANDLE canvas_fence_signal, CWP_OBJ_FENCE, FENCE_SIGNAL
ONE_HANDLE canvas_fence_reset, CWP_OBJ_FENCE, FENCE_RESET

; ---------------------------------------------------------------------------
; canvas_timeline_create
;   IN:  rdi = conn
;   OUT: rax = the timeline's handle, negative error
; ---------------------------------------------------------------------------
global canvas_timeline_create
canvas_timeline_create:
    push rbx
    mov rbx, rdi
    mov esi, CWP_OBJ_TIMELINE
    mov edx, TIMELINE_CREATE
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.reply]
    xor r8d, r8d
    call canvas_call
    test rax, rax
    js .out
    mov eax, [rbx + CLIENT_WIRE + ClientWire.reply]
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; canvas_timeline_destroy
;   IN:  rdi = conn, esi = timeline
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
ONE_HANDLE canvas_timeline_destroy, CWP_OBJ_TIMELINE, TIMELINE_DESTROY

; ---------------------------------------------------------------------------
; canvas_timeline_signal
;   The timeline to a point (one it is past changes nothing)
;   IN:  rdi = conn, esi = timeline, rdx = point
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_timeline_signal
canvas_timeline_signal:
    sub rsp, 24
    mov [rsp], esi
    mov dword [rsp + 4], 0
    mov [rsp + 8], rdx
    mov esi, CWP_OBJ_TIMELINE
    mov edx, TIMELINE_SIGNAL
    mov rcx, rsp
    mov r8d, 16
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_buffer_set_timeline
;   Shown once the timeline reaches the acquire point; the timeline moved
;   to the release point when the server lets the buffer go; timeline 0
;   takes them off
;   IN:  rdi = conn, esi = buffer, edx = timeline, rcx = acquire point,
;        r8 = release point
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_buffer_set_timeline
canvas_buffer_set_timeline:
    sub rsp, 40
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], rcx
    mov [rsp + 16], r8
    mov esi, CWP_OBJ_BUFFER
    mov edx, BUFFER_SET_TIMELINE
    mov rcx, rsp
    mov r8d, 24
    call canvas_send
    add rsp, 40
    ret

; ---------------------------------------------------------------------------
; canvas_fence_wait
;   Until the fence is signaled
;   IN:  rdi = conn, esi = fence, rdx = the longest wait in ns (-1: no end)
;   OUT: rax = 0 signaled, -ETIMEDOUT, the negative error the server sent
; ---------------------------------------------------------------------------
global canvas_fence_wait
canvas_fence_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16                         ; a payload; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rdx
    call deadline
    mov r13, rax
    mov [rsp], r12d                     ; signaled already?
    mov rdi, rbx
    mov esi, CWP_OBJ_FENCE
    mov edx, FENCE_GET_STATUS
    mov rcx, rsp
    mov r8d, 4
    call canvas_call
    test rax, rax
    js .out
    cmp dword [rbx + CLIENT_WIRE + ClientWire.reply], 0
    jne .done
    xor r14d, r14d                      ; the point: none for a fence
.wait:
    mov rdi, rbx
    mov esi, CWP_OBJ_FENCE << 16 | FENCE_EV_FENCE_SIGNALED
    mov edx, r12d
    mov rcx, r14
    mov r8, r13
    call wait_for
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
.done:
    xor eax, eax
    jmp .out

; ---------------------------------------------------------------------------
; canvas_timeline_wait
;   Until the timeline reaches a point
;   IN:  rdi = conn, esi = timeline, rdx = point, rcx = the longest wait in
;        ns (-1: no end)
;   OUT: rax = 0 reached, -ETIMEDOUT, the negative error the server sent
; ---------------------------------------------------------------------------
global canvas_timeline_wait
canvas_timeline_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16                         ; a payload; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r14, rdx
    mov rdi, rcx
    call deadline
    mov r13, rax
    mov [rsp], r12d                     ; there already?
    mov rdi, rbx
    mov esi, CWP_OBJ_TIMELINE
    mov edx, TIMELINE_GET_POINT
    mov rcx, rsp
    mov r8d, 4
    call canvas_call
    test rax, rax
    js .out
    cmp [rbx + CLIENT_WIRE + ClientWire.reply], r14
    jae .done
    mov rdi, rbx
    mov esi, CWP_OBJ_TIMELINE << 16 | TIMELINE_EV_TIMELINE_SIGNALED
    mov edx, r12d
    mov rcx, r14
    mov r8, r13
    call wait_for
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
.done:
    xor eax, eax
    jmp .out

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = the longest wait in ns, -1 none -> rax = the monotonic time to give
; up at, -1 none
deadline:
    cmp rdi, -1
    je .none
    push rdi                            ; 16-byte aligned
    call ut_time_now_ns
    pop rdi
    add rax, rdi
    jnc .out
.none:
    mov rax, -1
.out:
    ret

; Read until the event esi (interface << 16 | event) about handle edx comes,
; for a timeline with a point at or past rcx (its payload: handle, pad,
; point); each event read is queued for canvas_event_poll.
; rdi = conn, r8 = the deadline (-1 none) -> rax = 0, -ETIMEDOUT
wait_for:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
.read:
    mov rdi, rbx
    call canvas_wire_read
    test rax, rax
    js .idle
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.in_hdr]
    test word [rcx + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .read                           ; an answer nobody waits for
    mov rdi, rbx                        ; every event stays the program's
    call canvas_wire_queue
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.in_hdr]
    mov eax, [rcx + MsgHdr.obj]
    shl eax, 16
    movzx edx, word [rcx + MsgHdr.opcode]
    or eax, edx
    cmp eax, r12d
    jne .read
    cmp [rbx + CLIENT_WIRE + ClientWire.in_msg], r13d
    jne .read
    cmp r12d, CWP_OBJ_TIMELINE << 16 | TIMELINE_EV_TIMELINE_SIGNALED
    jne .done
    cmp [rbx + CLIENT_WIRE + ClientWire.in_msg + 8], r14
    jb .read                            ; not that far yet
.done:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.idle:
    cmp r15, -1
    je .turn
    call ut_time_now_ns
    cmp rax, r15
    jae .timed_out
.turn:
    mov rax, [rbx + CLIENT_WIRE + ClientWire.pump]
    test rax, rax
    jz .yield
    mov rdi, [rbx + CLIENT_WIRE + ClientWire.pump_arg]
    call rax
    jmp .read
.yield:
    call ut_yield
    jmp .read
.timed_out:
    mov rax, -(ETIMEDOUT)
    jmp .out

section .data
global canvas_sync_helpers_version
canvas_sync_helpers_version: dq 0x010000
