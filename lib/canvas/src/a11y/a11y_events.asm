; ============================================================================
; A11y Events — Accessibility Event Dispatch
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/server_offsets.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

extern a11y_reader_hooks_notify

; struct offsets (hoisted above use)
%define A11Y_EVENT_FOCUS_CHANGED      1
%define A11Y_EVENT_STATE_CHANGED      2
%define A11Y_EVENT_NAME_CHANGED       3
%define A11Y_EVENT_DESCRIPTION_CHANGED 4
%define A11Y_EVENT_CHILDREN_CHANGED   5
%define A11Y_EVENT_ACTIVE_DESCENDANT_CHANGED 5
%define A11Y_EVENT_TEXT_CHANGED       6
%define A11Y_EVENT_SELECTION_CHANGED  7
%define A11Y_EVENT_VALUE_CHANGED      8
%define A11Y_EVENT_ROLE_CHANGED       8
%define A11Y_EVENT_LOCATION_CHANGED   9
%define A11Y_EVENT_WINDOW_OPENED      10
%define A11Y_EVENT_WINDOW_CLOSED      11

section .text


struc A11yEvent
    .type:      resd 1
    .node:      resq 1
    .detail1:   resd 1
    .detail2:   resd 1
    .time:      resq 1
    .next:      resq 1
endstruc

; ---------------------------------------------------------------------------
; a11y_events_init
; ---------------------------------------------------------------------------
global a11y_events_init
a11y_events_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.a11y_events], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_send
;   Send accessibility event
; ---------------------------------------------------------------------------
global a11y_event_send
a11y_event_send:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Allocate event
    mov rdi, [rbx + Server.arena]
    mov rsi, A11yEvent_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r15, rax

    mov dword [r15 + A11yEvent.type], r12d
    mov qword [r15 + A11yEvent.node], r13
    mov dword [r15 + A11yEvent.detail1], r14d
    mov dword [r15 + A11yEvent.detail2], r8d
    mov r10, [rbx + Server.a11y_events]
    mov [r15 + A11yEvent.next], r10
    mov [rbx + Server.a11y_events], r15
    call ut_time_now_ns
    mov qword [r15 + A11yEvent.time], rax

    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    mov rcx, r14
    call a11y_reader_hooks_notify
    xor rax, rax

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; a11y_event_focus_changed
; ---------------------------------------------------------------------------
global a11y_event_focus_changed
a11y_event_focus_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_FOCUS_CHANGED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_state_changed
; ---------------------------------------------------------------------------
global a11y_event_state_changed
a11y_event_state_changed:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_STATE_CHANGED
    mov rdx, r12
    mov ecx, r13d
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; a11y_event_name_changed
; ---------------------------------------------------------------------------
global a11y_event_name_changed
a11y_event_name_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_NAME_CHANGED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_children_changed
; ---------------------------------------------------------------------------
global a11y_event_children_changed
a11y_event_children_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_CHILDREN_CHANGED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_text_changed
; ---------------------------------------------------------------------------
global a11y_event_text_changed
a11y_event_text_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_TEXT_CHANGED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_selection_changed
; ---------------------------------------------------------------------------
global a11y_event_selection_changed
a11y_event_selection_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_SELECTION_CHANGED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_location_changed
; ---------------------------------------------------------------------------
global a11y_event_location_changed
a11y_event_location_changed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_LOCATION_CHANGED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_window_opened
; ---------------------------------------------------------------------------
global a11y_event_window_opened
a11y_event_window_opened:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_WINDOW_OPENED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; a11y_event_window_closed
; ---------------------------------------------------------------------------
global a11y_event_window_closed
a11y_event_window_closed:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rbx
    mov rsi, A11Y_EVENT_WINDOW_CLOSED
    mov rdx, r12
    mov rcx, 0
    call a11y_event_send
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global a11y_events_version
a11y_events_version: dq 0x010000
