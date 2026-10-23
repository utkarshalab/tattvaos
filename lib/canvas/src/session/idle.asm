; ============================================================================
; Idle — Idle Detection and Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define IDLE_STATE_ACTIVE    0
%define IDLE_STATE_IDLE      1
%define IDLE_STATE_WARNING   2
%define DEFAULT_IDLE_TIMEOUT    300000000000  ; 5 minutes
%define DEFAULT_WARNING_TIME    30000000000   ; 30 seconds

section .text

; ---------------------------------------------------------------------------
; idle_init
;   Initialize idle manager
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global idle_init
idle_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi,r12
    mov rsi,IdleManager_SIZE
    call arena_alloc
    test rax,rax
    jz .oom
    mov [rax + IdleManager.server],rbx
    mov qword [rax + IdleManager.idle_timeout],DEFAULT_IDLE_TIMEOUT
    mov qword [rax + IdleManager.warning_time],DEFAULT_WARNING_TIME
    mov qword [rax + IdleManager.timer],0
    mov qword [rax + IdleManager.callbacks],0
    mov dword [rax + IdleManager.inhibit_count],0
    mov [rbx + Server.idle_manager],rax
    mov [rbx + Server.arena],r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx,r12
    ret

; ---------------------------------------------------------------------------
; idle_start_timer
;   Start idle timer
; ---------------------------------------------------------------------------
global idle_start_timer
idle_start_timer:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax,[rbx + IdleManager.timer]
    test rax,rax
    jz .arm
    mov rdi,rax
    call ut_timer_cancel
.arm:
    call ut_time_now_ns
    add rax,r12
    jc .invalid
    mov rdi,rax
    mov rsi,r13
    mov rdx,r14
    call ut_timer_register
    test rax,rax
    js .out
    mov [rbx + IdleManager.timer],rax
    xor eax,eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; idle_timeout_callback
;   Timer callback when idle timeout fires
; ---------------------------------------------------------------------------
global idle_timeout_callback
idle_timeout_callback:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    mov qword [rbx + IdleManager.timer],0
    cmp dword [rbx + IdleManager.inhibit_count],0
    jne .done
    mov r12,[rbx + IdleManager.callbacks]
.notify:
    test r12,r12
    jz .done
    mov rax,[r12]
    test rax,rax
    jz .next
    mov rdi,[r12+8]
    mov esi,IDLE_STATE_IDLE
    call rax
.next:
    mov r12,[r12+16]
    jmp .notify
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; idle_reset
;   Reset idle timer on user activity
; ---------------------------------------------------------------------------
global idle_reset
idle_reset:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax,[rbx + IdleManager.timer]
    test rax,rax
    jz .cleared
    mov rdi,rax
    call ut_timer_cancel
    mov qword [rbx + IdleManager.timer],0
.cleared:
    cmp dword [rbx + IdleManager.inhibit_count],0
    jne .done
    mov rdi,rbx
    mov rsi,[rbx + IdleManager.idle_timeout]
    lea rdx,[rel idle_timeout_callback]
    mov rcx,rbx
    call idle_start_timer
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; idle_inhibit
;   Inhibit idle detection
; ---------------------------------------------------------------------------
global idle_inhibit
idle_inhibit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp dword [rbx + IdleManager.inhibit_count],0x7fffffff
    jae .overflow
    inc dword [rbx + IdleManager.inhibit_count]
    mov rax,[rbx + IdleManager.timer]
    test rax,rax
    jz .done
    mov rdi,rax
    call ut_timer_cancel
    mov qword [rbx + IdleManager.timer],0
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.overflow:
    mov rax,-EOVERFLOW
    EPILOGUE_RESTORE rbx,r12
    ret

; ---------------------------------------------------------------------------
; idle_uninhibit
;   Allow idle detection again
; ---------------------------------------------------------------------------
global idle_uninhibit
idle_uninhibit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp dword [rbx + IdleManager.inhibit_count],0
    je .invalid
    dec dword [rbx + IdleManager.inhibit_count]
    jnz .done
    mov rdi,rbx
    xor esi,esi
    call idle_reset
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12
    ret

section .data
global idle_version
idle_version: dq 0x010000
