; ============================================================================
; Lock Screen — Session Locking with Authentication
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define LOCK_STATE_UNLOCKED    0
%define LOCK_STATE_LOCKED      1
%define LOCK_STATE_AUTHENTICATING 2
%define MAX_LOCK_ATTEMPTS    5
%define LOCKOUT_DURATION     30000000000  ; 30 seconds

section .text

; ---------------------------------------------------------------------------
; lock_init
;   Initialize lock subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global lock_init
lock_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.lock_screens], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; lock_create
;   Create lock screen for session
;   IN:  rdi = server*, rsi = session*, rdx = password_hash
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global lock_create
lock_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Allocate LockScreen
    mov rdi, [rbx + Server.arena]
    mov rsi, LockScreen_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax

    ; Initialize lock screen
    mov qword [r14 + LockScreen.session], r12
    mov qword [r14 + LockScreen.password_hash], r13
    mov dword [r14 + LockScreen.attempts], 0
    mov dword [r14 + LockScreen.max_attempts], MAX_LOCK_ATTEMPTS
    mov qword [r14 + LockScreen.lock_time], 0
    mov qword [r14 + LockScreen.unlock_callback], 0
    mov qword [r14 + LockScreen.user_data], 0
    mov dword [r14 + LockScreen.state],LOCK_STATE_LOCKED
    call ut_time_now_ns
    mov [r14 + LockScreen.lock_time],rax

    ; Create lock surface
    mov rdi, [rbx + Server.arena]
    mov rsi, 1920
    mov rdx, 1080
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [r14 + LockScreen.surface], rax

    ; Add to server's lock screens list
    mov rax, [rbx + Server.lock_screens]
    mov [r14 + LockScreen.next], rax
    mov [rbx + Server.lock_screens], r14

    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; lock_destroy
;   Destroy lock screen
; ---------------------------------------------------------------------------
global lock_destroy
lock_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find and remove from list
    mov rax, [rbx + Server.lock_screens]
    test rax, rax
    jz .done

    cmp rax, r12
    je .remove_head

    mov r13, rax
.find_loop:
    mov rax, [r13 + LockScreen.next]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_mid
    mov r13, rax
    jmp .find_loop

.remove_head:
    mov rax, [r12 + LockScreen.next]
    mov [rbx + Server.lock_screens], rax
    jmp .destroy

.remove_mid:
    mov rax, [r12 + LockScreen.next]
    mov [r13 + LockScreen.next], rax
    jmp .destroy

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.destroy:
    ; Destroy surface
    mov rdi, [r12 + LockScreen.surface]
    call pixbuf_destroy

    ; Free LockScreen
    mov rdi, [rbx + Server.arena]
    mov rsi, r12
    call arena_free

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; lock_authenticate
;   Attempt to unlock with password
; ---------------------------------------------------------------------------
global lock_authenticate
lock_authenticate:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Check state
    mov al, [r12 + LockScreen.state]
    cmp al, LOCK_STATE_LOCKED
    jne .not_locked

    ; Check attempts
    mov eax, [r12 + LockScreen.attempts]
    cmp eax, [r12 + LockScreen.max_attempts]
    jl .verify
    call ut_time_now_ns
    sub rax,[r12 + LockScreen.lock_time]
    cmp rax,LOCKOUT_DURATION
    jb .lockout
    mov dword [r12 + LockScreen.attempts],0
.verify:

    ; Verify password hash
    mov rdi, r13
    mov rsi, [r12 + LockScreen.password_hash]
    call verify_password
    test rax, rax
    jz .wrong_password

    ; Success - unlock
    mov byte [r12 + LockScreen.state], LOCK_STATE_UNLOCKED
    mov dword [r12 + LockScreen.attempts], 0

    ; Call unlock callback
    mov rax, [r12 + LockScreen.unlock_callback]
    test rax, rax
    jz .done
    mov rdi, [r12 + LockScreen.user_data]
    call rax

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.wrong_password:
    inc dword [r12 + LockScreen.attempts]
    mov eax,[r12 + LockScreen.attempts]
    cmp eax,[r12 + LockScreen.max_attempts]
    jl .denied
    call ut_time_now_ns
    mov [r12 + LockScreen.lock_time],rax
.denied:
    mov rax, -(EACCES)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.lockout:
    mov rax, -(EPERM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.not_locked:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; verify_password
;   Verify password against hash
; ---------------------------------------------------------------------------
global verify_password
verify_password:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Credentials arrive pre-hashed by the trusted authentication service.
    ; Compare the encoded hashes without data-dependent early exit.
    xor ecx,ecx
    xor r8d,r8d
.compare:
    mov al,[rbx+rcx]
    mov dl,[r12+rcx]
    mov r9b,al
    xor r9b,dl
    or r8b,r9b
    test al,al
    setnz r10b
    test dl,dl
    setnz r11b
    or r10b,r11b
    jz .compared
    inc rcx
    cmp rcx,4096
    jb .compare
    or r8b,1
.compared:
    xor eax,eax
    test r8b,r8b
    setz al
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global lock_version
lock_version: dq 0x010000
