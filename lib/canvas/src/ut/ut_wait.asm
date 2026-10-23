; ============================================================================
; Utkarsha Wait Service Binding — ut_wait.asm
; Event wait, yield, waitsets (like epoll but simpler)
; ============================================================================

%define UT_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

; ---------------------------------------------------------------------------
; ut_waitset_create
;   Create a new waitset
;   OUT: rax = waitset_handle (>0), negative error
; ---------------------------------------------------------------------------
global ut_waitset_create
ut_waitset_create:
    PROLOGUE
    mov rax, SYS_WAITSET_CREATE
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_waitset_add
;   Add event source to waitset
;   IN:  rdi = waitset_handle
;        rsi = event_type (WAIT_IRQ, WAIT_CHANNEL, WAIT_TIMER, WAIT_TASK, WAIT_INPUT)
;        rdx = source_id (irq number, channel handle, timer_id, task_id, input_dev_id)
;        rcx = trigger_mask (event-specific)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ut_waitset_add
ut_waitset_add:
    PROLOGUE_SAVE rbx, r12, r13
    mov rax, SYS_WAITSET_ADD
    syscall
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; ut_waitset_remove
;   Remove event source from waitset
;   IN:  rdi = waitset_handle
;        rsi = event_type
;        rdx = source_id
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global ut_waitset_remove
ut_waitset_remove:
    PROLOGUE_SAVE rbx
    mov rax, SYS_WAITSET_REMOVE
    syscall
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; ut_wait_wait
;   Wait for events on waitset
;   IN:  rdi = waitset_handle
;        rsi = deadline_ns (0 = infinite, -1 = poll/non-blocking)
;   OUT: rax = triggered_event_mask (bitmask of event types), negative error
; ---------------------------------------------------------------------------
global ut_wait_wait
ut_wait_wait:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, SYS_WAIT_WAIT
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; ut_wait_yield
;   Yield CPU to other tasks (cooperative)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global ut_wait_yield
ut_wait_yield:
    PROLOGUE
    mov rax, SYS_WAIT_YIELD
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_wait_wake_task
;   Wake specific task by task_id
;   IN:  rdi = task_id
;   OUT: rax = 0 OK, ESRCH if not found
; ---------------------------------------------------------------------------
global ut_wait_wake_task
ut_wait_wake_task:
    PROLOGUE
    mov rax, SYS_WAIT_WAKE_TASK
    syscall
    EPILOGUE

section .data

global ut_wait_version
ut_wait_version: dq 0x010000

section .note.ut_contract
    db "UT_WAIT_CONTRACT", 0
