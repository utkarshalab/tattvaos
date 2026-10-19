; ============================================================================
; Power Management — Suspend/Resume, Battery, AC Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define POWER_EVENT_SUSPEND      1
%define POWER_EVENT_RESUME       2
%define POWER_EVENT_HIBERNATE    3
%define POWER_EVENT_LOW_BATTERY  4
%define POWER_EVENT_AC_CHANGE    5
%define POWER_EVENT_BATTERY_CHANGE 6
%define INHIBIT_SUSPEND       (1 << 0)
%define INHIBIT_HIBERNATE     (1 << 1)
%define INHIBIT_IDLE          (1 << 2)
%define INHIBIT_HANDLE_POWER  (1 << 3)
%define DEFAULT_LOW_BATTERY_PCT    10
%define DEFAULT_CRITICAL_BATTERY_PCT 5

section .text

; ---------------------------------------------------------------------------
; power_init
;   Initialize power management
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global power_init
power_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi,r12
    mov rsi,PowerManager_SIZE
    call arena_alloc
    test rax,rax
    jz .oom
    mov [rax + PowerManager.server],rbx
    mov qword [rax + PowerManager.inhibit_mask],0
    mov qword [rax + PowerManager.suspend_callback],0
    mov qword [rax + PowerManager.resume_callback],0
    mov dword [rax + PowerManager.battery_level],100
    mov byte [rax + PowerManager.ac_connected],1
    mov byte [rax + PowerManager.suspending],0
    mov [rbx + Server.power_manager],rax
    mov [rbx + Server.arena],r12
    lea rdi,[rel power_event_callback]
    mov rsi,rax
    mov rax,SYS_POWER_REG_CB
    syscall
    test rax,rax
    js .register_fail

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx,r12
    ret
.register_fail:
    mov qword [rbx + Server.power_manager],0
    EPILOGUE_RESTORE rbx,r12
    ret

; ---------------------------------------------------------------------------
; power_event_callback
;   Handle power events from kernel
; ---------------------------------------------------------------------------
global power_event_callback
power_event_callback:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    cmp r12,POWER_EVENT_SUSPEND
    je .suspend
    cmp r12,POWER_EVENT_HIBERNATE
    je .suspend
    cmp r12,POWER_EVENT_RESUME
    je .resume
    cmp r12,POWER_EVENT_LOW_BATTERY
    je .battery
    cmp r12,POWER_EVENT_BATTERY_CHANGE
    je .battery
    cmp r12,POWER_EVENT_AC_CHANGE
    je .ac
    mov rax,-EINVAL
    jmp .done
.suspend:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call power_handle_suspend
    jmp .done
.resume:
    mov byte [rbx + PowerManager.suspending],0
    mov rax,[rbx + PowerManager.resume_callback]
    test rax,rax
    jz .ok
    mov rdi,[rbx + PowerManager.server]
    call rax
    jmp .ok
.battery:
    cmp r13,100
    ja .invalid
    mov [rbx + PowerManager.battery_level],r13d
    jmp .ok
.ac:
    test r13,r13
    setnz al
    mov [rbx + PowerManager.ac_connected],al
.ok:
    xor eax,eax
    jmp .done
.invalid:
    mov rax,-EINVAL
.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; power_handle_suspend
;   Handle system suspend
; ---------------------------------------------------------------------------
global power_handle_suspend
power_handle_suspend:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    cmp byte [rbx + PowerManager.suspending],0
    jne .already
    mov rax,[rbx + PowerManager.inhibit_mask]
    test rax,INHIBIT_SUSPEND | INHIBIT_HIBERNATE
    jnz .busy
    mov byte [rbx + PowerManager.suspending],1
    mov rax,[rbx + PowerManager.suspend_callback]
    test rax,rax
    jz .ok
    mov rdi,[rbx + PowerManager.server]
    mov rsi,r12
    mov rdx,r13
    call rax
    test rax,rax
    jnz .callback_failed
.ok:
    xor eax,eax
    jmp .out
.callback_failed:
    mov byte [rbx + PowerManager.suspending],0
    jmp .out
.busy:
    mov rax,-EBUSY
    jmp .out
.already:
    mov rax,-EALREADY
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global power_version
power_version: dq 0x010000
