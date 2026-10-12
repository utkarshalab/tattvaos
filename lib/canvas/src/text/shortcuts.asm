; ============================================================================
; Global Shortcuts — Mediated Global Keyboard Shortcuts
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Shortcut {
    .keysym:        resd 1
    .modifiers:     resd 1
    .action:        resd 1
    .action_data:   resq 1
    .client:        resq 1
    .next:          resq 1
}
%define Shortcut_size    40

%define SHORTCUT_ACTION_NONE       0
%define SHORTCUT_ACTION_SPAWN      1
%define SHORTCUT_ACTION_COMMAND    2
%define SHORTCUT_ACTION_DBUS       3
%define SHORTCUT_ACTION_KEYSYM     4

%define SHORTCUT_MAX               256

; ---------------------------------------------------------------------------
; shortcuts_init
; ---------------------------------------------------------------------------
global shortcuts_init
shortcuts_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.shortcuts], 0
    mov qword [rbx + Server.shortcut_count], 0

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; shortcuts_register
;   Register a global shortcut
;   IN:  rdi = server*, rsi = client*, rdx = keysym, rcx = modifiers, r8 = action, r9 = action_data
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global shortcuts_register
shortcuts_register:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check limit
    mov rax, [rbx + Server.shortcut_count]
    cmp rax, SHORTCUT_MAX
    jae .full

    ; Check for duplicate
    mov rax, [rbx + Server.shortcuts]
.check_loop:
    test rax, rax
    jz .create
    cmp dword [rax + Shortcut.keysym], r13d
    jne .next
    cmp dword [rax + Shortcut.modifiers], r14d
    jne .next
    ; Duplicate
    RETURN_ERROR EEXIST

.next:
    mov rax, [rax + Shortcut.next]
    jmp .check_loop

.create:
    ; Allocate shortcut
    mov rdi, [rbx + Server.arena]
    mov rsi, Shortcut_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov dword [rbx + Shortcut.keysym], r13d
    mov dword [rbx + Shortcut.modifiers], r14d
    mov dword [rbx + Shortcut.action], r15d
    mov qword [rbx + Shortcut.action_data], r9
    mov qword [rbx + Shortcut.client], r12

    ; Add to list
    mov rax, [rdi + Server.shortcuts]
    mov [rbx + Shortcut.next], rax
    mov [rdi + Server.shortcuts], rbx
    inc qword [rdi + Server.shortcut_count]

    xor rax, rax
    ret

.full:
    RETURN_ERROR ENOSPC
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; shortcuts_unregister
; ---------------------------------------------------------------------------
global shortcuts_unregister
shortcuts_unregister:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx

    mov rax, [rdi + Server.shortcuts]
    test rax, rax
    jz .not_found
    cmp dword [rax + Shortcut.keysym], r13d
    jne .check_next
    cmp dword [rax + Shortcut.modifiers], r13d
    je .remove_head

    mov rbx, rax
.find_loop:
    mov rax, [rax + Shortcut.next]
    test rax, rax
    jz .not_found
    cmp dword [rax + Shortcut.keysym], r13d
    jne .next_iter
    cmp dword [rax + Shortcut.modifiers], r13d
    je .remove_middle

.next_iter:
    mov rbx, rax
    jmp .find_loop

.remove_head:
    mov rax, [rdi + Server.shortcuts]
    mov rsi, [rax + Shortcut.next]
    mov [rdi + Server.shortcuts], rsi
    jmp .done

.remove_middle:
    mov rax, [rax + Shortcut.next]
    mov [rbx + Shortcut.next], rax

.done:
    dec qword [rdi + Server.shortcut_count]
    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; shortcuts_process_key
;   Process key event for shortcuts
; ---------------------------------------------------------------------------
global shortcuts_process_key
shortcuts_process_key:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov rax, [rbx + Server.shortcuts]
    test rax, rax
    jz .done

.check_loop:
    cmp dword [rax + Shortcut.keysym], r12d
    jne .next
    cmp dword [rax + Shortcut.modifiers], r13d
    jne .next

    ; Match! Execute action
    mov r14, [rax + Shortcut.action]
    cmp r14d, SHORTCUT_ACTION_SPAWN
    je .action_spawn
    cmp r14d, SHORTCUT_ACTION_COMMAND
    je .action_command
    cmp r14d, SHORTCUT_ACTION_DBUS
    je .action_dbus
    cmp r14d, SHORTCUT_ACTION_KEYSYM
    je .action_keysym

    ret

.next:
    mov rax, [rax + Shortcut.next]
    test rax, rax
    jnz .check_loop

.done:
    xor rax, rax
    ret

.action_spawn:
    ; TODO: Spawn command
    ret

.action_command:
    ; TODO: Execute internal command
    ret

.action_dbus:
    ; TODO: Send DBus message
    ret

.action_keysym:
    ; TODO: Inject keysym
    ret

section .data
global shortcuts_version
shortcuts_version: dq 0x010000