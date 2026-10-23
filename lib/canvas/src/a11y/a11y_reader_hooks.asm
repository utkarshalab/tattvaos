; ============================================================================
; A11y Reader Hooks — Screen Reader Integration Points
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/server_offsets.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define CALLBACK_FOCUS_CHANGED      1
%define CALLBACK_STATE_CHANGED      2
%define CALLBACK_NAME_CHANGED       3
%define CALLBACK_CHILDREN_CHANGED   4
%define CALLBACK_TEXT_CHANGED       5
%define CALLBACK_SELECTION_CHANGED  6
%define CALLBACK_LOCATION_CHANGED   7
%define CALLBACK_WINDOW_OPENED      8
%define CALLBACK_WINDOW_CLOSED      9

section .text

struc A11yReaderHooks
    .tree:              resq 1
    .seat:              resq 1
    .callbacks:         resq 1
    .callback_count:    resd 1
endstruc

struc A11yCallback
    .event_type:    resd 1
    .callback:      resq 1
    .user_data:     resq 1
    .next:          resq 1
endstruc


; ---------------------------------------------------------------------------
; a11y_reader_hooks_init
; ---------------------------------------------------------------------------
global a11y_reader_hooks_init
a11y_reader_hooks_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, A11yReaderHooks_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov qword [r13 + A11yReaderHooks.tree], 0
    mov qword [r13 + A11yReaderHooks.seat], r12
    mov qword [r13 + A11yReaderHooks.callbacks], 0
    mov dword [r13 + A11yReaderHooks.callback_count], 0

    mov qword [rbx + Server.a11y_reader_hooks], r13
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; a11y_reader_hooks_register
;   Register callback for accessibility events
; ---------------------------------------------------------------------------
global a11y_reader_hooks_register
a11y_reader_hooks_register:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Allocate callback
    mov rdi, [rbx + Server.arena]
    mov rsi, A11yCallback_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rdx, rax

    mov dword [rdx + A11yCallback.event_type], r12d
    mov qword [rdx + A11yCallback.callback], r13
    mov qword [rdx + A11yCallback.user_data], r14

    ; Add to callback list
    mov rax, [rbx + Server.a11y_reader_hooks]
    test rax, rax
    jz .oom
    mov rcx, [rax + A11yReaderHooks.callbacks]
    mov [rdx + A11yCallback.next], rcx
    mov [rax + A11yReaderHooks.callbacks], rdx
    inc dword [rax + A11yReaderHooks.callback_count]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; a11y_reader_hooks_unregister
; ---------------------------------------------------------------------------
global a11y_reader_hooks_unregister
a11y_reader_hooks_unregister:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Server.a11y_reader_hooks]
    test rax, rax
    jz .not_found
    lea rdx, [rax + A11yReaderHooks.callbacks]
.find:
    mov rcx, [rdx]
    test rcx, rcx
    jz .not_found
    cmp rcx, r12
    je .unlink
    lea rdx, [rcx + A11yCallback.next]
    jmp .find
.unlink:
    mov rcx, [rcx + A11yCallback.next]
    mov [rdx], rcx
    dec dword [rax + A11yReaderHooks.callback_count]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
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
    mov rax, [rbx + A11yCallback.callback]
    mov rdi, [rbx + A11yCallback.user_data]
    mov esi, r12d
    mov rdx, r13
    mov rcx, r14
    call rax

.next_callback:
    mov rbx, [rbx + A11yCallback.next]
    test rbx, rbx
    jnz .notify_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global a11y_reader_hooks_version
a11y_reader_hooks_version: dq 0x010000
