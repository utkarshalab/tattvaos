; ============================================================================
; Seat Session — Per-Seat Session Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

; ---------------------------------------------------------------------------
; seat_session_init
; ---------------------------------------------------------------------------
global seat_session_init
seat_session_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, SeatSession_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + SeatSession.seat], r12
    mov qword [rbx + SeatSession.user_id], 0
    mov byte [rbx + SeatSession.active], 0
    mov byte [rbx + SeatSession.locked], 0
    mov qword [rbx + SeatSession.lock_surface], 0
    mov qword [rbx + SeatSession.idle_timer], 0
    mov qword [rbx + SeatSession.idle_timeout], 300000000000  ; 5 minutes
    mov dword [rbx + SeatSession.inhibit_count], 0
    mov qword [rbx + SeatSession.power_inhibit], 0

    mov qword [r12 + Seat.session_session], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; seat_session_start
; ---------------------------------------------------------------------------
global seat_session_start
seat_session_start:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov byte [rbx + SeatSession.active], 1
    mov qword [rbx + SeatSession.user_id], r12

    ; Start idle timer
    call seat_session_start_idle_timer

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; seat_session_start_idle_timer
; ---------------------------------------------------------------------------
seat_session_start_idle_timer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + SeatSession.idle_timer]
    test rax, rax
    jz .create_timer

    ; Timer already exists
    EPILOGUE_RESTORE rbx
    ret

.create_timer:
    call tv_time_now_ns
    add rax,[rbx + SeatSession.idle_timeout]
    jc .invalid
    mov rdi,rax
    mov rsi, seat_session_idle_callback
    mov rdx, rbx
    call tv_timer_register
    test rax,rax
    js .fail
    mov [rbx + SeatSession.idle_timer], rax
    EPILOGUE_RESTORE rbx
    ret

.fail:
    EPILOGUE_RESTORE rbx
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; seat_session_idle_callback
; ---------------------------------------------------------------------------
seat_session_idle_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Lock the session
    call seat_session_lock

    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; seat_session_lock
; ---------------------------------------------------------------------------
global seat_session_lock
seat_session_lock:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp byte [rbx + SeatSession.locked], 1
    je .already_locked

    mov byte [rbx + SeatSession.locked], 1

    mov rax,[rbx + SeatSession.seat]
    mov rax,[rax + Seat.shell]
    test rax,rax
    jz .rollback
    mov rdi,[rax + Shell.arena]
    mov esi,1920
    mov edx,1080
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .rollback
    mov [rbx + SeatSession.lock_surface],rax
    mov rdi,[rax + PixBuf.data]
    mov esi,0xFF101010
    mov edx,[rax + PixBuf.width]
    mov ecx,[rax + PixBuf.height]
    mov r8,[rax + PixBuf.stride]
    call fill_solid

    ; Notify policy
    mov rax, [rbx + SeatSession.seat]
    mov rax, [rax + Seat.shell]
    test rax,rax
    jz .done
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_session_lock

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.rollback:
    mov byte [rbx + SeatSession.locked],0
    mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx
    ret

.already_locked:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; seat_session_unlock
; ---------------------------------------------------------------------------
global seat_session_unlock
seat_session_unlock:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp byte [rbx + SeatSession.locked], 0
    je .not_locked

    mov byte [rbx + SeatSession.locked], 0

    mov rdi,[rbx + SeatSession.lock_surface]
    test rdi,rdi
    jz .notify
    call pixbuf_destroy
    mov qword [rbx + SeatSession.lock_surface],0

    ; Notify policy
.notify:
    mov rax, [rbx + SeatSession.seat]
    mov rax, [rax + Seat.shell]
    test rax,rax
    jz .done
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_session_unlock

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.not_locked:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; seat_session_inhibit_idle
; ---------------------------------------------------------------------------
global seat_session_inhibit_idle
seat_session_inhibit_idle:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    inc dword [rbx + SeatSession.inhibit_count]

    ; Cancel idle timer
    mov rax, [rbx + SeatSession.idle_timer]
    test rax, rax
    jz .done
    mov rdi, rax
    call tv_timer_cancel
    mov qword [rbx + SeatSession.idle_timer], 0

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; seat_session_uninhibit_idle
; ---------------------------------------------------------------------------
global seat_session_uninhibit_idle
seat_session_uninhibit_idle:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp dword [rbx + SeatSession.inhibit_count],0
    je .underflow
    dec dword [rbx + SeatSession.inhibit_count]
    cmp dword [rbx + SeatSession.inhibit_count],0
    jne .done

    ; Restart idle timer
    call seat_session_start_idle_timer

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.underflow:
    mov dword [rbx + SeatSession.inhibit_count], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global seat_session_version
seat_session_version: dq 0x010000
