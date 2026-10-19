; ============================================================================
; User Session — Per-User Session Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define SESSION_STATE_INACTIVE    0
%define SESSION_STATE_ACTIVE      1
%define SESSION_STATE_CLOSING     2

section .text

; ---------------------------------------------------------------------------
; user_session_init
; ---------------------------------------------------------------------------
global user_session_init
user_session_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.user_sessions], 0
    mov qword [rbx + Server.session_count], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; user_session_create
; ---------------------------------------------------------------------------
global user_session_create
user_session_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r14,rbx

    ; Allocate session
    mov rdi,[r14 + Server.arena]
    mov rsi, UserSession_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov rax,[r14 + Server.next_session_id]
    inc qword [r14 + Server.next_session_id]
    mov qword [rbx + UserSession.session_id], rax
    mov qword [rbx + UserSession.user_id], r12
    mov qword [rbx + UserSession.seat], r13
    call tv_time_now_ns
    mov qword [rbx + UserSession.start_time], rax
    mov qword [rbx + UserSession.last_activity], rax
    mov dword [rbx + UserSession.state], SESSION_STATE_ACTIVE
    mov qword [rbx + UserSession.autostart_apps], 0
    mov qword [rbx + UserSession.env_vars], 0
    mov qword [rbx + UserSession.cwd], 0

    ; Add to list
    mov rax,[r14 + Server.user_sessions]
    mov [rbx + UserSession.next], rax
    mov [r14 + Server.user_sessions],rbx
    inc qword [r14 + Server.session_count]

    ; Launch autostart apps
    call user_session_launch_autostart

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; user_session_destroy
; ---------------------------------------------------------------------------
global user_session_destroy
user_session_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Set state to closing
    mov dword [r12 + UserSession.state], SESSION_STATE_CLOSING

    ; Detach the seat before unlinking so no new input or launches target it.
    mov rax,[r12 + UserSession.seat]
    test rax,rax
    jz .find
    mov rcx,[rax + Seat.session]
    cmp rcx,r12
    jne .find
    mov qword [rax + Seat.session],0
.find:
    xor r13d,r13d
    mov rax,[rbx + Server.user_sessions]
.loop:
    test rax,rax
    jz .missing
    cmp rax,r12
    je .unlink
    mov r13,rax
    mov rax,[rax + UserSession.next]
    jmp .loop
.unlink:
    mov rdx,[r12 + UserSession.next]
    test r13,r13
    jz .head
    mov [r13 + UserSession.next],rdx
    jmp .count
.head:
    mov [rbx + Server.user_sessions],rdx
.count:
    cmp qword [rbx + Server.session_count],0
    je .corrupt
    dec qword [rbx + Server.session_count]
    mov dword [r12 + UserSession.state],SESSION_STATE_INACTIVE
    mov qword [r12 + UserSession.autostart_apps],0
    xor eax,eax
    jmp .out
.missing:
    mov rax,-ENOENT
    jmp .out
.corrupt:
    mov rax,-EINVAL
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; user_session_get
; ---------------------------------------------------------------------------
global user_session_get
user_session_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Server.user_sessions]
.find_loop:
    test rax, rax
    jz .not_found
    cmp qword [rax + UserSession.session_id], r12
    je .found
    mov rax, [rax + UserSession.next]
    jmp .find_loop

.find_next:
    mov rax, [rax + UserSession.next]
    test rax, rax
    jnz .find_next

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.found:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; user_session_launch_autostart
; ---------------------------------------------------------------------------
user_session_launch_autostart:
    PROLOGUE_SAVE rbx,r12
    mov rbx,rdi
    ASSERT_PTR rbx
    cmp dword [rbx + UserSession.state],SESSION_STATE_ACTIVE
    jne .inactive
    ; The native session service populates this list and performs launches.
    ; Canvas records ownership; an empty list is a successful no-op.
    mov r12,[rbx + UserSession.autostart_apps]
    test r12,r12
    jz .ok
    ; Non-empty launch descriptors are handed to the kernel task service as
    ; (entry, argument, flags) triples followed by a next pointer.
.launch:
    mov rdi,[r12]
    mov rsi,[r12+8]
    mov rdx,[r12+16]
    call tv_task_spawn
    test rax,rax
    js .out
    mov r12,[r12+24]
    test r12,r12
    jnz .launch
.ok:
    xor eax,eax
.out:
    EPILOGUE_RESTORE rbx,r12
    ret
.inactive:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12
    ret

section .data
global user_session_version
user_session_version: dq 0x010000
