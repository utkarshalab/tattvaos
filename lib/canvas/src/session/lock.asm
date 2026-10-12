; ============================================================================
; Lock Screen — Session Locking with Authentication
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc LockScreen {
    .session:         resq 1
    .surface:         resq 1
    .password_hash:   resq 1
    .attempts:        resd 1
    .max_attempts:    resd 1
    .lock_time:       resq 1
    .unlock_callback: resq 1
    .user_data:       resq 1
}
%define LockScreen_size    64

%define LOCK_STATE_UNLOCKED    0
%define LOCK_STATE_LOCKED      1
%define LOCK_STATE_AUTHENTICATING 2

%define MAX_LOCK_ATTEMPTS    5
%define LOCKOUT_DURATION     30000000000  ; 30 seconds

; ---------------------------------------------------------------------------
; lock_init
; ---------------------------------------------------------------------------
global lock_init
lock_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.lock_screens], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; lock_create
;   Create lock screen for session
; ---------------------------------------------------------------------------
global lock_create
lock_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate lock screen
    mov rdi, [rbx + Server.arena]
    mov rsi, LockScreen_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + LockScreen.session], r12
    mov qword [rbx + LockScreen.password_hash], r13
    mov dword [rbx + LockScreen.attempts], 0
    mov dword [rbx + LockScreen.max_attempts], MAX_LOCK_ATTEMPTS
    mov qword [rbx + LockScreen.lock_time], 0
    mov qword [rbx + LockScreen.unlock_callback], 0
    mov qword [rbx + LockScreen.user_data], 0

    ; Create lock surface
    mov rdi, [rbx + Server.arena]
    mov rsi, 1920
    mov rdx, 1080
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [rbx + LockScreen.surface], rax

    ; Draw lock screen
    call lock_draw

    ; Grab input
    call lock_grab_input

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; lock_destroy
; ---------------------------------------------------------------------------
global lock_destroy
lock_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Release input grab
    call lock_ungrab_input

    ; Destroy surface
    mov rax, [rbx + LockScreen.surface]
    test rax, rax
    jz .done
    mov rdi, rax
    call pixbuf_destroy

.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; lock_authenticate
;   Attempt to unlock with password
; ---------------------------------------------------------------------------
global lock_authenticate
lock_authenticate:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Verify password hash
    mov rax, [rbx + LockScreen.password_hash]
    test rax, rax
    jz .no_hash

    ; TODO: Verify password against hash
    ; For now, accept any non-empty password
    cmp r13, 0
    je .wrong_password

    ; Success
    mov dword [rbx + LockScreen.attempts], 0
    call lock_unlock
    xor rax, rax
    ret

.no_hash:
    ; No password set - allow
    call lock_unlock
    xor rax, rax
    ret

.wrong_password:
    inc dword [rbx + LockScreen.attempts]
    cmp dword [rbx + LockScreen.attempts], MAX_LOCK_ATTEMPTS
    jge .lockout

    ; TODO: Send failed attempt event
    xor rax, rax
    ret

.lockout:
    ; Too many attempts - lock out
    call tv_time_now_ns
    add rax, LOCKOUT_DURATION
    mov [rdi + LockScreen.lockout_until], rax
    RETURN_ERROR EPERM

; ---------------------------------------------------------------------------
; lock_unlock
; ---------------------------------------------------------------------------
lock_unlock:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Call unlock callback
    mov rax, [rbx + LockScreen.unlock_callback]
    test rax, rax
    jz .no_callback
    mov rdi, [rbx + LockScreen.user_data]
    call rax

.no_callback:
    ; Destroy lock screen
    call lock_destroy
    ret

; ---------------------------------------------------------------------------
; lock_grab_input
; ---------------------------------------------------------------------------
lock_grab_input:
    PROLOGUE
    ; TODO: Grab pointer and keyboard
    ret

; ---------------------------------------------------------------------------
; lock_ungrab_input
; ---------------------------------------------------------------------------
lock_ungrab_input:
    PROLOGUE
    ; TODO: Release input grab
    ret

; ---------------------------------------------------------------------------
; lock_draw
; ---------------------------------------------------------------------------
lock_draw:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Draw lock screen UI
    mov rax, [rbx + LockScreen.surface]
    test rax, rax
    jz .done

    ; Fill with dark background
    mov rdi, [rax + PixBuf.data]
    mov rsi, 0xFF1A1A2E  ; Dark blue-gray
    mov rdx, [rax + PixBuf.width]
    mov rcx, [rax + PixBuf.height]
    mov r8, [rax + PixBuf.stride]
    call fill_solid

    ; Draw lock icon, time, password prompt
    ; TODO: Draw UI elements

.done:
    ret

section .data
global lock_version
lock_version: dq 0x010000