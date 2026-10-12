; ============================================================================
; A11y Events — Accessibility Event Dispatch
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

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

struc A11yEvent {
    .type:      resd 1
    .node:      resq 1
    .detail1:   resd 1
    .detail2:   resd 1
    .time:      resq 1
}
%define A11yEvent_size    32

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
    ret

; ---------------------------------------------------------------------------
; a11y_event_send
;   Send accessibility event
; ---------------------------------------------------------------------------
global a11y_event_send
a11y_event_send:
    PROLOGUE_SAVE rbx, r12, r13, r14
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
    mov rbx, rax

    mov dword [rbx + A11yEvent.type], r12d
    mov qword [rbx + A11yEvent.node], r13
    mov dword [rbx + A11yEvent.detail1], r14d
    mov dword [rbx + A11yEvent.detail2], r8d
    call tv_time_now_ns
    mov qword [rbx + A11yEvent.time], rax

    ; Queue event for AT clients
    ; TODO: Add to event queue

    ret

.oom:
    RETURN_ERROR ENOMEM

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
    mov rcx, r13d
    call a11y_event_send
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
    ret

section .data
global a11y_events_version
a11y_events_version: dq 0x010000