; ============================================================================
; A11y Reader Hooks — Screen Reader Integration Points
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc A11yReaderHooks {
    .tree:              resq 1
    .seat:              resq 1
    .callbacks:         resq 1
    .callback_count:    resd 1
}
%define A11yReaderHooks_size    32

struc A11yCallback {
    .event_type:    resd 1
    .callback:      resq 1
    .user_data:     resq 1
    .next:          resq 1
}
%define A11yCallback_size    24

%define CALLBACK_FOCUS_CHANGED      1
%define CALLBACK_STATE_CHANGED      2
%define CALLBACK_NAME_CHANGED       3
%define CALLBACK_CHILDREN_CHANGED   4
%define CALLBACK_TEXT_CHANGED       5
%define CALLBACK_SELECTION_CHANGED  6
%define CALLBACK_LOCATION_CHANGED   7
%define CALLBACK_WINDOW_OPENED      8
%define CALLBACK_WINDOW_CLOSED      9

; ---------------------------------------------------------------------------
; a11y_reader_hooks_init
; ---------------------------------------------------------------------------
global a11y_reader_hooks_init
a11y_reader_hooks_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, A11yReaderHooks_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + A11yReaderHooks.tree], 0
    mov qword [rbx + A11yReaderHooks.seat], 0
    mov qword [rbx + A11yReaderHooks.callbacks], 0
    mov dword [rbx + A11yReaderHooks.callback_count], 0

    mov qword [rdi + Server.a11y_reader_hooks], rbx
    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; a11y_reader_hooks_register
;   Register callback for accessibility events
; ---------------------------------------------------------------------------
global a11y_reader_hooks_register
a11y_reader_hooks_register:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Allocate callback
    mov rdi, [rdi + Server.arena]
    mov rsi, A11yCallback_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov dword [rbx + A11yCallback.event_type], r12d
    mov qword [rbx + A11yCallback.callback], r13
    mov qword [rbx + A11yCallback.user_data], rcx
    mov qword [rbx + A11yCallback.next], 0

    ; Add to callback list
    mov rax, [rdi + Server.a11y_reader_hooks]
    mov rax, [rax + A11yReaderHooks.callbacks]
    mov [rbx + A11yCallback.next], rax
    mov qword [rdi + Server.a11y_reader_hooks + A11yReaderHooks.callbacks], rbx
    inc dword [rdi + Server.a11y_reader_hooks + A11yReaderHooks.callback_count]

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; a11y_reader_hooks_unregister
; ---------------------------------------------------------------------------
global a11y_reader_hooks_unregister
a11y_reader_hooks_unregister:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Remove from callback list
    ; TODO

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; a11y_reader_hooks_notify
;   Notify all registered callbacks
; ---------------------------------------------------------------------------
global a11y_reader_hooks_notify
a11y_reader_hooks_notify:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    mov rax, [rbx + Server.a11y_reader_hooks]
    test rax, rax
    jz .done

    mov rbx, [rax + A11yReaderHooks.callbacks]
    test rbx, rbx
    jz .done

.notify_loop:
    cmp dword [rbx + A11yCallback.event_type], r12d
    jne .next_callback

    ; Call callback
    mov rdi, [rbx + A11yCallback.callback]
    mov rsi, [rbx + A11yCallback.user_data]
    mov rdx, [rdi + Server.a11y_tree]
    call rdi

.next_callback:
    mov rbx, [rbx + A11yCallback.next]
    test rbx, rbx
    jnz .notify_loop

.done:
    xor rax, rax
    ret

section .data
global a11y_reader_hooks_version
a11y_reader_hooks_version: dq 0x010000