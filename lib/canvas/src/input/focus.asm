; ============================================================================
; Focus — Keyboard Focus Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define Focus_size    48
%define FOCUS_STATE_NONE    0
%define FOCUS_STATE_ENTER   1
%define FOCUS_STATE_LEAVE   2

section .text

struc Focus
    .seat:          resq 1
    .surface:       resq 1
    .serial:        resq 1
    .keys:          resq 1
    .modifiers:     resd 1
endstruc


; ---------------------------------------------------------------------------
; focus_init
; ---------------------------------------------------------------------------
global focus_init
focus_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, Focus_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Server.focus], rax

    mov qword [rax + Focus.seat], r12
    mov qword [rax + Focus.surface], 0
    mov qword [rax + Focus.serial], 0
    mov qword [rax + Focus.keys], 0
    mov dword [rax + Focus.modifiers], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; focus_set
;   Set keyboard focus to surface
; ---------------------------------------------------------------------------
global focus_set
focus_set:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Server.focus]
    test rax, rax
    jz .fail

    mov r14, [rax + Focus.surface]
    cmp r14, r12
    je .already_focused

    ; Leave current focus
    test r14, r14
    jz .set_new
    ; TODO: Send leave event

.set_new:
    mov [rax + Focus.surface], r12
    inc qword [rax + Focus.serial]

    ; TODO: Send enter event with serial

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.already_focused:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; focus_get
; ---------------------------------------------------------------------------
global focus_get
focus_get:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.focus]
    test rax, rax
    jz .none
    mov rax, [rax + Focus.surface]
    leave
    ret
.none:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; focus_get_serial
; ---------------------------------------------------------------------------
global focus_get_serial
focus_get_serial:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.focus]
    test rax, rax
    jz .none
    mov rax, [rax + Focus.serial]
    leave
    ret
.none:
    xor rax, rax
    leave
    ret

section .data
global focus_version
focus_version: dq 0x010000
