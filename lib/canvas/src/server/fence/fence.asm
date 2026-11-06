; ============================================================================
; Fence — Binary Sync Primitive (cw_fence)
; ============================================================================
; A fence is unsignaled or signaled. A client makes fences and passes them
; with a buffer on attach: the server shows the buffer only once its acquire
; fence is signaled (commit_surface waits), and signals its release fence
; when it lets the buffer go. Each fence is its client's: it lives in the
; client's arena, its handle resolves for that client only (fence_own), and
; a client going takes its fences with it. A fence that is gone counts as
; signaled, so nothing waits on it for ever. When a fence becomes signaled
; its client is sent fence_signaled, so it need not ask (sync_event, which
; timelines use too).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern msgbuf_write
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_table_init

%define FENCE_HANDLES   1024

section .text

; ---------------------------------------------------------------------------
; fence_init
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0, -ENOMEM
; ---------------------------------------------------------------------------
global fence_init
fence_init:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    mov esi, 48
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    mov edx, FENCE_HANDLES
    call handle_table_init
    test rax, rax
    js .out
    mov [rbx + Server.fence_table], r13
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; fence_create
;   A new unsignaled fence for a client
;   IN:  rdi = server*, rsi = client*, edx = type (CPU 0, GPU 1)
;   OUT: rax = its handle, -ENOMEM
; ---------------------------------------------------------------------------
global fence_create
fence_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rdi, [r12 + Client.arena]
    mov esi, Fence_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Fence_size
    rep stosb
    mov [r14 + Fence.type], r13d
    mov [r14 + Fence.client], r12
    mov rax, [r12 + Client.id]
    mov [r14 + Fence.client_id], rax
    mov rdi, [rbx + Server.fence_table]
    mov rsi, r14
    call handle_create
    test rax, rax
    jz .oom
    mov [r14 + Fence.handle], eax
    mov rcx, [r12 + Client.fences]
    mov [r14 + Fence.next], rcx
    mov [r12 + Client.fences], r14
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; fence_own
;   A client's own fence from its handle
;   IN:  rdi = server*, rsi = client*, edx = handle
;   OUT: rax = Fence*, 0 if there is no such fence of that client's
; ---------------------------------------------------------------------------
global fence_own
fence_own:
    push rbx
    mov rbx, rsi
    mov rdi, [rdi + Server.fence_table]
    test rdi, rdi
    jz .none
    mov esi, edx
    call handle_resolve
    test rax, rax
    jz .out
    cmp [rax + Fence.client], rbx
    je .out
.none:
    xor eax, eax
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; fence_destroy
;   A client's fence goes; what waited on it goes on
;   IN:  rdi = server*, rsi = client*, edx = handle
;   OUT: rax = 0, -ENOENT if it is not that client's
; ---------------------------------------------------------------------------
global fence_destroy
fence_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call fence_own
    test rax, rax
    jz .missing
    mov dword [rax + Fence.signaled], 1
    lea rcx, [r12 + Client.fences]      ; off the client's list
.find:
    mov rdx, [rcx]
    test rdx, rdx
    jz .unlinked
    cmp rdx, rax
    je .unlink
    lea rcx, [rdx + Fence.next]
    jmp .find
.unlink:
    mov rdx, [rax + Fence.next]
    mov [rcx], rdx
.unlinked:
    mov rdi, [rbx + Server.fence_table]
    mov esi, r13d
    call handle_destroy
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.missing:
    mov rax, -(ENOENT)
    jmp .out

; ---------------------------------------------------------------------------
; fence_destroy_client
;   A client going: every handle of its fences goes (their memory goes with
;   its arena)
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global fence_destroy_client
fence_destroy_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rsi + Client.fences]
    mov qword [rsi + Client.fences], 0
.next:
    test r12, r12
    jz .done
    mov rdi, [rbx + Server.fence_table]
    mov esi, [r12 + Fence.handle]
    call handle_destroy
    mov r12, [r12 + Fence.next]
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; fence_signal
;   Signaled; the first time since it was made or reset, its client is
;   sent fence_signaled(fence)
;   IN:  rdi = server*, esi = fence handle
;   OUT: rax = 0, -ENOENT
; ---------------------------------------------------------------------------
global fence_signal
fence_signal:
    sub rsp, 24                         ; the event's payload; 16-byte aligned
    mov [rsp], esi
    call resolve
    test rax, rax
    jz .missing
    cmp dword [rax + Fence.signaled], 0
    jne .done
    mov dword [rax + Fence.signaled], 1
    mov rdi, [rax + Fence.client]
    mov esi, CWP_OBJ_FENCE
    mov edx, FENCE_EV_FENCE_SIGNALED
    mov rcx, rsp
    mov r8d, 4
    call sync_event
.done:
    xor eax, eax
    add rsp, 24
    ret
.missing:
    mov rax, -(ENOENT)
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; sync_event
;   An event about a fence or timeline to its client
;   IN:  rdi = client* (0: none, nothing sent), esi = CWP_OBJ_*, edx = the
;        event's opcode, rcx = its payload, r8d = the payload's length
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sync_event
sync_event:
    test rdi, rdi
    jz .none
    sub rsp, 24                         ; the header; 16-byte aligned
    mov [rsp + MsgHdr.obj], esi
    mov [rsp + MsgHdr.opcode], dx
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov [rsp + MsgHdr.len], r8d
    mov rdx, rcx
    mov rdi, [rdi + Client.rx_ring]
    mov rsi, rsp
    call msgbuf_write                   ; a full ring drops it
    add rsp, 24
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; fence_reset
;   Back to unsignaled
;   IN:  rdi = server*, rsi = fence handle
;   OUT: rax = 0, -ENOENT
; ---------------------------------------------------------------------------
global fence_reset
fence_reset:
    xor edx, edx
    jmp set_state

; ---------------------------------------------------------------------------
; fence_get_status
;   IN:  rdi = server*, rsi = fence handle
;   OUT: rax = 1 signaled, 0 not, -ENOENT
; ---------------------------------------------------------------------------
global fence_get_status
fence_get_status:
    sub rsp, 8
    call resolve
    add rsp, 8
    test rax, rax
    jz .missing
    mov eax, [rax + Fence.signaled]
    ret
.missing:
    mov rax, -(ENOENT)
    ret

; ---------------------------------------------------------------------------
; fence_ready
;   Whether what waits on a fence may go on: signaled, or no such fence
;   IN:  rdi = server*, esi = fence handle (0: none)
;   OUT: rax = 1 ready, 0 still waiting
; ---------------------------------------------------------------------------
global fence_ready
fence_ready:
    mov eax, 1
    test esi, esi
    jz .out
    sub rsp, 8
    call resolve
    add rsp, 8
    test rax, rax
    jz .gone
    mov eax, [rax + Fence.signaled]
    ret
.gone:
    mov eax, 1
.out:
    ret

; ---------------------------------------------------------------------------
; fence_wait
;   Wait for a fence, yielding meanwhile; for the backends, never for a
;   client's request
;   IN:  rdi = server*, rsi = fence handle, rdx = timeout ns (-1: none)
;   OUT: rax = 0 signaled, -ETIMEDOUT, -ENOENT
; ---------------------------------------------------------------------------
global fence_wait
fence_wait:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call resolve
    test rax, rax
    jz .missing
    mov [rsp], rax
    cmp dword [rax + Fence.signaled], 0
    jne .signaled
    cmp r13, -1
    je .wait
    call ut_time_now_ns
    add rax, r13
    jc .timed_out
    mov [rsp + 8], rax
.wait:
    call ut_yield
    mov rax, [rsp]
    cmp dword [rax + Fence.signaled], 0
    jne .signaled
    cmp r13, -1
    je .wait
    call ut_time_now_ns
    cmp rax, [rsp + 8]
    jb .wait
.timed_out:
    mov rax, -(ETIMEDOUT)
    jmp .out
.signaled:
    xor eax, eax
    jmp .out
.missing:
    mov rax, -(ENOENT)
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server, rsi = handle -> rax = Fence*, 0 if none
resolve:
    mov rdi, [rdi + Server.fence_table]
    test rdi, rdi
    jz .none
    jmp handle_resolve
.none:
    xor eax, eax
    ret

; rdi = server, rsi = handle, edx = 1 signaled / 0 not -> rax = 0, -ENOENT
set_state:
    push rdx
    call resolve
    pop rdx
    test rax, rax
    jz .missing
    mov [rax + Fence.signaled], edx
    xor eax, eax
    ret
.missing:
    mov rax, -(ENOENT)
    ret

section .data
global fence_version
fence_version: dq 0x020000
