; ============================================================================
; Power Management — Suspend/Resume, Battery, AC Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc PowerManager {
    .server:            resq 1
    .suspend_inhibits:  resq 1
    .inhibit_count:     resd 1
    .suspend_callback:  resq 1
    .resume_callback:   resq 1
    .battery_callback:  resq 1
    .ac_callback:       resq 1
    .low_battery_pct:   resb 1
    .critical_pct:      resb 1
}
%define PowerManager_size    64

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

global power_init
power_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.power_manager], 0
    mov qword [rbx + Server.arena], r12

    mov rdi, r12
    mov rsi, PowerManager_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + PowerManager.server], rdi
    mov qword [rbx + PowerManager.suspend_inhibits], 0
    mov dword [rbx + PowerManager.inhibit_count], 0
    mov qword [rbx + PowerManager.suspend_callback], 0
    mov qword [rbx + PowerManager.resume_callback], 0
    mov qword [rbx + PowerManager.battery_callback], 0
    mov qword [rbx + PowerManager.ac_callback], 0
    mov byte [rbx + PowerManager.low_battery_pct], DEFAULT_LOW_BATTERY_PCT
    mov byte [rbx + PowerManager.critical_pct], DEFAULT_CRITICAL_BATTERY_PCT

    mov qword [rdi + Server.power_manager], rbx

    mov rdi, power_event_callback
    xor rsi, rsi
    call tv_power_register_callback
    test rax, rax
    jnz .fail

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM
.fail:
    RETURN_ERROR EIO

power_event_callback:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp r12d, POWER_EVENT_SUSPEND
    je .suspend
    cmp r12d, POWER_EVENT_RESUME
    je .resume
    cmp r12d, POWER_EVENT_HIBERNATE
    je .hibernate
    cmp r12d, POWER_EVENT_LOW_BATTERY
    je .low_battery
    cmp r12d, POWER_EVENT_AC_CHANGE
    je .ac_change
    cmp r12d, POWER_EVENT_BATTERY_CHANGE
    je .battery_change
    ret

.suspend:
    call power_handle_suspend
    ret

.resume:
    call power_handle_resume
    ret

.hibernate:
    call power_handle_hibernate
    ret

.low_battery:
    call power_handle_low_battery
    ret

.ac_change:
    call power_handle_ac_change
    ret

.battery_change:
    call power_handle_battery_change
    ret

power_handle_suspend:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + PowerManager.inhibit_count]
    test rax, rax
    jnz .abort_suspend

    mov rax, [rbx + PowerManager.suspend_callback]
    test rax, rax
    jz .proceed

    mov rdi, rbx
    call rax
    test rax, rax
    jz .abort_suspend

.proceed:
    call power_notify_suspend
    ret

.abort_suspend:
    mov rax, -EBUSY
    ret

power_handle_resume:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + PowerManager.resume_callback]
    test rax, rax
    jz .done

    mov rdi, rbx
    call rax

.done:
    call power_notify_resume
    ret

power_handle_hibernate:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    call power_handle_suspend
    ret

power_handle_low_battery:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + PowerManager.battery_callback]
    test rax, rax
    jz .done

    mov rdi, rbx
    call rax

.done:
    ret

power_handle_ac_change:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + PowerManager.ac_callback]
    test rax, rax
    jz .done

    mov rdi, rbx
    call rax

    ret

power_handle_battery_change:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + PowerManager.battery_callback]
    test rax, rax
    jz .done

    mov rdi, rbx
    call rax

    ret

power_notify_suspend:
    PROLOGUE
    ret

power_notify_resume:
    PROLOGUE
    ret

global power_inhibit_suspend
power_inhibit_suspend:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + PowerManager.suspend_inhibits]
    mov [r12 + 0], rax
    mov [rbx + PowerManager.suspend_inhibits], r12
    inc dword [rbx + PowerManager.inhibit_count]

    xor rax, rax
    ret

global power_uninhibit_suspend
power_uninhibit_suspend:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    dec dword [rbx + PowerManager.inhibit_count]

    xor rax, rax
    ret

global power_set_callbacks
power_set_callbacks:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    mov qword [rbx + PowerManager.suspend_callback], r12
    mov qword [rbx + PowerManager.resume_callback], r13
    xor rax, rax
    ret

global power_set_battery_callback
power_set_battery_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + PowerManager.battery_callback], rsi
    xor rax, rax
    ret

global power_set_ac_callback
power_set_ac_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + PowerManager.ac_callback], rsi
    xor rax, rax
    ret

global power_get_battery_status
power_get_battery_status:
    PROLOGUE
    ASSERT_PTR rdi

    call tv_power_battery_status
    ret

global power_set_thresholds
power_set_thresholds:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + PowerManager.low_battery_pct], sil
    mov byte [rbx + PowerManager.critical_pct], dl
    xor rax, rax
    ret

section .data

%define DEFAULT_LOW_BATTERY_PCT    10
%define DEFAULT_CRITICAL_BATTERY_PCT 5

global power_version
power_version: dq 0x010000