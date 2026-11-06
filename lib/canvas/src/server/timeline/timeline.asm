; ============================================================================
; Timeline — Monotonic Sync Points (cw_timeline)
; ============================================================================
; A timeline is a 64-bit point that only goes up. A client makes timelines
; and gives a buffer one with two points (cw_buffer.set_timeline): the server
; shows the buffer only once the timeline has reached its acquire point
; (commit_surface waits), and moves the timeline to its release point when
; it lets the buffer go. Like a fence, each timeline is its client's: it
; lives in the client's arena, its handle resolves for that client only
; (timeline_own), and a client going takes its timelines with it. A timeline
; that is gone counts as having reached every point, so nothing waits on it
; for ever. Each time a timeline moves on, its client is sent
; timeline_signaled with the new point.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern sync_event
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_table_init

%define TIMELINE_HANDLES    1024

struc Timeline
    .handle:                  resd 1
    resb 4
    .point:                   resq 1    ; the latest point reached
    .client:                  resq 1    ; whose it is
    .next:                    resq 1    ; Client.timelines
endstruc

section .text

; ---------------------------------------------------------------------------
; timeline_init
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0, -ENOMEM
; ---------------------------------------------------------------------------
global timeline_init
timeline_init:
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
    mov edx, TIMELINE_HANDLES
    call handle_table_init
    test rax, rax
    js .out
    mov [rbx + Server.timeline_table], r13
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; timeline_create
;   A new timeline at point 0 for a client
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = its handle, -ENOMEM
; ---------------------------------------------------------------------------
global timeline_create
timeline_create:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [r12 + Client.arena]
    mov esi, Timeline_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Timeline_size
    rep stosb
    mov [r13 + Timeline.client], r12
    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r13
    call handle_create
    test rax, rax
    jz .oom
    mov [r13 + Timeline.handle], eax
    mov rcx, [r12 + Client.timelines]
    mov [r13 + Timeline.next], rcx
    mov [r12 + Client.timelines], r13
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; timeline_own
;   A client's own timeline from its handle
;   IN:  rdi = server*, rsi = client*, edx = handle
;   OUT: rax = Timeline*, 0 if there is no such timeline of that client's
; ---------------------------------------------------------------------------
global timeline_own
timeline_own:
    push rbx
    mov rbx, rsi
    mov rdi, [rdi + Server.timeline_table]
    test rdi, rdi
    jz .none
    mov esi, edx
    call handle_resolve
    test rax, rax
    jz .out
    cmp [rax + Timeline.client], rbx
    je .out
.none:
    xor eax, eax
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; timeline_destroy
;   A client's timeline goes; what waited on it goes on
;   IN:  rdi = server*, rsi = client*, edx = handle
;   OUT: rax = 0, -ENOENT if it is not that client's
; ---------------------------------------------------------------------------
global timeline_destroy
timeline_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call timeline_own
    test rax, rax
    jz .missing
    mov qword [rax + Timeline.point], -1
    lea rcx, [r12 + Client.timelines]   ; off the client's list
.find:
    mov rdx, [rcx]
    test rdx, rdx
    jz .unlinked
    cmp rdx, rax
    je .unlink
    lea rcx, [rdx + Timeline.next]
    jmp .find
.unlink:
    mov rdx, [rax + Timeline.next]
    mov [rcx], rdx
.unlinked:
    mov rdi, [rbx + Server.timeline_table]
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
; timeline_destroy_client
;   A client going: every handle of its timelines goes (their memory goes
;   with its arena)
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global timeline_destroy_client
timeline_destroy_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rsi + Client.timelines]
    mov qword [rsi + Client.timelines], 0
.next:
    test r12, r12
    jz .done
    mov rdi, [rbx + Server.timeline_table]
    mov esi, [r12 + Timeline.handle]
    call handle_destroy
    mov r12, [r12 + Timeline.next]
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; timeline_signal
;   The timeline reaches a point, and its client is sent
;   timeline_signaled(timeline, point); one it is past already changes
;   nothing and sends nothing
;   IN:  rdi = server*, esi = timeline handle, rdx = point
;   OUT: rax = 0, -ENOENT
; ---------------------------------------------------------------------------
global timeline_signal
timeline_signal:
    sub rsp, 24                         ; the event's payload; 16-byte aligned
    mov [rsp], esi
    mov dword [rsp + 4], 0
    mov [rsp + 8], rdx
    call resolve
    test rax, rax
    jz .missing
    mov rdx, [rsp + 8]
    cmp rdx, [rax + Timeline.point]
    jbe .done
    mov [rax + Timeline.point], rdx
    mov rdi, [rax + Timeline.client]
    mov esi, CWP_OBJ_TIMELINE
    mov edx, TIMELINE_EV_TIMELINE_SIGNALED
    mov rcx, rsp
    mov r8d, 16
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
; timeline_get_point
;   IN:  rdi = server*, esi = timeline handle
;   OUT: rax = its point; rdx = 0, -ENOENT with no such timeline
; ---------------------------------------------------------------------------
global timeline_get_point
timeline_get_point:
    sub rsp, 8
    call resolve
    add rsp, 8
    test rax, rax
    jz .missing
    mov rax, [rax + Timeline.point]
    xor edx, edx
    ret
.missing:
    mov rdx, -(ENOENT)
    ret

; ---------------------------------------------------------------------------
; timeline_reached
;   Whether what waits for a point may go on: the timeline is there or past
;   it, or there is no such timeline
;   IN:  rdi = server*, esi = timeline handle (0: none), rdx = point
;   OUT: rax = 1 reached, 0 still waiting
; ---------------------------------------------------------------------------
global timeline_reached
timeline_reached:
    test esi, esi
    jz .yes
    push rdx
    call resolve
    pop rdx
    test rax, rax
    jz .yes                             ; gone
    cmp [rax + Timeline.point], rdx
    jae .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server, esi = handle -> rax = Timeline*, 0 if none
resolve:
    mov rdi, [rdi + Server.timeline_table]
    test rdi, rdi
    jz .none
    jmp handle_resolve
.none:
    xor eax, eax
    ret

section .data
global timeline_version
timeline_version: dq 0x020000
